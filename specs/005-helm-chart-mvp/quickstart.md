# Quickstart Validation Guide: MVP Helm Chart

Runnable scenarios that prove the feature works end-to-end. Run these in order against a clean cluster (kind or k3s recommended).

## Prerequisites

- `kubectl` connected to a test cluster
- `helm` 3.14+
- Access to the registry where the operator and runner images were pushed
- The chart packaged or available from the OCI registry

---

## Scenario 1 — Full install, operator reaches Running

**Goal**: Validates FR-001, FR-002, FR-003, SC-001, SC-002.

```bash
# Install with both Argo and Pushgateway enabled (defaults)
helm install the-grid oci://<registry>/charts/the-grid-synthetics \
  --set operator.image=<registry>/the-grid/operator:<version> \
  --set runner.image=<registry>/the-grid/runner:<version> \
  --namespace the-grid-system \
  --create-namespace \
  --wait --timeout=5m
```

**Expected outcomes**:
- `kubectl get pods -n the-grid-system` shows operator pod in `Running` state
- `kubectl get crd synthetictests.thegrid.io` exits 0
- `kubectl get crd synthetictestruns.thegrid.io` exits 0
- `kubectl get ns the-grid-synthetics` exists (created by the chart)
- `kubectl get pods -n the-grid-synthetics` shows Pushgateway running

---

## Scenario 2 — SyntheticTest CR reconciles without PUSHGATEWAY_URL in the CR

**Goal**: Validates FR-004, FR-005, FR-006, SC-004.

```bash
kubectl apply -f - <<EOF
apiVersion: thegrid.io/v1alpha1
kind: SyntheticTest
metadata:
  name: validation-test
  namespace: the-grid-synthetics
spec:
  schedule: "*/5 * * * *"
  entrypoint: run
  source:
    inline: |
      import { test } from "@playwright/test";
      test("smoke", async () => {});
EOF
```

**Expected outcomes**:
- `kubectl get cronworkflow -n the-grid-synthetics validation-test` appears within 10 seconds
- `kubectl get cronworkflow validation-test -n the-grid-synthetics -o jsonpath='{.spec.workflowSpec.templates[0].container.env}'` contains `PUSHGATEWAY_URL` set to the chart-deployed Pushgateway service URL
- `kubectl get cronworkflow validation-test -n the-grid-synthetics -o jsonpath='{.spec.workflowSpec.templates[0].container.image}'` equals the `runner.image` set during install
- `kubectl get configmap validation-test-config -n the-grid-synthetics` exists with `test.spec.ts` key

---

## Scenario 3 — CR-level image override respected

**Goal**: Validates FR-004 (CR overrides chart default), User Story 3.

```bash
kubectl apply -f - <<EOF
apiVersion: thegrid.io/v1alpha1
kind: SyntheticTest
metadata:
  name: custom-image-test
  namespace: the-grid-synthetics
spec:
  schedule: "*/5 * * * *"
  entrypoint: run
  container:
    image: custom-registry.example.com/runner:pinned
  source:
    inline: |
      import { test } from "@playwright/test";
      test("smoke", async () => {});
EOF
```

**Expected outcome**:
- `kubectl get cronworkflow custom-image-test -n the-grid-synthetics -o jsonpath='{.spec.workflowSpec.templates[0].container.image}'` equals `custom-registry.example.com/runner:pinned`, not the chart default

---

## Scenario 4 — CR deletion cleans up owned resources

**Goal**: Validates User Story 2 acceptance scenario 3, FR-003 (operator lifecycle ownership).

```bash
kubectl delete synthetictest validation-test -n the-grid-synthetics
```

**Expected outcomes** (within 30 seconds):
- `kubectl get cronworkflow validation-test -n the-grid-synthetics` returns `NotFound`
- `kubectl get configmap validation-test-config -n the-grid-synthetics` returns `NotFound`

---

## Scenario 5 — Bring-your-own Argo + external Pushgateway

**Goal**: Validates FR-006, FR-011, SC-005.

```bash
helm install the-grid oci://<registry>/charts/the-grid-synthetics \
  --set operator.image=<registry>/the-grid/operator:<version> \
  --set runner.image=<registry>/the-grid/runner:<version> \
  --set argo-workflows.enabled=false \
  --set pushgateway.enabled=false \
  --set pushgateway.externalUrl=http://my-pushgateway.monitoring.svc:9091 \
  --namespace the-grid-system \
  --create-namespace \
  --wait --timeout=3m
```

**Expected outcomes**:
- Operator pod reaches `Running`
- No Argo Workflows pods deployed by this release (`kubectl get pods -A | grep argo` should show only pre-existing Argo pods)
- No Pushgateway pod deployed by this release
- `kubectl get cronworkflow` for a new `SyntheticTest` CR shows `PUSHGATEWAY_URL=http://my-pushgateway.monitoring.svc:9091` in the container env

---

## Scenario 6 — Release pipeline (CI validation)

**Goal**: Validates FR-009, FR-010, SC-003, User Story 4.

```bash
# From the maintainer's local machine — push a release tag
git tag v0.2.0
git push origin v0.2.0
```

**Expected outcomes** (within 10 minutes, check in CI):
- GitHub Actions `release.yml` workflow completes successfully
- `docker pull <registry>/the-grid/operator:v0.2.0` succeeds
- `helm pull oci://<registry>/charts/the-grid-synthetics --version 0.2.0` succeeds
- Chart `appVersion` in the pulled chart matches the git tag

---

## Validation checklist

| Scenario | FR/SC covered | Pass criteria |
|---|---|---|
| 1 — Full install | FR-001, FR-002, FR-003, SC-001, SC-002 | Operator Running; CRDs registered; workload namespace created |
| 2 — SyntheticTest reconciles | FR-004, FR-005, FR-006, SC-004 | CronWorkflow has correct image and PUSHGATEWAY_URL; no manual env var in CR |
| 3 — CR image override | FR-004 | Custom image in CronWorkflow, not chart default |
| 4 — CR deletion cleanup | FR-003, US-2 | CronWorkflow + ConfigMap removed |
| 5 — BYO Argo + Pushgateway | FR-006, FR-011, SC-005 | Operator starts; external URL injected; no extra pods |
| 6 — Release pipeline | FR-009, FR-010, SC-003 | Tag → image + chart in registry within 10 min |
