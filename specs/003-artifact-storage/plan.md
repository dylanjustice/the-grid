# Implementation Plan: Artifact Storage

**Branch**: `003-artifact-storage` | **Date**: 2026-10-20 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/003-artifact-storage/spec.md`

## Summary

Enable durable artifact storage for every synthetic test run by wiring Argo Workflows' native artifact storage mechanism into the existing operator. The `SyntheticTest` CR already has an `ArtifactStorageSpec` stub and the `SyntheticTestRun` CR already has an `ArtifactURL` status field — both need to be fully implemented. Configuration lives in `ArtifactStorageSpec` (bucket, endpoint, region, credential mode); the operator propagates it into Kubernetes resources and the `WorkflowBuilder` opts the generated CronWorkflow into Argo's artifact repository.

## Technical Context

**Language/Version**: Go 1.22 (operator); TypeScript / Node 23 (runner — no changes required)

**Primary Dependencies**: controller-runtime, Argo Workflows v3 Go client, kubebuilder RBAC markers

**Storage**: S3-compatible object store (AWS S3, GCS S3-interop, MinIO) — platform-operator supplied

**Testing**: `go test` with envtest (controller tests); existing `make test` for runner

**Target Platform**: Kubernetes (k3s / EKS / any), ARM64 or AMD64

**Project Type**: Kubernetes operator + GitOps manifests

**Performance Goals**: Artifact upload completes within 2 minutes of run completion (SC-001)

**Constraints**: Upload failure must not fail the workflow (Constitution V); all config must flow through `values.yaml` / CR fields (Constitution II)

**Scale/Scope**: One artifact package per test run; upload size bounded by normal Playwright output (~10–100 MB)

## Constitution Check

_GATE: Must pass before Phase 0 research. Re-check after Phase 1 design._

| Principle                            | Status | Notes                                                                                                                                                                                                                            |
| ------------------------------------ | ------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| I. GitOps is source of truth         | ✓      | New ConfigMap and CR changes go through `gitops/` and `main`                                                                                                                                                                     |
| II. Helm Chart is product boundary   | ✓      | The `artifact-repositories` ConfigMap and optional credentials Secret are added to `gitops/workloads/playwright-synthetics/`. All config surfaces via fields on the `SyntheticTest` CR, which operators set in `synthetics.yaml` |
| III. Operator owns the lifecycle     | ✓      | `SyntheticTestController` propagates `ArtifactStorageSpec` to the SA annotations and CronWorkflow's `artifactRepositoryRef`; `SyntheticTestRunController` already extracts the URL                                               |
| IV. Zero-boilerplate instrumentation | ✓      | No test-file changes; upload is handled by Argo artifact storage, not by test code                                                                                                                                               |
| V. Observability is non-blocking     | ✓      | Argo's artifact storage is best-effort by design; a failed upload does not propagate to workflow phase                                                                                                                           |

**Gate result: PASS**

## Project Structure

### Documentation (this feature)

```text
specs/003-artifact-storage/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   ├── artifact-storage-spec.go
│   ├── artifact-repository-configmap.yaml
│   └── synthetictestrun-artifact-url.md
└── tasks.md             # Phase 2 output (/speckit-tasks — not created by /speckit-plan)
```

### Source Code (repository root)

```text
synthetics-operator/
├── api/v1alpha1/
│   └── synthetictest_types.go          # Expand ArtifactStorageSpec with bucket/endpoint/region/credentials fields
├── internal/controller/
│   ├── workflow_builder.go             # Set artifactRepositoryRef on WorkflowSpec when enabled
│   └── synthetictest_controller.go     # Propagate serviceAccountAnnotations onto created SA

gitops/workloads/playwright-synthetics/
├── synthetics.yaml                     # Update ArtifactStorageSpec fields on the SyntheticTest CR
├── service-account.yaml                # Unchanged (operator-owned SA takes over for artifact uploads)
├── artifact-repository.yaml            # New: artifact-repositories ConfigMap
└── artifact-credentials.yaml          # New: optional Secret for static credentials (templated, not committed with real values)
```

**Structure Decision**: Single operator + GitOps raw-manifest structure. The playwright-synthetics workload is raw YAML (not a Helm chart) deployed by ArgoCD from `gitops/workloads/playwright-synthetics/`. New manifests follow the same pattern.

## Complexity Tracking

No constitution violations to justify.
