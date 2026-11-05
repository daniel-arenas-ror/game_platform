#!/usr/bin/env bash
# How busy the server is: request times from Caddy's access log (p50/p95/p99, slowest pages), memory,
# and CPU + CPU credits over the last 7 days. Read-only.
# Usage: script/aws_latency.sh
set -euo pipefail
cd "$(dirname "$0")/.."

tf() { terraform -chdir=terraform output -raw "$1"; }
REGION=$(tf aws_region)
INSTANCE_ID=$(tf instance_id)

# Turns log lines into "seconds status path" (websockets stay open for minutes, so /cable is left out),
# groups rooms by page, and prints the totals and the 15 slowest pages by p95.
REPORT=$(cat <<'SH' | base64 | tr -d '\n'
sed -E 's/.*"uri":"([^"?]*)[^"]*".*"duration":([0-9.e-]+).*"status":([0-9]+).*/\2 \3 \1/' |
  grep -v " /cable" | sed -E 's#/(rooms|join)/[A-Z0-9]{4}#/\1/:code#' | sort -g |
  awk '{t[NR]=$1; n[$3]++; s[$3]=s[$3]" "$1; if($2>=500)e++}
    END {printf "requests=%d p50=%.3fs p95=%.3fs p99=%.3fs max=%.3fs 5xx=%d\n",NR,t[int(NR*.5)+1],t[int(NR*.95)+1],t[int(NR*.99)+1],t[NR],e
      print "p50 p95 count path"
      for(p in n){if(n[p]<5)continue; m=split(s[p],a," ")
        printf "%.3f %.3f %d %s\n",a[int(m*.5)+1],a[int(m*.95)+1],n[p],p | "sort -k2 -g -r | head -15"}}'
SH
)

script/aws_run.sh "echo $REPORT | base64 -d > /tmp/latency_report.sh
echo '== requests'
docker exec \$(docker ps -qf name=caddy | head -1) sh -c 'cat /data/logs/access.log; zcat /data/logs/*.gz 2>/dev/null; true' | sh /tmp/latency_report.sh
echo '== memory'; free -m
echo '== containers'; docker stats --no-stream --format '{{.Name}} cpu={{.CPUPerc}} mem={{.MemUsage}}'
echo '== load'; uptime
rm -f /tmp/latency_report.sh"

echo "== last 7 days (t4g.micro CPU credits max out at 288; near 0 means the CPU gets throttled)"
for metric in "CPUUtilization Maximum" "CPUCreditBalance Minimum"; do
  set -- $metric
  aws cloudwatch get-metric-statistics --region "$REGION" --namespace AWS/EC2 --metric-name "$1" \
    --dimensions "Name=InstanceId,Value=$INSTANCE_ID" --statistics "$2" --period 3600 \
    --start-time "$(date -u -v-7d +%Y-%m-%dT%H:%M:%SZ)" --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" |
    jq -r --arg m "$1" --arg s "$2" '[.Datapoints[][$s]] | "\($m): lowest \(min), highest \(max) (hourly \($s))"'
done
