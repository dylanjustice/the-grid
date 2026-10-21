# Research: Workflow Builder

**Feature**: 002-workflow-builder
**Date**: 2026-10-14

No external research required — all decisions are resolvable from the existing codebase and Go / controller-runtime conventions. Findings documented here for future reference.

---

## Decision 1: Package placement for `WorkflowBuilder`

**Decision**: Place `workflow_builder.go` in `internal/controller` alongside `synthetictest_controller.go`.

**Rationale**: The builder is consumed exclusively by `SyntheticTestReconciler`. Placing it in the same package avoids an import cycle and keeps the scope clear. A separate `internal/workflow` package is the right move if a second consumer appears (e.g., a webhook or event-driven controller), but that's a future extraction, not today's task.

**Alternatives considered**:
- `internal/workflow/` — cleaner separation, but premature for one consumer and one package today.
- `internal/builder/` — same concern; adds a hop for no current benefit.

---

## Decision 2: `FakeWorkflowBuilder` placement

**Decision**: Define `FakeWorkflowBuilder` in `synthetictest_controller_test.go` (unexported, `_test.go` only).

**Rationale**: The fake is only needed by reconciler tests. Keeping it in `_test.go` makes the dependency direction explicit — production code cannot accidentally import test infrastructure. If integration tests in `test/e2e/` ever need a fake, extract it to an `internal/testhelpers` package at that point.

**Alternatives considered**:
- Exported `FakeWorkflowBuilder` in `workflow_builder.go` — pollutes the production package with test-only types.
- Separate `internal/testhelpers/` package — correct approach at scale; over-engineering for current scope.

---

## Decision 3: Interface method signatures

**Decision**:
```go
type WorkflowBuilder interface {
    BuildCronWorkflow(ctx context.Context, test *gridv1alpha1.SyntheticTest) (*wfv1.CronWorkflow, error)
    BuildWorkflow(ctx context.Context, test *gridv1alpha1.SyntheticTest) (*wfv1.Workflow, error)
}
```

**Rationale**: `context.Context` is Go convention for any function that might need cancellation or deadline propagation — even if the current implementation doesn't use it, omitting it is a breaking change to add later. Returning `error` alongside the result keeps error handling at the call site, which is where the reconciler's requeue logic lives.

**Alternatives considered**:
- No `context.Context` — saves one parameter today but breaks the interface when logging or tracing is added to the builder.
- Builder returning only `error` with a separate `Get*()` method — mimics the step-based pattern; rejected in favor of the simpler single-call form.

---

## Decision 4: Constructor injection vs field assignment

**Decision**: Add `WorkflowBuilder` as a field on `SyntheticTestReconciler`; wire `DefaultWorkflowBuilder` in `cmd/main.go` at startup.

**Rationale**: `cmd/main.go` already constructs the reconciler with a struct literal — adding the builder field there follows the same pattern. Avoids factory functions or `New*` constructors that would require touching the kubebuilder scaffold's wiring conventions.

**Alternatives considered**:
- `NewSyntheticTestReconciler(...)` constructor — cleaner API but requires changing `main.go` and any other wiring code.
- Default to `DefaultWorkflowBuilder` inside `Reconcile` if field is nil — hidden fallback that makes injection invisible in tests.

---

## Decision 5: Statelessness of `DefaultWorkflowBuilder`

**Decision**: `DefaultWorkflowBuilder` has no fields; it is a zero-value struct. Both methods are pure functions of their inputs.

**Rationale**: The current inline construction logic in the reconciler has no shared mutable state between calls. Carrying that property into the builder means concurrent reconcile loops can share the same builder instance safely, and tests need not reset any state between runs.

**Alternatives considered**:
- Store default image/command as builder fields configurable at startup — adds flexibility but the defaults are already constants in the reconciler; move that decision to a later milestone if configurability is needed.
