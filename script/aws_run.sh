#!/usr/bin/env bash
# Run a shell command on the EC2 instance through SSM and print its output.
# Usage: script/aws_run.sh "/opt/game_platform/bin/rails db:seed"
set -euo pipefail
cd "$(dirname "$0")/.."

tf() { terraform -chdir=terraform output -raw "$1"; }
REGION=$(tf aws_region)
INSTANCE_ID=$(tf instance_id)

PARAMS=$(jq -n --arg cmd "$1" '{commands: [$cmd], executionTimeout: ["1800"]}')
COMMAND_ID=$(aws ssm send-command --region "$REGION" --instance-ids "$INSTANCE_ID" \
  --document-name AWS-RunShellScript --parameters "$PARAMS" \
  --query Command.CommandId --output text)

invocation() {
  aws ssm get-command-invocation --region "$REGION" --command-id "$COMMAND_ID" --instance-id "$INSTANCE_ID" \
    --query "$1" --output text 2>/dev/null
}

STATUS=Pending
while [[ "$STATUS" =~ ^(Pending|InProgress|Delayed)$ ]]; do
  sleep 3
  STATUS=$(invocation Status || echo Pending)
done

invocation StandardOutputContent
invocation StandardErrorContent >&2
echo "==> $STATUS"
[ "$STATUS" = "Success" ]
