# Quickstart: Workflow Builder

**Feature**: 002-workflow-builder

This is a pure internal refactor. There is no new user-facing behavior to observe — validation
confirms the reconciler produces the same cluster state as before while using the builder interface.

## Prerequisites

- Go toolchain installed (same version as the operator, check `synthetics-operator/go.mod`)
- `make` available at repo root

## Scenario 1: Existing tests still pass after refactor

**Goal**: Confirm the refactor introduces no regression.

```bash
make operator-test
```

**Expected outcome**: All tests in `synthetics-operator/internal/controller/...` pass. The suite
includes the envtest-based integration tests that spin up a real API server and reconcile a
`SyntheticTest` CR.

---

## Scenario 2: Reconciler error path is covered by a fake builder test

**Goal**: Confirm a new unit test exercises the reconciler's error handling by injecting a fake.

```bash
make operator-test
```

**Expected outcome**: A test named `"when the builder returns an error"` (or similar) appears in
the output and passes. The test must not require a live cluster or Argo CRDs — it uses only the
fake builder and the in-memory `k8sClient` from envtest.

---

## Scenario 3: Builder constructs identical CronWorkflow

**Goal**: Confirm `DefaultWorkflowBuilder.BuildCronWorkflow` produces a `CronWorkflow` structurally
identical to what the old inline code produced.

```bash
make operator-test
```

**Expected outcome**: A test comparing the builder's output to a golden `CronWorkflow` fixture
(or asserting specific fields: schedule, container image, volume mount path, service account name)
passes.

---

## Scenario 4: `BuildWorkflow` produces a schedule-free Workflow

**Goal**: Confirm the one-shot builder method omits the schedule.

```bash
make operator-test
```

**Expected outcome**: A test calling `BuildWorkflow` on a `DefaultWorkflowBuilder` asserts:
- The returned type is `*wfv1.Workflow` (not `CronWorkflow`)
- `Spec.WorkflowSpec` contains the expected container and volumes
- No `Schedules` field is set

---

## Verify wiring in `main.go`

After implementation, confirm `cmd/main.go` passes `&controller.DefaultWorkflowBuilder{}` when
constructing `SyntheticTestReconciler`:

```bash
grep -A5 "SyntheticTestReconciler{" synthetics-operator/cmd/main.go
```

**Expected output**: Shows `WorkflowBuilder: &controller.DefaultWorkflowBuilder{}` in the struct literal.
