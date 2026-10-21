# Feature Specification: Workflow Builder

**Feature Branch**: `002-workflow-builder`

**Created**: 2026-10-14

**Status**: Draft

**Input**: User description: "The operator reconciler constructs every field of a cronworkflow. Use a builder pattern and interface to construct the workflow from the synthetictest. Ensure we can test with an adapter. And we're positioned to create on-demand/event driven workflows through the builder."

## User Scenarios & Testing _(mandatory)_

### User Story 1 - Reconciler Delegates CronWorkflow Construction to a Builder (Priority: P1)

A platform engineer maintaining the operator wants all Argo CronWorkflow construction logic moved out of the reconciler into a `WorkflowBuilder` interface. The reconciler holds a builder, calls `BuildCronWorkflow(test)`, receives a complete `CronWorkflow`, and applies it. All knowledge of how to inflate a `SyntheticTest` into an Argo object lives inside the builder, not the reconciler.

**Why this priority**: This is the core refactor. Every other story depends on the reconciler delegating construction through the interface.

**Independent Test**: Can be validated by running the reconciler tests with a `FakeWorkflowBuilder` injected — the CronWorkflow the reconciler previously constructed inline should be produced identically with no change to observed cluster behavior.

**Acceptance Scenarios**:

1. **Given** a `SyntheticTest` CR with a schedule, container spec, and inline source, **When** the reconciler runs, **Then** it calls `BuildCronWorkflow(test)` on the injected builder and applies the returned workflow — no Argo struct literals remain in the reconciler body.
2. **Given** a `SyntheticTest` CR update, **When** the reconciler re-runs, **Then** `BuildCronWorkflow` is called again with the updated spec and the result is used to patch the existing CronWorkflow.
3. **Given** a builder that returns an error from `BuildCronWorkflow`, **When** the reconciler calls it, **Then** the reconciler returns the error and requeues without applying anything to the cluster.

---

### User Story 2 - Fake Builder Adapter Enables Isolated Reconciler Tests (Priority: P2)

A developer writing operator unit tests wants to inject a `FakeWorkflowBuilder` that records which method was called and with what `SyntheticTest`, and returns a pre-configured `CronWorkflow` or error — so the reconciler's behavior can be tested completely independently of the construction logic.

**Why this priority**: The interface is the seam. Without an injectable fake, reconciler tests couple to the full Argo object graph and become integration tests.

**Independent Test**: Can be validated by a test suite that injects a `FakeWorkflowBuilder`, reconciles a `SyntheticTest`, and asserts the builder received the correct input and that the reconciler applied exactly the workflow the builder returned — no Argo API calls needed.

**Acceptance Scenarios**:

1. **Given** a reconciler wired with a `FakeWorkflowBuilder`, **When** a `SyntheticTest` is reconciled, **Then** the fake records the `SyntheticTest` passed to `BuildCronWorkflow` and the test can assert it matches the CR.
2. **Given** a fake configured to return an error, **When** the reconciler runs, **Then** the test can assert the error path: no workflow is applied and the reconciler requeues.
3. **Given** a fake configured to return a specific `CronWorkflow`, **When** the reconciler runs, **Then** that exact object is what gets applied — confirming the reconciler does not modify the builder's output.

---

### User Story 3 - Builder Supports On-Demand Workflow Construction (Priority: P3)

A platform engineer wants the same `WorkflowBuilder` interface to produce a one-shot `Workflow` (no schedule) via `BuildWorkflow(test)`, so future event-driven and manual-trigger scenarios can reuse the same small-to-large inflation logic without a separate implementation.

**Why this priority**: The interface already defines the contract. Adding `BuildWorkflow` positions the platform for manual triggers and webhook-driven runs without any new Argo field knowledge being introduced elsewhere.

**Independent Test**: Can be validated by calling `BuildWorkflow` on the concrete builder and asserting the returned `Workflow` has no schedule fields set and the same container and volume configuration as `BuildCronWorkflow` would produce.

**Acceptance Scenarios**:

1. **Given** a `SyntheticTest`, **When** `BuildWorkflow(test)` is called, **Then** the returned Argo `Workflow` has no schedule, and the same container spec and volumes as the equivalent CronWorkflow.
2. **Given** the same concrete builder, **When** `BuildCronWorkflow` and `BuildWorkflow` are called with the same `SyntheticTest`, **Then** both products share identical container and volume configuration — only the schedule and outer wrapper type differ.
3. **Given** a one-shot `Workflow` produced by the builder, **When** applied to the cluster, **Then** Argo executes it immediately as a single run with no recurrence.

---

### Edge Cases

- What happens when `SyntheticTest.Spec.Container` is partially specified (e.g., missing image) — does the builder apply defaults or return an error?
- How does the builder handle an empty `Spec.Source.Inline` — is this a construction error or does it produce an empty ConfigMap volume?
- If `BuildWorkflow` and `BuildCronWorkflow` are called concurrently on the same builder instance, is the builder stateless enough to handle this safely?

## Requirements _(mandatory)_

### Functional Requirements

- **FR-001**: The system MUST define a `WorkflowBuilder` interface with at minimum two methods: one that accepts a `SyntheticTest` and returns a fully-formed `CronWorkflow` (or error), and one that returns a one-shot `Workflow` (or error).
- **FR-002**: The reconciler MUST receive a `WorkflowBuilder` via constructor injection and call it in place of all inline Argo struct construction.
- **FR-003**: The package MUST include a concrete `WorkflowBuilder` implementation that encapsulates all existing Argo construction logic currently embedded in the reconciler, including all defaulting behavior (image, command, container name, volume mount).
- **FR-004**: The package MUST include a `FakeWorkflowBuilder` that records method invocations and their arguments, and returns configurable outputs, suitable for injection in unit tests.
- **FR-005**: A builder error MUST cause the reconciler to return the error and requeue; the reconciler MUST NOT apply a partial or zero-value workflow.
- **FR-006**: The `BuildWorkflow` method MUST produce an Argo `Workflow` with the same container spec, volumes, and service account as `BuildCronWorkflow`, but with no schedule.
- **FR-007**: The concrete builder MUST be stateless between calls — successive calls with different `SyntheticTest` inputs MUST NOT bleed state.

### Key Entities

- **WorkflowBuilder**: The interface. Two methods: `BuildCronWorkflow(test) → CronWorkflow` and `BuildWorkflow(test) → Workflow`. Absorbs all knowledge of how to inflate a `SyntheticTest` into Argo types.
- **ConcreteWorkflowBuilder**: The production implementation. Contains all construction and defaulting logic extracted from the reconciler.
- **FakeWorkflowBuilder**: The test implementation. Records calls for assertion; returns pre-configured results or errors.

## Success Criteria _(mandatory)_

### Measurable Outcomes

- **SC-001**: All existing operator unit and integration tests pass after the refactor with no behavioral change to the CronWorkflows produced.
- **SC-002**: The reconciler body contains zero inline Argo workflow struct literals after the change.
- **SC-003**: A new unit test suite covers the reconciler's create path, update path, and error path by injecting a `FakeWorkflowBuilder` — no live cluster or Argo API required.
- **SC-004**: A test on the concrete builder asserts that `BuildWorkflow` and `BuildCronWorkflow` produce identical container and volume configuration from the same `SyntheticTest` input.

## Assumptions

- The existing construction logic is correct and is being moved into the concrete builder, not rewritten.
- ConfigMap, ServiceAccount, Role, and RoleBinding creation remain in the reconciler; the builder owns only `CronWorkflow` and `Workflow` construction.
- The `FakeWorkflowBuilder` does not need to produce valid Argo objects — only to satisfy the interface and record calls.
- `BuildWorkflow` (FR-006) does not need to be wired into a reconciler for this feature to be complete; it is a positioning story.
- Go module and package layout follows the existing kubebuilder scaffold conventions in `synthetics-operator/internal/`.
