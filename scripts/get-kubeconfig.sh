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


CLUSTER_CA=$(kubectl --kubeconfig kubeconfig.yaml config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
CLIENT_CERT=$(kubectl --kubeconfig kubeconfig.yaml config view --raw -o jsonpath='{.users[0].user.client-certificate-data}')
CLIENT_KEY=$(kubectl --kubeconfig kubeconfig.yaml config view --raw -o jsonpath='{.users[0].user.client-key-data}')

# Prefer Tailscale hostname so kubectl works without an SSM tunnel.
# Falls back to localhost:6443 (requires make tunnel-start) if Tailscale is not active.
echo "Detecting Tailscale hostname..."
TS_CMD_ID=$(aws ssm send-command \
  --region "$REGION" \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["tailscale status --json 2>/dev/null | python3 -c \"import json,sys; d=json.load(sys.stdin); print(d['\''Self'\'']['\''DNSName'\''].rstrip('\''.'\''))\" 2>/dev/null || echo \"\""]' \
  --query "Command.CommandId" \
  --output text 2>/dev/null || echo "")

TS_HOSTNAME=""
if [ -n "$TS_CMD_ID" ]; then
  sleep 5
  TS_HOSTNAME=$(aws ssm get-command-invocation \
    --region "$REGION" \
    --command-id "$TS_CMD_ID" \
    --instance-id "$INSTANCE_ID" \
    --query "StandardOutputContent" \
    --output text 2>/dev/null | tr -d '[:space:]' || echo "")
fi

if [ -n "$TS_HOSTNAME" ] && [[ "$TS_HOSTNAME" == *.ts.net ]]; then
  CLUSTER_SERVER="https://${TS_HOSTNAME}:6443"
  echo "Using Tailscale hostname: $TS_HOSTNAME"
else
  CLUSTER_SERVER="https://localhost:6443"
  echo "Tailscale not detected — using localhost:6443 (requires make tunnel-start)"
fi

GRID_DIR="$HOME/.kube/the-grid"
mkdir -p "$GRID_DIR"
chmod 700 "$GRID_DIR"

echo "$CLUSTER_CA" | base64 --decode > "$GRID_DIR/ca.crt"
echo "$CLIENT_CERT" | base64 --decode > "$GRID_DIR/client.crt"
echo "$CLIENT_KEY" | base64 --decode > "$GRID_DIR/client.key"

chmod 600 "$GRID_DIR"/*

kubectl config delete-context the-grid 2>/dev/null || true
kubectl config delete-cluster the-grid 2>/dev/null || true
kubectl config delete-user the-grid-admin 2>/dev/null || true

kubectl config set-cluster the-grid \
  --server="$CLUSTER_SERVER" \
  --certificate-authority="$GRID_DIR/ca.crt"

kubectl config set-credentials the-grid-admin \
  --client-certificate="$GRID_DIR/client.crt" \
  --client-key="$GRID_DIR/client.key"

kubectl config set-context the-grid \
  --cluster=the-grid \
  --user=the-grid-admin

kubectl config use-context the-grid