#!/usr/bin/env bash
# Configures Tailscale Serve on the EC2 instance via SSM Run Command.
# Run this once after k3s-bootstrap when all services are ready.
set -euo pipefail

INSTANCE_ID=$(terraform -chdir=live/flynn output -raw k3s_instance_id)
REGION=${AWS_REGION:-us-east-2}

echo "Configuring Tailscale Serve on instance $INSTANCE_ID..."

# Encode the remote script as a single-line base64 string (no newlines)
ENCODED=$(base64 -i scripts/tailscale-serve-remote.sh | tr -d '\n')

COMMAND_ID=$(aws ssm send-command \
  --region "$REGION" \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters "commands=[\"echo '$ENCODED' | base64 -d | bash\"]" \
  --query "Command.CommandId" \
  --output text)

echo "SSM command dispatched: $COMMAND_ID"

# Poll until the command completes
while true; do
  STATUS=$(aws ssm get-command-invocation \
    --region "$REGION" \
    --command-id "$COMMAND_ID" \
    --instance-id "$INSTANCE_ID" \
    --query "Status" \
    --output text 2>/dev/null || echo "Pending")

  case "$STATUS" in
    Success)
      echo ""
      aws ssm get-command-invocation \
        --region "$REGION" \
        --command-id "$COMMAND_ID" \
        --instance-id "$INSTANCE_ID" \
        --query "StandardOutputContent" \
        --output text
      echo "Tailscale Serve configured successfully."
      break
      ;;
    Failed|Cancelled|TimedOut)
      echo "ERROR: SSM command $STATUS"
      aws ssm get-command-invocation \
        --region "$REGION" \
        --command-id "$COMMAND_ID" \
        --instance-id "$INSTANCE_ID" \
        --query "StandardErrorContent" \
        --output text >&2
      exit 1
      ;;
    *)
      printf "."
      sleep 5
      ;;
  esac
done
