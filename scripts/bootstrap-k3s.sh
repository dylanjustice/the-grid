#!/usr/bin/env bash

helm repo add argo https://argoproj.github.io/argo-helm
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install argocd argo/argo-cd --namespace argocd --create-namespace
helm install prometheus prometheus-community/prometheus --namespace the-grid-monitoring --create-namespace
kubectl apply -f gitops/applications/argo-workflows.yaml
kubectl apply -f gitops/applications/playwright-synthetics.yaml
