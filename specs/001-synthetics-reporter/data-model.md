# Data Model: The Synthetics Reporter

## Entities

### SyntheticsReporter

The Playwright `Reporter` implementation. One instance per Playwright worker process.

| Field           | Type                        | Description                                             |
| --------------- | --------------------------- | ------------------------------------------------------- |
| `registry`      | `Registry`                  | Per-instance prom-client Registry (isolated per worker) |
| `gateway`       | `Pushgateway`               | prom-client Pushgateway client; pushes after each test  |
| `stepHistogram` | `Histogram`                 | `synthetic_step_duration_seconds`                       |
| `testHistogram` | `Histogram`                 | `synthetic_test_duration_seconds`                       |
| `options`       | `SyntheticsReporterOptions` | Resolved config (pushgatewayUrl, jobName)               |

**Lifecycle**: Constructed once by Playwright when the worker starts. `onStepEnd` fires per step;
`onTestEnd` fires per test and triggers a push.

---

### SyntheticsReporterOptions

Configuration passed from `playwright.config.ts`.

| Field            | Type     | Required | Default                       |
| ---------------- | -------- | -------- | ----------------------------- |
| `pushgatewayUrl` | `string` | No       | `process.env.PUSHGATEWAY_URL` |
| `jobName`        | `string` | No       | `"synthetic-tests"`           |

If neither option nor env var is present, a warning is logged and metrics are silently dropped.

---

### StepObservation

Transient value — computed in `onStepEnd`, observed to `stepHistogram` immediately.

| Field             | Type         | Source                                  |
| ----------------- | ------------ | --------------------------------------- |
| `durationSeconds` | `number`     | `step.duration / 1000`                  |
| `testSuite`       | `string`     | `LabelResolver.resolveTestSuite(test)`  |
| `testName`        | `string`     | `test.title`                            |
| `stepName`        | `string`     | `step.title`                            |
| `status`          | `StepStatus` | `LabelResolver.resolveStepStatus(step)` |
| `environment`     | `string`     | `process.env.GRID_ENV ?? 'unknown'`     |

**Filter**: Only created when `step.parent === undefined` AND `step.category === 'test.step'`.

---

### TestObservation

Transient value — computed in `onTestEnd`, observed to `testHistogram` and pushed.

| Field             | Type         | Source                                    |
| ----------------- | ------------ | ----------------------------------------- |
| `durationSeconds` | `number`     | `result.duration / 1000`                  |
| `testSuite`       | `string`     | `LabelResolver.resolveTestSuite(test)`    |
| `testName`        | `string`     | `test.title`                              |
| `status`          | `TestStatus` | `LabelResolver.resolveTestStatus(result)` |
| `environment`     | `string`     | `process.env.GRID_ENV ?? 'unknown'`       |

---

### LabelResolver

Pure logic module — no I/O, fully unit-testable.

**`resolveTestSuite(test: TestCase): string`**
Walk `test.parent` chain upward. Return the `title` of the first `Suite` with
`type === 'describe'`. If no describe suite is found before reaching `type === 'file'`, return
`path.basename(fileSuite.title)`.

```
test.parent                  → Suite (type='describe', title='HTTP Methods') → return 'HTTP Methods'
test.parent → test.parent... → Suite (type='file', title='/app/tests/http-bin.spec.ts') → return 'http-bin.spec.ts'
```

**`resolveTestStatus(result: TestResult): TestStatus`**

| `result.status` | returns     |
| --------------- | ----------- |
| `'passed'`      | `'success'` |
| `'failed'`      | `'failure'` |
| `'timedOut'`    | `'timeout'` |
| `'skipped'`     | `'skip'`    |
| `'interrupted'` | `'failure'` |

**`resolveStepStatus(step: TestStep): StepStatus`**

| condition                                 | returns                   |
| ----------------------------------------- | ------------------------- |
| `step.error === undefined`                | `'success'`               |
| `step.error.message` matches `/timeout/i` | `'timeout'` (best-effort) |
| otherwise                                 | `'failure'`               |

---

## Status Enums

```typescript
type TestStatus = "success" | "failure" | "timeout" | "skip";
type StepStatus = "success" | "failure" | "timeout";
```

---

## Metric Definitions

### `synthetic_step_duration_seconds`

| Property | Value                                                                          |
| -------- | ------------------------------------------------------------------------------ |
| Type     | Histogram                                                                      |
| Unit     | seconds                                                                        |
| Labels   | `test_suite`, `test_name`, `step_name`, `status`, `environment`                |
| Buckets  | `0.1, 0.25, 0.5, 1, 2.5, 5, 10, 30`                                            |
| Fires on | `onStepEnd` where `step.parent === undefined && step.category === 'test.step'` |

### `synthetic_test_duration_seconds`

| Property | Value                                              |
| -------- | -------------------------------------------------- |
| Type     | Histogram                                          |
| Unit     | seconds                                            |
| Labels   | `test_suite`, `test_name`, `status`, `environment` |
| Buckets  | `1, 5, 10, 30, 60, 120, 300`                       |
| Fires on | `onTestEnd`                                        |

---

## State Transitions

```
Reporter constructed
  ↓
[per step] onStepEnd fires
  filter: parent===undefined && category==='test.step'
  → StepObservation → stepHistogram.observe()
  ↓
[per test] onTestEnd fires
  → TestObservation → testHistogram.observe()
  → gateway.pushAdd({ jobName })
     success → continue
     failure → log to stderr, continue (test is NOT failed)
```
