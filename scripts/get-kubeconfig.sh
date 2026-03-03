#!/usr/bin/env bash
set -euo pipefail

INSTANCE_ID=$(terraform -chdir=live/flynn output -raw k3s_instance_id)
REGION=$(aws configure get region)

echo "Fetching kubeconfig from $INSTANCE_ID..."

COMMAND_ID=$(aws ssm send-command \
  --region "$REGION" \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters commands="sudo cat /etc/rancher/k3s/k3s.yaml" \
  --query "Command.CommandId" \
  --output text)

# Wait for command to finish
while true; do
  STATUS=$(aws ssm get-command-invocation \
    --region "$REGION" \
    --command-id "$COMMAND_ID" \
    --instance-id "$INSTANCE_ID" \
    --query "Status" \
    --output text)

  if [[ "$STATUS" == "Success" ]]; then
    break
  elif [[ "$STATUS" == "Failed" ]]; then
    echo "Command failed"
    exit 1
  else
    sleep 2
  fi
done

# Fetch clean stdout
aws ssm get-command-invocation \
  --region "$REGION" \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --query "StandardOutputContent" \
  --output text > kubeconfig.yaml

# Rewrite server to localhost for port-forwarding
sed -i '' 's/127.0.0.1/localhost/' kubeconfig.yaml 2>/dev/null || \
sed -i 's/127.0.0.1/localhost/' kubeconfig.yaml

echo "kubeconfig.yaml written cleanly."