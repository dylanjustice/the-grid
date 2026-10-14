# The Grid

The Grid is a self-hosted synthetic testing platform. Users declare tests as Kubernetes resources;
the platform schedules, runs, and observes them.

## Language

### Tests and Runs

**Synthetic Test**: A scheduled, repeating end-to-end test declared as a `SyntheticTest` Kubernetes
CR. A Synthetic Test defines the test source, schedule, and runner configuration.
_Avoid_: monitor, check, probe

**Synthetic Test Run**: A single execution of a Synthetic Test, mirrored as a `SyntheticTestRun` CR
after the Argo Workflow completes.
_Avoid_: job, execution, instance

**Test Suite**: The outermost `describe` block in a Playwright spec file. Used as the primary
grouping label on all emitted metrics. Falls back to the spec filename when no describe block
is present.
_Avoid_: suite name, describe group, spec

**Test Step**: A named unit of work inside a test, declared with Playwright's `test.step()`. The
atomic unit of instrumentation — each step produces one histogram observation.
_Avoid_: action, assertion, checkpoint

**Inline Source**: Test code embedded directly in the `SyntheticTest` CR spec, stored as a
`ConfigMap` and mounted into the runner pod at startup.
_Avoid_: embedded test, inline script

### Instrumentation

**Synthetics Reporter**: A Playwright Reporter plugin (`@the-grid/synthetics/reporter`) that
auto-instruments every Test Step and Synthetic Test with Prometheus metrics. Configured once in
`playwright.config.ts`; test files require no changes.
_Avoid_: metrics plugin, metrics middleware, prom wrapper

**Step Histogram**: The `synthetic_step_duration_seconds` Prometheus histogram. One observation per
Test Step completion, labelled by test suite, test name, step name, status, and environment.
_Avoid_: step metrics, step timer

**Test Histogram**: The `synthetic_test_duration_seconds` Prometheus histogram. One observation per
Synthetic Test Run completion, labelled by test suite, test name, status, and environment.
_Avoid_: test metrics, test timer, run duration

**Standard Labels**: The fixed set of Prometheus labels emitted on every metric:
`test_suite`, `test_name`, `step_name` (Step Histogram only), `status`, `environment`.
All Synthetic Tests MUST use these labels; custom label sets require a constitution amendment.
_Avoid_: metric labels, dimensions

### Infrastructure

**Runner**: The container image that executes Playwright tests. Contains browsers and
`node_modules` but no test files — test source is injected via Inline Source or S3 at pod startup.
_Avoid_: test container, playwright container

**Operator**: The kubebuilder-based Kubernetes controller that reconciles `SyntheticTest` CRs into
Argo `CronWorkflow` resources and `SyntheticTestRun` CRs into run records.
_Avoid_: controller, manager

**Pushgateway**: The Prometheus Pushgateway that receives metrics pushed by the Synthetics Reporter
after each test run. Scraped by Prometheus on a static config.
_Avoid_: metrics endpoint, push endpoint

---

## Example dialogue

> **Dev:** I want to add a test for the login flow. Do I need to touch the metrics code?
>
> **Domain expert:** No — just write your Playwright test, wrap everything meaningful in
> `test.step()` calls, and the Synthetics Reporter handles the rest. The Step Histogram
> and Test Histogram are emitted automatically.
>
> **Dev:** Where does `test_suite` come from?
>
> **Domain expert:** It's the outermost describe block in your spec file. If you don't have one,
> it falls back to the filename. That's what groups your tests together in Grafana.
>
> **Dev:** And to deploy it to the cluster?
>
> **Domain expert:** Create a `SyntheticTest` CR with your schedule and Inline Source. The Operator
> reconciles it into an Argo CronWorkflow. Each execution becomes a Synthetic Test Run.
