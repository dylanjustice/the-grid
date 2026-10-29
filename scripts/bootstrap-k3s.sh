#!/usr/bin/env bash
set -euo pipefail

helm repo add argo https://argoproj.github.io/argo-helm
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade argocd argo/argo-cd --install --namespace argocd --create-namespace
helm upgrade prometheus prometheus-community/prometheus --install --namespace the-grid-monitoring --create-namespace --values gitops/workloads/kube-prometheus/values.yaml
kubectl apply -f gitops/applications/argo-workflows.yaml
kubectl apply -f gitops/applications/playwright-synthetics.yaml
kubectl apply -f gitops/applications/httpbin.yaml

# Wait for ArgoCD and core workloads to become ready before configuring Tailscale Serve
echo "Waiting for ArgoCD pods to be ready..."
kubectl wait --for=condition=ready pod --all -n argocd --timeout=300s

echo "Waiting for Argo Workflows pods to be ready..."
kubectl wait --for=condition=ready pod --all -n the-grid-workflows --timeout=300s || true

echo "Waiting for monitoring pods to be ready..."
kubectl wait --for=condition=ready pod --all -n the-grid-monitoring --timeout=300s || true

echo "Waiting for synthetics pods to be ready..."
kubectl wait --for=condition=ready pod --all -n the-grid-synthetics --timeout=300s || true

# Configure Tailscale Serve if Tailscale is running on the instance
if terraform -chdir=live/flynn output -raw k3s_instance_id &>/dev/null 2>&1; then
  if [ "${TAILSCALE_ENABLED:-false}" = "true" ]; then
    echo "Configuring Tailscale Serve..."
    make tailscale-serve-setup
  else
    echo "TAILSCALE_ENABLED is not set to true; skipping Tailscale Serve setup."
    echo "Run 'make tailscale-serve-setup' manually after enabling Tailscale."
  fi
fi
