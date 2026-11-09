#!/bin/bash
# Runs ON the EC2 instance via SSM. Configures Tailscale Serve so platform UIs
# are reachable over HTTPS on the Tailnet without port-forwarding.
# Requires split DNS configured for cluster.local (see modules/k3s/userdata.sh).
set -euo pipefail

echo "=== Tailscale Serve Setup ==="

configure_serve() {
  local label=$1 port=$2 target=$3
  tailscale serve --https="$port" --bg --yes "$target"
  echo "Configured $label on https port $port -> $target"
}

# ArgoCD serves HTTPS internally (self-signed)
configure_serve "ArgoCD"         443  "https+insecure://argocd-server.argocd.svc.cluster.local:443"
configure_serve "Argo Workflows" 2746 "http://argo-workflows-server.the-grid-workflows.svc.cluster.local:2746"
configure_serve "Prometheus"     9090 "http://prometheus-server.the-grid-monitoring.svc.cluster.local:80"
configure_serve "Grafana"        3000 "http://grafana.the-grid-monitoring.svc.cluster.local:3000"
configure_serve "httpbin"        8080 "http://httpbin.the-grid-synthetics.svc.cluster.local:80"

echo ""
echo "=== Tailscale Serve Status ==="
tailscale serve status
