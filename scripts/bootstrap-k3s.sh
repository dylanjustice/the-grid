#!/usr/bin/env bash

helm repo add argo https://argoproj.github.io/argo-helm
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade argocd argo/argo-cd --install --namespace argocd --create-namespace
helm upgrade prometheus prometheus-community/prometheus --install --namespace the-grid-monitoring --create-namespace --values gitops/workloads/kube-prometheus/values.yaml
kubectl apply -f gitops/applications/argo-workflows.yaml
kubectl apply -f gitops/applications/playwright-synthetics.yaml
