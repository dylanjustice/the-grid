# Quickstart Validation Guide: Artifact Storage

**Purpose**: End-to-end validation that artifact storage is working after implementation.

## Prerequisites

- A running cluster with the operator deployed (`make tunnel-start && make get-kubeconfig`)
- An accessible S3-compatible store. For local validation use MinIO in-cluster (see setup below).
- `kubectl` configured against the cluster
- AWS CLI or MinIO `mc` client (for inspecting the bucket)

## Option A: MinIO in-cluster (fastest local validation)

### 1. Deploy MinIO

```bash
kubectl create namespace minio
kubectl apply -n minio -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minio
spec:
  selector:
    matchLabels:
      app: minio
  template:
    metadata:
      labels:
        app: minio
    spec:
      containers:
      - name: minio
        image: minio/minio:latest
        args: ["server", "/data"]
        env:
        - name: MINIO_ROOT_USER
          value: minioadmin
        - name: MINIO_ROOT_PASSWORD
          value: minioadmin
        ports:
        - containerPort: 9000
---
apiVersion: v1
kind: Service
metadata:
  name: minio
spec:
  selector:
    app: minio
  ports:
  - port: 9000
    targetPort: 9000
EOF

# Create the bucket
kubectl run mc --image=minio/mc --rm -it --restart=Never -n minio -- \
  sh -c "mc alias set local http://minio.minio.svc:9000 minioadmin minioadmin && mc mb local/the-grid-artifacts"
```

### 2. Create the credentials Secret

```bash
kubectl create secret generic artifact-credentials \
  -n the-grid-synthetics \
  --from-literal=accessKey=minioadmin \
  --from-literal=secretKey=minioadmin
```

### 3. Update the SyntheticTest CR

Edit `gitops/workloads/playwright-synthetics/synthetics.yaml` — add the `artifactStorage` block:

```yaml
spec:
  artifactStorage:
    enabled: true
    bucket: the-grid-artifacts
    endpoint: "http://minio.minio.svc:9000"
    credentialsSecret: artifact-credentials
```

Push to `main` and wait for ArgoCD sync (~3 minutes), or `make argo-sync`.

### 4. Trigger a test run

```bash
kubectl create -n the-grid-synthetics -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: httbin-synthetic-manual-
  labels:
    the-grid.io/synthetic-test: httbin-synthetic
spec:
  workflowTemplateRef:
    name: httbin-synthetic
EOF
```

### 5. Verify the artifact was uploaded

Watch the workflow complete:
```bash
kubectl get workflows -n the-grid-synthetics -w
```

Once the workflow shows `Succeeded` or `Failed`, check MinIO:
```bash
kubectl run mc-check --image=minio/mc --rm -it --restart=Never -n minio -- \
  sh -c "mc alias set local http://minio.minio.svc:9000 minioadmin minioadmin && mc ls --recursive local/the-grid-artifacts"
```

Expected output (the path follows `<test-name>/<workflow-name>/playwright-report`):
```
httbin-synthetic/httbin-synthetic-manual-xxxxx/playwright-report
```

### 6. Verify the SyntheticTestRun has the artifact URL

```bash
kubectl get synthetictestruns -n the-grid-synthetics -o jsonpath='{.items[*].status.artifactURL}'
```

Expected: `s3://the-grid-artifacts/httbin-synthetic/httbin-synthetic-manual-xxxxx/playwright-report`

---

## Option B: AWS S3 with IRSA (cloud validation)

### Prerequisites

- EKS cluster with OIDC provider configured
- IAM role with `s3:PutObject` and `s3:GetObject` on the target bucket, trusted by the EKS OIDC provider
- Existing S3 bucket

### 1. Update the SyntheticTest CR

```yaml
spec:
  serviceAccountName: httpbin-synthetic-sa
  artifactStorage:
    enabled: true
    bucket: your-artifact-bucket
    region: us-east-2
    serviceAccountAnnotations:
      eks.amazonaws.com/role-arn: "arn:aws:iam::123456789012:role/the-grid-artifact-uploader"
```

### 2–6. Follow steps 4–6 from Option A, adapting the bucket inspection command to:

```bash
aws s3 ls s3://your-artifact-bucket/httbin-synthetic/ --recursive
```

---

## Validation Checklist

- [ ] Workflow completes with the same pass/fail result regardless of upload outcome (upload failure test: disconnect MinIO after run starts)
- [ ] `SyntheticTestRun.status.artifactURL` is non-empty after a successful upload
- [ ] `SyntheticTestRun.status.artifactURL` is empty (not an error state) when artifact storage is disabled
- [ ] The artifact path matches the pattern `<test-name>/<workflow-name>/playwright-report` within the bucket
- [ ] The `playwright-report` object in the store is a gzipped tar archive containing `index.html`, screenshots, and trace files
- [ ] Deleting the `SyntheticTest` CR removes the `<name>-artifact-repository` ConfigMap (owner reference GC)
- [ ] No test file changes were required to enable artifact storage
