# Implementation Plan: Workflow Builder

**Branch**: `002-workflow-builder` | **Date**: 2026-10-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/002-workflow-builder/spec.md`

## Summary

Extract all Argo `CronWorkflow` construction logic from `SyntheticTestReconciler` into a `WorkflowBuilder` interface with a concrete implementation and a fake for testing. The reconciler receives the builder via constructor injection. Two interface methods — `BuildCronWorkflow` and `BuildWorkflow` — handle scheduled and on-demand runs respectively, allowing the reconciler and future controllers to remain ignorant of Argo's field layout.

## Technical Context

**Language/Version**: Go 1.23 (kubebuilder scaffold)

**Primary Dependencies**: `controller-runtime` v0.21, `argo-workflows/v3` (wfv1 types), `k8s.io/api` (corev1, rbacv1)

**Storage**: N/A — the builder produces in-memory Argo objects; persistence is handled by the existing reconciler via `controller-runtime` client

**Testing**: Ginkgo v2 + Gomega (existing scaffold); `FakeWorkflowBuilder` injected for reconciler-level unit tests

**Target Platform**: Kubernetes operator binary (Linux, ARM64 / AMD64)

**Project Type**: Internal refactor of an existing controller package — no new CRDs, no new external API surface

**Performance Goals**: N/A — object construction is synchronous, in-memory, and not on any hot path

**Constraints**: Must not change the shape of the `CronWorkflow` the reconciler currently applies to the cluster; existing e2e behavior is unchanged

**Scale/Scope**: Two source files added (`workflow_builder.go`, `workflow_builder_test.go`), one file modified (`synthetictest_controller.go`), one file modified (`cmd/main.go`), one test file substantially rewritten

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. GitOps is the Single Source of Truth | ✓ PASS | Internal code refactor; no cluster state changes, no manual `kubectl apply` |
| II. Helm Chart is the Product Boundary | ✓ PASS | No new product features; operator internals only |
| III. Operator Owns the Test Lifecycle | ✓ PASS | Directly supports this principle — improves the operator's internal structure |
| IV. Zero-Boilerplate Test Instrumentation | ✓ PASS | Not applicable — Go operator, not test runner code |
| V. Observability is Non-Blocking | ✓ PASS | Not applicable to this change |

No violations. No Complexity Tracking required.

## Project Structure

### Documentation (this feature)

```text
specs/002-workflow-builder/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── workflow-builder.go
└── tasks.md             # Phase 2 output (/speckit-tasks — not created here)
```

### Source Code (repository root)

```text
synthetics-operator/
├── cmd/
│   └── main.go                                         # modified: wire DefaultWorkflowBuilder into reconciler
└── internal/
    └── controller/
        ├── synthetictest_controller.go                 # modified: inject WorkflowBuilder, remove inline construction
        ├── workflow_builder.go                         # new: WorkflowBuilder interface + DefaultWorkflowBuilder
        └── synthetictest_controller_test.go            # rewritten: inject FakeWorkflowBuilder, test error/create/update paths
```

**Structure Decision**: Builder lives in `internal/controller` (same package as the reconciler). A separate `internal/workflow` package would be cleaner at larger scale but adds indirection with no current benefit — the builder is tightly scoped to what the controller needs.
