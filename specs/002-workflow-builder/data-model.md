# Data Model: Workflow Builder

**Feature**: 002-workflow-builder
**Date**: 2026-10-14

This feature introduces no new CRDs or persisted state. The entities below are in-memory Go types.

---

## WorkflowBuilder (interface)

The central seam. Both the production builder and the fake implement this interface.

| Method | Input | Output | Notes |
|--------|-------|--------|-------|
| `BuildCronWorkflow` | `ctx context.Context`, `test *SyntheticTest` | `*wfv1.CronWorkflow, error` | Inflates the full scheduled workflow |
| `BuildWorkflow` | `ctx context.Context`, `test *SyntheticTest` | `*wfv1.Workflow, error` | Same body/volumes, no schedule |

**Validation rules**:
- If `test.Spec.Schedule` is empty, `BuildCronWorkflow` returns an error.
- If `test.Spec.Source.Inline` is empty, both methods return an error (no volume to mount).
- `test.Spec.ServiceAccountName` must be non-nil; both methods return an error if nil.

---

## DefaultWorkflowBuilder (concrete struct)

Implements `WorkflowBuilder`. No fields — stateless.

**Defaulting behavior** (carried over from the current reconciler):

| Field | Default applied when |
|-------|----------------------|
| `container.Image` | Empty string → `"393657359434.dkr.ecr.us-east-2.amazonaws.com/flynn/playwright-runner-js:latest"` |
| `container.Command` | Empty slice → `["npx", "playwright", "test"]` |
| `container.Name` | Empty string → `"playwright"` |
| `container.VolumeMounts` | Always appended: `{Name: test.Name + "-source", MountPath: "/app/tests"}` |

Both methods share a private helper that builds the common `wfv1.Template` and volumes from a `SyntheticTest`. `BuildCronWorkflow` wraps this in a `CronWorkflowSpec` with the schedule; `BuildWorkflow` wraps it in a `WorkflowSpec` directly.

---

## FakeWorkflowBuilder (test struct)

Implements `WorkflowBuilder`. Used only in `_test.go` files.

| Field | Type | Purpose |
|-------|------|---------|
| `BuildCronWorkflowCalled` | `bool` | Assert the method was invoked |
| `BuildWorkflowCalled` | `bool` | Assert the method was invoked |
| `ReceivedTest` | `*SyntheticTest` | Assert the correct input was passed |
| `CronWorkflowResult` | `*wfv1.CronWorkflow` | Pre-configure the return value |
| `WorkflowResult` | `*wfv1.Workflow` | Pre-configure the return value |
| `Err` | `error` | Pre-configure an error return for both methods |

**Behavior**: Both methods set their `Called` flag and `ReceivedTest`, then return the pre-configured result or error.

---

## SyntheticTestReconciler (modified)

Adds one field to the existing struct:

| Field | Type | Wired from |
|-------|------|-----------|
| `WorkflowBuilder` | `WorkflowBuilder` (interface) | `cmd/main.go` at startup |

The `Reconcile` method calls `r.WorkflowBuilder.BuildCronWorkflow(ctx, syntheticTest)` and applies the result. No other fields change.

---

## Relationships

```
SyntheticTestReconciler
  └── holds WorkflowBuilder (interface)
        ├── DefaultWorkflowBuilder  [production]
        │     └── builds CronWorkflow / Workflow from SyntheticTest
        └── FakeWorkflowBuilder     [tests only]
              └── records calls, returns pre-configured result
```
