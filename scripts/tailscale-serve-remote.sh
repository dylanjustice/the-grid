#!/bin/bash
# Runs ON the EC2 instance via SSM. Discovers k3s ClusterIPs and
# configures Tailscale Serve so platform UIs are reachable over HTTPS
# on the Tailnet without port-forwarding.
set -euo pipefail

echo "=== Tailscale Serve Setup ==="
echo "Discovering k3s service ClusterIPs..."

get_cluster_ip() {
  local svc=$1 ns=$2
  k3s kubectl get svc "$svc" -n "$ns" \
    -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo ""
}

ARGOCD_IP=$(get_cluster_ip argocd-server argocd)
ARGO_IP=$(get_cluster_ip argo-workflows-server the-grid-workflows)
PROM_IP=$(get_cluster_ip prometheus-server the-grid-monitoring)
HTTPBIN_IP=$(get_cluster_ip httpbin the-grid-synthetics)

echo "  argocd-server:          ${ARGOCD_IP:-NOT FOUND}"
echo "  argo-workflows-server:  ${ARGO_IP:-NOT FOUND}"
echo "  prometheus-server:      ${PROM_IP:-NOT FOUND}"
echo "  httpbin:                ${HTTPBIN_IP:-NOT FOUND}"

configure_serve() {
  local label=$1 port=$2 target=$3
  if [ -n "$target" ]; then
    tailscale serve "https:${port}" "$target"
    echo "Configured $label on https port $port -> $target"
  else
    echo "WARNING: $label ClusterIP not found, skipping"
  fi
}

# ArgoCD serves HTTPS internally (self-signed); use https+insecure
[ -n "$ARGOCD_IP" ] && configure_serve "ArgoCD" 443 "https+insecure://${ARGOCD_IP}:443" || true
[ -n "$ARGO_IP" ]   && configure_serve "Argo Workflows" 2746 "http://${ARGO_IP}:2746" || true
[ -n "$PROM_IP" ]   && configure_serve "Prometheus" 9090 "http://${PROM_IP}:80" || true
[ -n "$HTTPBIN_IP" ] && configure_serve "httpbin" 8080 "http://${HTTPBIN_IP}:80" || true

echo ""
echo "=== Tailscale Serve Status ==="
tailscale serve status
