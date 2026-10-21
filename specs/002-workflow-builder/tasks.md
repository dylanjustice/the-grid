# Tasks: Workflow Builder

**Input**: Design documents from `specs/002-workflow-builder/`

**Prerequisites**: plan.md ✓, spec.md ✓, research.md ✓, data-model.md ✓, contracts/ ✓, quickstart.md ✓

**Source files touched**:
- `synthetics-operator/internal/controller/workflow_builder.go` (new)
- `synthetics-operator/internal/controller/workflow_builder_test.go` (new)
- `synthetics-operator/internal/controller/synthetictest_controller.go` (modified)
- `synthetics-operator/internal/controller/synthetictest_controller_test.go` (rewritten)
- `synthetics-operator/cmd/main.go` (modified)

## Format: `[ID] [P?] [Story?] Description with file path`

- **[P]**: Can run in parallel (different files, no file conflicts)
- **[US#]**: User story this task belongs to

---

## Phase 1: Setup

**Purpose**: Establish a clean baseline before any changes are made.

- [X] T001 Run `make operator-test` from repo root and confirm all existing tests pass — this is the regression baseline for SC-001

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Define the full `WorkflowBuilder` interface and both concrete implementations before the reconciler or tests touch them. All user story phases depend on this phase being complete.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T002 Create `synthetics-operator/internal/controller/workflow_builder.go` — define `WorkflowBuilder` interface with two methods: `BuildCronWorkflow(ctx context.Context, test *gridv1alpha1.SyntheticTest) (*wfv1.CronWorkflow, error)` and `BuildWorkflow(ctx context.Context, test *gridv1alpha1.SyntheticTest) (*wfv1.Workflow, error)`; declare `DefaultWorkflowBuilder` as an empty struct

- [X] T003 Implement `DefaultWorkflowBuilder.BuildCronWorkflow` in `synthetics-operator/internal/controller/workflow_builder.go` — extract the CronWorkflow construction block from `synthetictest_controller.go` lines 140–224 verbatim, preserving all defaulting: image defaults to `"393657359434.dkr.ecr.us-east-2.amazonaws.com/flynn/playwright-runner-js:latest"` when empty, command defaults to `["npx", "playwright", "test"]` when empty, name defaults to `"playwright"` when empty, volume mount `{Name: test.Name+"-source", MountPath: "/app/tests"}` always appended; return error if `test.Spec.Schedule` is empty, `test.Spec.Source.Inline` is empty, or `test.Spec.ServiceAccountName` is nil

- [X] T004 Implement `DefaultWorkflowBuilder.BuildWorkflow` in `synthetics-operator/internal/controller/workflow_builder.go` — extract the shared template and volume construction into a private helper `buildWorkflowSpec(test)`; `BuildWorkflow` calls it and wraps the result in `*wfv1.Workflow` with no `Schedules` field; return error if `test.Spec.Source.Inline` is empty or `test.Spec.ServiceAccountName` is nil; refactor `BuildCronWorkflow` to also use the shared helper

**Checkpoint**: `workflow_builder.go` compiles with both methods implemented. Run `go build ./...` from `synthetics-operator/`.

---

## Phase 3: User Story 1 — Reconciler Delegates CronWorkflow Construction (Priority: P1) 🎯 MVP

**Goal**: The reconciler calls `BuildCronWorkflow` and applies the result; no Argo struct literals remain in the reconciler body.

**Independent Test**: `make operator-test` passes with no behavioral change; `grep -n "CronWorkflow{" synthetics-operator/internal/controller/synthetictest_controller.go` returns no matches.

- [X] T005 [US1] Add `WorkflowBuilder WorkflowBuilder` field to `SyntheticTestReconciler` struct in `synthetics-operator/internal/controller/synthetictest_controller.go`

- [X] T006 [US1] Replace the CronWorkflow construction block (lines 171–224 of `synthetictest_controller.go`) with a call to `r.WorkflowBuilder.BuildCronWorkflow(ctx, syntheticTest)`; assign the returned `*wfv1.CronWorkflow` to `workflow`; return the error immediately if non-nil; update the `CreateOrUpdate` call to use the returned object in `synthetics-operator/internal/controller/synthetictest_controller.go`

- [X] T007 [US1] Add `WorkflowBuilder: &controller.DefaultWorkflowBuilder{}` to the `SyntheticTestReconciler` struct literal in `synthetics-operator/cmd/main.go`

- [X] T008 [US1] Run `make operator-test` — confirm SC-001 (all existing tests pass) and SC-002 (no `wfv1.CronWorkflow{` literal in `synthetictest_controller.go`)

**Checkpoint**: US1 complete. Reconciler delegates construction. Cluster behavior unchanged.

---

## Phase 4: User Story 2 — Fake Builder Adapter + Reconciler Unit Tests (Priority: P2)

**Goal**: The reconciler's create, update, and error paths are covered by isolated unit tests that inject a fake builder.

**Independent Test**: `make operator-test` shows passing tests for "create path", "error path", and "update path" in the `SyntheticTest Controller` suite — none requiring a live Argo API.

- [X] T009 [US2] Define `fakeWorkflowBuilder` struct in `synthetics-operator/internal/controller/synthetictest_controller_test.go` with fields: `buildCronWorkflowCalled bool`, `buildWorkflowCalled bool`, `receivedTest *gridv1alpha1.SyntheticTest`, `cronWorkflowResult *wfv1.CronWorkflow`, `workflowResult *wfv1.Workflow`, `err error`; implement both `WorkflowBuilder` methods: set the `Called` flag, store `receivedTest`, return the pre-configured result or error

- [X] T010 [US2] Write Ginkgo test "create path" in `synthetics-operator/internal/controller/synthetictest_controller_test.go` — wire a `fakeWorkflowBuilder` with a pre-built `CronWorkflow` into the reconciler; reconcile a valid `SyntheticTest`; assert `buildCronWorkflowCalled` is true, `receivedTest` matches the CR, and the CronWorkflow was applied (verify via `k8sClient.Get`)

- [X] T011 [US2] Write Ginkgo test "error path" in `synthetics-operator/internal/controller/synthetictest_controller_test.go` — wire a `fakeWorkflowBuilder` with `err` set to a non-nil error; reconcile; assert the reconciler returns the error and no CronWorkflow exists in the cluster

- [X] T012 [US2] Write Ginkgo test "update path" in `synthetics-operator/internal/controller/synthetictest_controller_test.go` — reconcile the same `SyntheticTest` twice with updated spec between calls; assert `buildCronWorkflowCalled` increments and the applied CronWorkflow reflects the second call's result

**Checkpoint**: US2 complete. SC-003 satisfied: reconciler error/create/update paths covered without live cluster.

---

## Phase 5: User Story 3 — BuildWorkflow Test Coverage (Priority: P3)

**Goal**: `BuildWorkflow` is proven to produce a schedule-free Workflow with identical container and volume configuration to `BuildCronWorkflow`.

**Independent Test**: `make operator-test` shows passing tests in `workflow_builder_test.go` asserting no schedule and matching container/volume fields.

- [X] T013 [US3] Create `synthetics-operator/internal/controller/workflow_builder_test.go` — write test calling `DefaultWorkflowBuilder.BuildCronWorkflow` and `DefaultWorkflowBuilder.BuildWorkflow` on the same `SyntheticTest`; assert both return the same `container.Image`, `container.Command`, `container.Name`, `VolumeMounts`, and `ServiceAccountName`

- [X] T014 [US3] Add test in `synthetics-operator/internal/controller/workflow_builder_test.go` asserting `BuildWorkflow` returns `*wfv1.Workflow` (not CronWorkflow) with no `Spec.Schedules` field set, and `Spec.WorkflowSpec.Entrypoint` matches `BuildCronWorkflow`'s `WorkflowSpec.Entrypoint`

**Checkpoint**: US3 complete. SC-004 satisfied: one-shot Workflow is structurally verified.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T015 Run `make operator-test` from repo root — confirm all four success criteria: SC-001 (no test regression), SC-002 (zero inline Argo struct literals in reconciler), SC-003 (fake builder tests cover three paths), SC-004 (BuildWorkflow test passes); run `grep -n "wfv1.CronWorkflow{" synthetics-operator/internal/controller/synthetictest_controller.go` to verify SC-002

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — run immediately
- **Foundational (Phase 2)**: Depends on Setup — **BLOCKS all user stories**
- **US1 (Phase 3)**: Depends on Foundational — no other story dependency
- **US2 (Phase 4)**: Depends on US1 (reconciler must have the `WorkflowBuilder` field before fake can be injected)
- **US3 (Phase 5)**: Depends on Foundational (T003, T004) — independent of US1 and US2
- **Polish (Phase 6)**: Depends on all story phases

### Parallel Opportunities

- T013 and T014 (both US3 tasks) are in the same file but test independent methods — can be written together
- US3 (Phase 5) can begin in parallel with US2 (Phase 4) once Foundational is complete, since US3 tests the builder directly and does not touch the reconciler or fake

---

## Parallel Example: After Foundational is complete

```
# Developer A: wire reconciler (US1)
Task: T005 → T006 → T007 → T008

# Developer B: builder unit tests (US3) — fully independent
Task: T013 → T014
```

---

## Implementation Strategy

### MVP (US1 only)

1. Complete Phase 1: Setup (T001)
2. Complete Phase 2: Foundational (T002 → T003 → T004)
3. Complete Phase 3: US1 (T005 → T006 → T007 → T008)
4. **STOP and VALIDATE**: `make operator-test` passes, no struct literals in reconciler
5. Cluster behavior is identical — safe to deploy

### Full Delivery

1. MVP above
2. Phase 4: US2 — isolated reconciler unit tests (T009 → T010 → T011 → T012)
3. Phase 5: US3 — BuildWorkflow coverage (T013 → T014) *(can overlap with Phase 4)*
4. Phase 6: Polish (T015)
