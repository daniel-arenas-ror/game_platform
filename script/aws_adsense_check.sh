#!/usr/bin/env bash
# What Google's ad crawlers got from us, and whether the server had trouble. Read-only.
# Reads Caddy's access log (up to 30 days), container restarts, OOM kills, memory and CPU credits.
# Usage: script/aws_adsense_check.sh [days]   (default 30)
set -euo pipefail
cd "$(dirname "$0")/.."

DAYS=${1:-30}
tf() { terraform -chdir=terraform output -raw "$1"; }
REGION=$(tf aws_region)
INSTANCE_ID=$(tf instance_id)

# Python on the host turns Caddy's JSON lines into: crawler hits per day, every non-2xx/3xx answer they
# got, slow answers to them, and 5xx answers to anyone grouped by hour (a 502 burst = the app was down).
REPORT=$(cat <<'PY' | base64 | tr -d '\n'
import json, sys, time, collections
days = int(sys.argv[1]); since = time.time() - days * 86400
BOTS = ("Mediapartners-Google", "Google-Display-Ads-Bot", "AdsBot-Google", "Google-Adwords", "Googlebot", "Google-InspectionTool", "Google-Site-Verification")
hits = collections.Counter(); bad = []; slow = []; err5 = collections.Counter(); first5 = {}
for line in sys.stdin:
    try: d = json.loads(line)
    except Exception: continue
    ts = d.get("ts", 0)
    if ts < since: continue
    r = d.get("request", {}); st = d.get("status", 0); dur = d.get("duration", 0)
    ua = (r.get("headers", {}).get("User-Agent") or [""])[0]
    when = time.strftime("%m-%d %H:%M:%S", time.gmtime(ts))
    bot = next((b for b in BOTS if b in ua), None)
    if bot:
        hits[(time.strftime("%m-%d", time.gmtime(ts)), bot, r.get("host"), st)] += 1
        if st >= 400 or st == 0: bad.append(f"{when} {bot} {st} {r.get('host')}{r.get('uri')}")
        if dur > 5: slow.append(f"{when} {bot} {dur:.1f}s {st} {r.get('host')}{r.get('uri')}")
    if st >= 500:
        h = time.strftime("%m-%d %H:00", time.gmtime(ts)); err5[(h, st)] += 1
        first5.setdefault((h, st), f"{when} {r.get('uri','')[:60]}")
print("== Google crawler hits (UTC day, bot, host, status: count)")
for k in sorted(hits): print(*k, ":", hits[k])
print("\n== Crawler requests that got an error"); print("\n".join(bad[-80:]) or "none")
print("\n== Crawler requests slower than 5s"); print("\n".join(slow[-40:]) or "none")
print("\n== 5xx to anyone, per UTC hour (502/503/504 = app down or restarting)")
for k in sorted(err5): print(*k, ":", err5[k], " first:", first5[k])
if not err5: print("none")
PY
)

script/aws_run.sh "echo $REPORT | base64 -d > /tmp/adsense_report.py
C=\$(docker ps -qf name=caddy | head -1)
docker exec \$C sh -c 'zcat /data/logs/*.gz 2>/dev/null; cat /data/logs/access.log' | python3 /tmp/adsense_report.py $DAYS
rm -f /tmp/adsense_report.py
echo; echo '== containers (Status shows time since the last start)'
docker ps --format '{{.Names}}  {{.Status}}'
for c in \$(docker ps -q); do docker inspect -f '{{.Name}} restarts={{.RestartCount}} started={{.State.StartedAt}} oomkilled={{.State.OOMKilled}}' \$c; done
echo; echo '== OOM kills (kernel log)'; journalctl -k --since '$DAYS days ago' --no-pager 2>/dev/null | grep -i -E 'out of memory|oom-kill|killed process' | tail -20 || true
echo; echo '== memory'; free -m; echo; uptime"

echo
echo "== CPU credits, last 7 days (t4g.micro; near 0 = CPU throttled, the site slows to a crawl)"
for metric in "CPUCreditBalance Minimum" "CPUUtilization Maximum" "StatusCheckFailed Maximum"; do
  set -- $metric
  aws cloudwatch get-metric-statistics --region "$REGION" --namespace AWS/EC2 --metric-name "$1" \
    --dimensions "Name=InstanceId,Value=$INSTANCE_ID" --statistics "$2" --period 3600 \
    --start-time "$(date -u -v-7d +%Y-%m-%dT%H:%M:%SZ)" --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" |
    jq -r --arg m "$1" --arg s "$2" '[.Datapoints[][$s]] | "\($m): lowest \(min), highest \(max) (hourly \($s))"'
done
