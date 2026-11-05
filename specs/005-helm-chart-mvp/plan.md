# Implementation Plan: MVP Helm Chart

**Branch**: `005-helm-chart-mvp` | **Date**: 2026-11-04 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/005-helm-chart-mvp/spec.md`

## Summary

Package the existing operator, CRDs, and supporting resources into a distributable Helm chart (`charts/the-grid-synthetics/`) so that any Kubernetes user can install The Grid with a single `helm install` command. The chart bundles Argo Workflows and the Prometheus Pushgateway as toggleable dependencies, deploys the operator with configurable runner image and auto-injected Pushgateway URL, and publishes via a GitHub Actions CI pipeline triggered by semver git tags.

Two code changes sit outside the chart itself: the operator binary gains `--runner-image` and `--pushgateway-url` startup flags so the chart can wire values through to it at runtime.

## Technical Context

**Language/Version**: Go 1.21 (operator), Helm 3.14+ (chart), YAML (templates), GitHub Actions (CI)

**Primary Dependencies**:
- controller-runtime / kubebuilder (operator)
- Argo Workflows v1alpha1 API (operator dependency)
- `helm/chart-releaser-action` or `helm registry push` (OCI chart publish)
- `docker/build-push-action` (operator image CI)

**Storage**: Kubernetes etcd via API server only — no additional storage

**Testing**: `go test ./...` + envtest for operator; `helm lint` + `helm template` for chart; end-to-end validation against kind/k3s cluster

**Target Platform**: Any CNCF-conformant Kubernetes cluster (amd64 + ARM64 — dev cluster is ARM64 t4g.medium)

**Project Type**: Kubernetes operator + Helm chart + CI pipeline

**Performance Goals**: `helm install` → operator `Running` in < 5 minutes (SC-002); release tag → published chart in < 10 minutes (SC-003)

**Constraints**: Helm 3.x; no cert-manager or webhook server required for MVP; operator must not require cluster-admin beyond the ClusterRole defined in `config/rbac/role.yaml`

**Scale/Scope**: Single cluster install; MVP targets early adopters running < 100 `SyntheticTest` CRs

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|---|---|---|
| I. GitOps is SSOT | ✓ PASS | Chart templates committed to `main`; ArgoCD still manages dev cluster via `gitops/`. Chart is the product; `gitops/` is the dev proving ground. |
| II. Helm Chart is Product Boundary | ✓ PASS | This feature IS the chart. All capabilities (`operator.image`, `runner.image`, `workloadNamespace`, dependency toggles) are configurable via `values.yaml`. |
| III. Operator Owns Test Lifecycle | ✓ PASS | `SyntheticTest` and `SyntheticTestRun` CRDs ship with the chart; the operator manages full lifecycle. No direct CronWorkflow authorship by users. |
| IV. Zero-Boilerplate Instrumentation | ✓ PASS | Operator auto-injects `PUSHGATEWAY_URL` into every CronWorkflow — users need no env var in their `SyntheticTest` CR. |
| V. Observability is Non-Blocking | ✓ PASS | Pushgateway URL wiring is best-effort at runtime; push failures are already logged and non-aborting in `SyntheticsReporter`. |
| Technology Constraints | ✓ PASS | Go operator, TypeScript runner, Argo Workflows, Pushgateway, GitHub Actions all consistent. Dev images → ECR; published release images → configurable registry. |

**No violations. Proceeding.**

## Project Structure

### Documentation (this feature)

```text
specs/005-helm-chart-mvp/
├── plan.md              ← this file
├── research.md          ← Phase 0 output
├── data-model.md        ← Phase 1 output
├── quickstart.md        ← Phase 1 output
├── contracts/
│   └── values-schema.md ← Phase 1 output
└── tasks.md             ← /speckit-tasks output (not created here)
```

### Source Code (repository root)

```text
charts/the-grid-synthetics/
├── Chart.yaml                        # already exists — no changes needed
├── values.yaml                       # add operator: and workloadNamespace: sections
├── crds/
│   ├── thegrid.io_synthetictests.yaml     # copied from config/crd/bases/
│   └── thegrid.io_synthetictestruns.yaml  # copied from config/crd/bases/
└── templates/
    ├── _helpers.tpl
    ├── namespace.yaml                # workload namespace
    ├── serviceaccount.yaml           # operator ServiceAccount
    ├── clusterrole.yaml              # operator ClusterRole
    ├── clusterrolebinding.yaml       # operator ClusterRoleBinding
    ├── leader-election-role.yaml     # namespaced Role for leader election
    ├── leader-election-rolebinding.yaml
    └── deployment.yaml               # operator Deployment

synthetics-operator/
├── cmd/
│   └── main.go                       # add --runner-image and --pushgateway-url flags
└── internal/controller/
    └── workflow_builder.go           # DefaultWorkflowBuilder gains RunnerImage + PushgatewayURL fields

.github/workflows/
├── ci.yml                            # runs on push/PR to main: test + lint
└── release.yml                       # runs on tag push (v*): build + push image + publish chart
```

**Structure Decision**: Single chart package under `charts/the-grid-synthetics/` with `crds/` for CRD installation (Helm native, no auto-upgrade) and `templates/` for all other resources. Operator code changes are minimal and confined to `cmd/main.go` and `workflow_builder.go`.

## Complexity Tracking

No constitution violations requiring justification.
