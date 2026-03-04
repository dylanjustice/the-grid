echo $(pwd)
kubectl apply -f gitops/applications/argo-workflows.yaml
kubectl apply -f gitops/applications/playwright-synthetics.yaml
