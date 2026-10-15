# Feature Specification: The Synthetics Reporter

**Feature Branch**: `001-synthetics-reporter`

**Created**: 2026-10-13

**Status**: Draft

**Input**: A Playwright Reporter plugin (`@the-grid/synthetics/reporter`) that automatically
instruments every Test Step and Synthetic Test with Prometheus metrics — no boilerplate in
test files. Configured once in `playwright.config.ts`.

## User Scenarios & Testing _(mandatory)_

### User Story 1 - Zero-boilerplate step metrics (Priority: P1)

A developer writing a Playwright synthetic test wants step-level Prometheus metrics without
importing prom-client, creating a registry, or managing timers manually.

**Why this priority**: This is the core value proposition of the reporter. Without it, every test
file repeats 6 lines of boilerplate and risks label drift. It is the seam that makes the rest of
the platform scale.

**Independent Test**: Configure the reporter in a clean `playwright.config.ts`, write a test with
`test.step()` calls, run it with `PUSHGATEWAY_URL` set, and verify `synthetic_step_duration_seconds`
appears in the Pushgateway with correct labels.

**Acceptance Scenarios**:

1. **Given** a `playwright.config.ts` that includes the reporter with `pushgatewayUrl` set,
   **When** a test with two `test.step()` calls runs and passes,
   **Then** `synthetic_step_duration_seconds{status="success"}` has two observations in Pushgateway,
   one per step, each with `test_suite`, `test_name`, `step_name`, and `environment` labels set.

2. **Given** the same setup,
   **When** a test step throws an assertion error,
   **Then** `synthetic_step_duration_seconds{status="failure"}` has one observation for the
   failed step, with duration still recorded.

3. **Given** a test that exceeds its timeout,
   **When** a step is interrupted by the timeout,
   **Then** the step emits `status="timeout"` (best-effort via error message inspection).

4. **Given** no `PUSHGATEWAY_URL` env var and no `pushgatewayUrl` option,
   **When** a test run completes,
   **Then** a warning is logged to stderr and no push is attempted (tests still pass).

---

### User Story 2 - End-to-end test duration histogram (Priority: P1)

An operator wants to track overall pass rate and latency per Synthetic Test in Prometheus —
the SLO-level view.

**Why this priority**: Step-level and test-level metrics together enable drill-down: first see
which test is failing, then see which step inside it is slow or flaky.

**Independent Test**: Run a test suite with one passing and one failing test; verify both
`synthetic_test_duration_seconds{status="success"}` and `{status="failure"}` observations appear.

**Acceptance Scenarios**:

1. **Given** a test suite with three tests (one passes, one fails, one is skipped),
   **When** the suite completes,
   **Then** Pushgateway contains three observations on `synthetic_test_duration_seconds`,
   with `status="success"`, `status="failure"`, and `status="skip"` respectively.

2. **Given** a test that exceeds its Playwright timeout,
   **When** the suite completes,
   **Then** the test emits `status="timeout"` on `synthetic_test_duration_seconds`.

3. **Given** a test in a file with no `describe` block,
   **When** metrics are emitted,
   **Then** `test_suite` is set to the spec filename (without path prefix).

---

### User Story 3 - Remove operator metric injection (Priority: P2)

The Argo Workflows metric injection in the operator (`syntheticTestMetrics()`) emits a metric
named `synthetic_test_duration_seconds` that conflicts with the reporter's metric. The operator
metric must be removed so there is one authoritative source.

**Why this priority**: Without removing the operator metric, Prometheus will receive two
observations for every test run under the same metric name — one measuring pod runtime (Argo),
one measuring Playwright execution time (reporter). This makes the histogram meaningless.

**Independent Test**: After removing `syntheticTestMetrics()` from `synthetictest_controller.go`,
apply a `SyntheticTest` CR and verify no `synthetic_test_duration_seconds` metric appears in
Argo Workflows' own metrics endpoint.

**Acceptance Scenarios**:

1. **Given** the operator has `syntheticTestMetrics()` removed,
   **When** a CronWorkflow runs,
   **Then** `synthetic_test_duration_seconds` is absent from Argo's `/metrics` endpoint.

2. **Given** the operator change is deployed,
   **When** a full test run completes end-to-end,
   **Then** `synthetic_test_duration_seconds` in Prometheus has exactly one source (the reporter).

---

### Edge Cases

- What if `test.step()` is nested? Only top-level steps are instrumented (Playwright fires
  `onStepEnd` for every level; we filter to `step.parent === null` equivalent depth 0).
- What if `GRID_ENV` is not set? `environment` label defaults to `"unknown"`.
- What if Pushgateway is unreachable? Log the error; do not abort the test run.
- What if a test has no `test.step()` calls? The test histogram still fires; no step observations.
- What if multiple spec files run in parallel? Each reporter instance pushes independently;
  `pushAdd` (not `push`) is used so observations accumulate rather than overwrite.

## Requirements _(mandatory)_

### Functional Requirements

- **FR-001**: Reporter MUST emit `synthetic_step_duration_seconds` histogram on every `onStepEnd`
  event with labels `test_suite`, `test_name`, `step_name`, `status`, `environment`.
- **FR-002**: Reporter MUST emit `synthetic_test_duration_seconds` histogram on every `onTestEnd`
  event with labels `test_suite`, `test_name`, `status`, `environment`.
- **FR-003**: `status` MUST be one of `success`, `failure`, `timeout`, `skip`.
- **FR-004**: `test_suite` MUST be derived from the outermost `describe` block title; fallback to
  spec filename (basename without path) when no describe wrapper is present.
- **FR-005**: Reporter MUST accept `pushgatewayUrl` and `jobName` as constructor options in
  `playwright.config.ts`; these MUST fall back to `PUSHGATEWAY_URL` and the string
  `"synthetic-tests"` respectively when not supplied.
- **FR-006**: `environment` label MUST be sourced from `GRID_ENV` env var; defaults to `"unknown"`.
- **FR-007**: Pushgateway push failure MUST be logged to stderr and MUST NOT abort the test run
  or cause tests to fail.
- **FR-008**: Reporter MUST use `pushAdd` (not `push`) so parallel workers accumulate rather than
  overwrite each other's observations.
- **FR-009**: `syntheticTestMetrics()` in `synthetics-operator/internal/controller/synthetictest_controller.go`
  MUST be removed along with its call site.
- **FR-010**: Step instrumentation MUST only record top-level steps (depth 0); nested steps inside
  a `test.step()` MUST be excluded to avoid double-counting.
- **FR-011**: Reporter MUST be publishable as `@the-grid/synthetics` with a `/reporter` sub-path
  export.

### Key Entities

- **SyntheticsReporter**: The Playwright `Reporter` implementation. Owns both histograms and the
  Pushgateway client. One instance per Playwright worker process.
- **StepObservation**: A single data point emitted on `onStepEnd` — step title, duration, status,
  and resolved labels.
- **TestObservation**: A single data point emitted on `onTestEnd` — test title, duration, status,
  and resolved labels.
- **LabelResolver**: Logic that derives `test_suite` from a `TestCase`'s suite hierarchy and
  `status` from `TestResult`/`TestStep` state.

## Success Criteria _(mandatory)_

### Measurable Outcomes

- **SC-001**: A new test file with zero prom-client imports emits correct metrics after adding the
  reporter to `playwright.config.ts`.
- **SC-002**: `synthetic_step_duration_seconds` and `synthetic_test_duration_seconds` appear in
  Pushgateway with all five standard labels populated on every test run.
- **SC-003**: `status="timeout"` is distinguishable from `status="failure"` in Grafana queries.
- **SC-004**: Removing `syntheticTestMetrics()` from the operator causes zero test failures in the
  operator's existing e2e suite.
- **SC-005**: Pushgateway unavailability produces a logged warning but zero test failures.

## Assumptions

- Node 23 + TypeScript; `@playwright/test ^1.58` reporter API is stable for this feature.
- `prom-client ^15` Pushgateway API (`pushAdd`) is the correct accumulation primitive.
- The reporter runs in the same process as Playwright workers; no cross-process metric state needed.
- The operator e2e test suite (`synthetics-operator/test/e2e/`) will remain green after removing
  `syntheticTestMetrics()` since no e2e test currently asserts on that metric's presence.
- Step depth can be inferred from `TestStep.parent !== undefined` (nested steps have a parent step;
  top-level steps have a parent that is a `TestCase`).
