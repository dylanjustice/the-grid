# Research: The Synthetics Reporter

## Playwright Reporter API

**Decision**: Implement the `Reporter` interface from `@playwright/test/reporter`. Use `onStepEnd`
for step metrics and `onTestEnd` for test metrics. All methods are optional.

**Key signatures** (from `node_modules/@playwright/test/types/testReporter.d.ts`):

```typescript
interface Reporter {
  onTestEnd?(test: TestCase, result: TestResult): void;
  onStepEnd?(test: TestCase, result: TestResult, step: TestStep): void;
}

interface TestResult {
  status: "passed" | "failed" | "timedOut" | "skipped" | "interrupted";
  duration: number; // milliseconds
  error?: TestError;
}

interface TestStep {
  title: string;
  duration: number; // milliseconds
  error?: TestError;
  category: string; // 'test.step' | 'expect' | 'fixture' | 'pw:api' | 'hook'
  parent?: TestStep; // undefined = top-level; TestStep = nested
  steps: TestStep[]; // children
}

interface TestCase {
  title: string;
  titlePath(): string[]; // [projectName, filename, ...describes, testTitle]
  parent: Suite;
}

interface Suite {
  title: string;
  type: "root" | "project" | "file" | "describe";
  parent?: Suite;
}
```

**Rationale**: Using `onStepEnd` gives us step title, duration, and error in one event — no need
to correlate begin/end ourselves. `onTestEnd` gives `TestResult.duration` as the total Playwright
execution time (not pod runtime).

---

## Step Depth and Category Filtering

**Decision**: Filter in `onStepEnd` to steps where `step.parent === undefined` AND
`step.category === 'test.step'`.

**Rationale**: Two filters are both required:

1. `step.parent === undefined` — top-level only; nested steps inside `test.step()` also fire
   `onStepEnd` with a `TestStep` parent. Without this filter, a step with two nested sub-steps
   would emit three observations (parent + 2 children).
2. `step.category === 'test.step'` — Playwright fires `onStepEnd` for _every_ step type:
   `expect` assertions, fixture setup/teardown, `pw:api` (page actions like `goto`, `click`),
   and `hook` (beforeEach/afterEach). We only want explicit developer-defined steps.

**Alternatives considered**:

- Filter only by depth: would include top-level `expect()` calls as separate step observations
- Filter only by category: would include nested `test.step()` as double-counts
- No filter: would flood metrics with every `page.goto()` and `expect()` call

---

## Status Derivation

**Decision**: Map Playwright statuses to the four constitutional values.

| Playwright status | Metric status         |
| ----------------- | --------------------- |
| `'passed'`        | `'success'`           |
| `'failed'`        | `'failure'`           |
| `'timedOut'`      | `'timeout'`           |
| `'skipped'`       | `'skip'`              |
| `'interrupted'`   | `'failure'` (fold in) |

For step-level status:

- `step.error === undefined` → `'success'`
- `step.error.message` matches `/timeout/i` → `'timeout'` (best-effort)
- Otherwise → `'failure'`

**Rationale**: `TestResult.status === 'timedOut'` is explicit and clean. Step-level timeout
detection via error message is fragile but acceptable as best-effort per spec. `'interrupted'`
folds into `'failure'` — it represents a killed worker, not a meaningful test outcome.

---

## Pushgateway Accumulation

**Decision**: Use `gateway.pushAdd({ jobName })` (POST semantics), one call per `onTestEnd`.

**Rationale**: `push()` uses HTTP PUT and _replaces_ all metrics for the job — a second parallel
worker would wipe the first worker's observations. `pushAdd()` uses HTTP POST and _accumulates_
observations. With multiple Playwright workers each running their own reporter instance and
their own `Registry`, `pushAdd()` correctly merges all workers' histograms at the gateway.

**Alternatives considered**:

- Push in `onEnd` (batch): simpler, but `onEnd` fires after all tests complete. Per-test push
  means partial data is visible in Prometheus during long runs. Per-test chosen.
- Global `register`: works but cross-contaminates metrics between reporter instances if the
  test runner ever reuses the module. Per-instance `Registry` preferred.

---

## Package Sub-path Exports

**Decision**: `"type": "module"` with conditional `exports` in `package.json`. Dual
CJS/ESM output is not required for the runner image (Node 23 ESM-native). Output ESM only.

```json
{
  "name": "@the-grid/synthetics",
  "type": "module",
  "exports": {
    ".": { "types": "./dist/index.d.ts", "default": "./dist/index.js" },
    "./reporter": {
      "types": "./dist/reporter/index.d.ts",
      "default": "./dist/reporter/index.js"
    }
  }
}
```

**Rationale**: Node 23 is ESM-native; no CJS shim needed for our use case. Playwright's own
reporter loading supports ESM. Simpler build: `tsc` only, no bundler step required.

**Alternatives considered**:

- Dual CJS/ESM: necessary if publishing to npm for broad consumption; overkill for a
  single-repo library consumed only by the runner image and test suite.
- Single export (no sub-path): forces callers to import from `@the-grid/synthetics` and
  re-export; sub-path is cleaner and matches `@playwright/test/reporter` convention.

---

## Summary of Resolved Decisions

| Question                | Resolution                                                                                               |
| ----------------------- | -------------------------------------------------------------------------------------------------------- |
| Which Reporter hooks?   | `onStepEnd` + `onTestEnd`                                                                                |
| Step filtering          | `parent === undefined` AND `category === 'test.step'`                                                    |
| Step timeout detection  | Best-effort: `step.error.message` matches `/timeout/i`                                                   |
| `test_suite` derivation | Walk `test.parent` chain; first `type === 'describe'` suite title; fallback: file suite title (basename) |
| Push method             | `pushAdd()` per `onTestEnd`                                                                              |
| Registry                | Per-instance `new Registry()`                                                                            |
| Duration units          | Playwright reports ms; divide by 1000 for Prometheus `_seconds` convention                               |
| Module format           | ESM only (`"type": "module"`)                                                                            |
| CJS support             | Not required (runner image is Node 23)                                                                   |
