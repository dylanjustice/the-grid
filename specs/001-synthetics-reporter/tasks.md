# Tasks: The Synthetics Reporter

**Branch**: `001-synthetics-reporter`

**Input**: Design documents from `/specs/001-synthetics-reporter/`

**Spec**: spec.md — 3 user stories (US1 P1, US2 P1, US3 P2)

**Format**: `[ID] [P?] [Story?] Description — file path`

- **[P]**: Parallelizable (different files, no incomplete dependencies)
- **[Story]**: User story label (US1, US2, US3)

---

## Phase 1: Setup

**Purpose**: npm workspace root + new `packages/synthetics/` package scaffolding.

- [x] T001 Create root `package.json` with npm workspaces pointing to `packages/*` and `playwright-synthetics` — `/Users/dylanjustice/projects/the-grid/package.json`
- [x] T002 Create `packages/synthetics/package.json` — name `@the-grid/synthetics`, `"type": "module"`, exports for `.` and `./reporter` sub-path, dependencies `@playwright/test ^1.58` and `prom-client ^15` — `packages/synthetics/package.json`
- [x] T003 [P] Create `packages/synthetics/tsconfig.json` — `target: ES2022`, `module: NodeNext`, `moduleResolution: NodeNext`, `outDir: ./dist`, `rootDir: ./src`, `declaration: true`, `strict: true` — `packages/synthetics/tsconfig.json`
- [x] T004 [P] Create `packages/synthetics/.gitignore` with `node_modules/` and `dist/` — `packages/synthetics/.gitignore`
- [x] T005 Add `@the-grid/synthetics: "*"` dependency to `playwright-synthetics/package.json` so the workspace links the local package — `playwright-synthetics/package.json`
- [x] T006 Run `npm install` from repo root to link workspace packages — repo root

**Checkpoint**: `packages/synthetics/` directory exists, workspace linked, `node_modules/@the-grid/synthetics` resolves to local package in `playwright-synthetics/`.

---

## Phase 2: Foundational — LabelResolver and Status Types

**Purpose**: Pure logic modules with no I/O. Both US1 and US2 depend on these. Fully unit-testable before any Playwright integration.

- [x] T007 Create `src/reporter/status.ts` — export `TestStatus`, `StepStatus` union types; export `deriveTestStatus(result: TestResult): TestStatus` mapping `passed→success`, `failed→failure`, `timedOut→timeout`, `skipped→skip`, `interrupted→failure`; export `deriveStepStatus(step: TestStep): StepStatus` with `/timeout/i` message check (best-effort) — `packages/synthetics/src/reporter/status.ts`
- [x] T008 Create `src/reporter/label-resolver.ts` — export `resolveTestSuite(test: TestCase): string` walking `test.parent` chain for first `type==='describe'` suite title; fallback to `path.basename(fileSuite.title)`; export re-exports of deriveTestStatus and deriveStepStatus — `packages/synthetics/src/reporter/label-resolver.ts`
- [x] T009 [P] Unit test `resolveTestSuite` — test with describe block (returns block title), test with no describe (returns spec basename), test with nested describes (returns outermost) — `packages/synthetics/tests/unit/label-resolver.test.ts`
- [x] T010 [P] Unit test `deriveTestStatus` — all 5 Playwright input statuses → 4 metric outputs; unit test `deriveStepStatus` — undefined error → success, timeout message → timeout, other error → failure — `packages/synthetics/tests/unit/status.test.ts`

**Checkpoint**: `npm test` in `packages/synthetics/` passes all unit tests with zero I/O.

---

## Phase 3: US1 — Zero-Boilerplate Step Metrics (Priority P1) 🎯 MVP

**Goal**: `onStepEnd` auto-instruments every top-level `test.step()` call. No prom-client imports in test files.

**Independent Test**: quickstart.md Scenario 1 — run `http-bin.spec.ts` with `PUSHGATEWAY_URL` set; `synthetic_step_duration_seconds` appears in Pushgateway with all 5 standard labels. Quickstart Scenario 6 — `grep prom-client playwright-synthetics/tests/` returns no matches.

- [x] T011 [US1] Create `src/reporter/index.ts` — `SyntheticsReporterOptions` interface (`pushgatewayUrl?: string`, `jobName?: string`); `SyntheticsReporter` class constructor: resolve `pushgatewayUrl` from options then `PUSHGATEWAY_URL` env var; create per-instance `Registry`; create `stepHistogram` (`synthetic_step_duration_seconds`, labels `test_suite test_name step_name status environment`, buckets `0.1 0.25 0.5 1 2.5 5 10 30`); create `testHistogram` (`synthetic_test_duration_seconds`, labels `test_suite test_name status environment`, buckets `1 5 10 30 60 120 300`); create `Pushgateway` or set to `null` with stderr warning if URL absent — `packages/synthetics/src/reporter/index.ts`
- [x] T012 [US1] Implement `onStepEnd(test, result, step)` in `SyntheticsReporter` — filter: skip if `step.parent !== undefined` OR `step.category !== 'test.step'`; resolve labels via `resolveTestSuite` + `test.title` + `step.title` + `deriveStepStatus` + `GRID_ENV ?? 'unknown'`; call `stepHistogram.labels({...}).observe(step.duration / 1000)` — `packages/synthetics/src/reporter/index.ts`
- [x] T013 [US1] Create package root export `src/index.ts` — re-export `SyntheticsReporter` and `SyntheticsReporterOptions` from `./reporter/index.js` (use `.js` extension for NodeNext ESM resolution) — `packages/synthetics/src/index.ts`
- [x] T014 [US1] Build package: add `"build": "tsc"` and `"test": "node --experimental-vm-modules node_modules/.bin/jest"` scripts to `package.json`; run `npm run build` and verify `dist/reporter/index.js` and `dist/index.js` are emitted — `packages/synthetics/package.json`
- [x] T015 [US1] Add `SyntheticsReporter` to `playwright-synthetics/playwright.config.ts` reporter array: `['@the-grid/synthetics/reporter', { pushgatewayUrl: process.env.PUSHGATEWAY_URL, jobName: 'the-grid' }]` — `playwright-synthetics/playwright.config.ts`
- [x] T016 [US1] Remove all prom-client boilerplate from `playwright-synthetics/tests/http-bin.spec.ts`: delete `import * as client from 'prom-client'`, `new client.Registry()`, `new client.Histogram(...)`, `const register`, `startTimer` calls, `timer()` calls, `test.afterEach` push block — `playwright-synthetics/tests/http-bin.spec.ts`

**Checkpoint**: `make test` passes. `grep -r "prom-client" playwright-synthetics/tests/` returns nothing. Step histogram emits with correct labels when `PUSHGATEWAY_URL` is set.

---

## Phase 4: US2 — End-to-End Test Duration Histogram (Priority P1)

**Goal**: `onTestEnd` records test-level duration and status; pushes all accumulated metrics to Pushgateway after each test. Non-blocking on push failure.

**Independent Test**: quickstart.md Scenario 2 — `synthetic_test_duration_seconds` in Pushgateway with 4 labels (no `step_name`). Scenario 4 — unreachable Pushgateway URL, tests still pass, warning on stderr.

- [x] T017 [US2] Implement `onTestEnd(test, result)` in `SyntheticsReporter` — resolve labels; call `testHistogram.labels({test_suite, test_name, status, environment}).observe(result.duration / 1000)`; if gateway is non-null call `await gateway.pushAdd({ jobName: this.options.jobName })` inside a try/catch that logs `[SyntheticsReporter] push failed: ${err.message}` to stderr and does NOT re-throw — `packages/synthetics/src/reporter/index.ts`

**Checkpoint**: Both histograms populate. Pushgateway push error logs to stderr and test exit code is unaffected.

---

## Phase 5: US3 — Remove Operator Metric Injection (Priority P2)

**Goal**: `syntheticTestMetrics()` removed from the operator. `synthetic_test_duration_seconds` has one authoritative source (the reporter).

**Independent Test**: quickstart.md Scenario 5 — `make test` in `synthetics-operator/` passes; Argo metrics endpoint returns no `synthetic_test_duration_seconds` line.

- [x] T018 [US3] Remove `Metrics: syntheticTestMetrics(syntheticTest.Name),` assignment at line 160 from the template struct literal — `synthetics-operator/internal/controller/synthetictest_controller.go`
- [x] T019 [US3] Remove the `syntheticTestMetrics` function (lines 232–269) and its doc comment (lines 232–237); remove `"encoding/json"` and `"strconv"` from the import block (both are only used by `syntheticTestMetrics`) — `synthetics-operator/internal/controller/synthetictest_controller.go`
- [x] T020 [US3] Run `make test` from `synthetics-operator/` and confirm all tests pass — `synthetics-operator/`

**Checkpoint**: `go build ./...` succeeds with no unused import errors. Operator e2e tests pass.

---

## Phase 6: Polish & Cross-Cutting

- [x] T021 [P] Add `packages/synthetics/` to root `.gitignore` exclusions if needed; verify `dist/` is not committed — repo root `.gitignore`
- [x] T022 Run quickstart.md Scenario 6 end-to-end: `grep -r "prom-client\|new Registry\|new Histogram\|startTimer\|Pushgateway" playwright-synthetics/tests/` — expected: no output
- [x] T023 [P] Update `runner/package.json` to add `@the-grid/synthetics: "*"` so the runner image picks up the library at build time — `runner/package.json`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Foundational)**: Depends on Phase 1 completion (package.json must exist)
- **Phase 3 (US1)**: Depends on Phase 2 — LabelResolver and status types must exist
- **Phase 4 (US2)**: Depends on Phase 3 — `SyntheticsReporter` class must exist (T011)
- **Phase 5 (US3)**: Independent of Phases 3–4 — operator change can be done in parallel with TypeScript work after Phase 1
- **Phase 6 (Polish)**: Depends on Phases 3–5 complete

### Within Each Phase

- T009 and T010 (unit tests) can run in parallel with each other
- T011 (reporter constructor) must precede T012 (onStepEnd) and T017 (onTestEnd)
- T015 (wire config) and T016 (remove boilerplate) both depend on T014 (build succeeds)
- T018 and T019 (operator removals) can be done as one edit; T020 validates

### Parallel Opportunities

```bash
# Phase 2 — run unit tests in parallel:
T009: label-resolver.test.ts
T010: status.test.ts

# Phase 3 + Phase 5 — can proceed in parallel (different codebases):
T011–T016: packages/synthetics/ TypeScript work
T018–T020: synthetics-operator/ Go work
```

---

## Implementation Strategy

### MVP First (US1 only)

1. Complete Phase 1: Setup (workspace + package scaffold)
2. Complete Phase 2: Foundational (LabelResolver + status types + unit tests)
3. Complete Phase 3: US1 — step metrics wired in, boilerplate gone from test files
4. **STOP and VALIDATE**: `make test` passes, `grep prom-client tests/` empty, step histogram in Pushgateway
5. Ship or demo

### Incremental Delivery

1. Phase 1 + 2 → foundation
2. Phase 3 → step metrics live (MVP)
3. Phase 4 → test-level histogram + push (completes observability story)
4. Phase 5 → operator cleaned up (metric conflict resolved)
5. Phase 6 → polish + runner image update

---

## Notes

- All `.js` import extensions required in ESM source under `"module": "NodeNext"`
- `prom-client`'s `Pushgateway` constructor signature: `new Pushgateway(url, options?, registry?)`
- Step duration from Playwright is in **milliseconds** — divide by 1000 before calling `.observe()`
- `deriveStepStatus` timeout detection is explicitly best-effort per research.md
- The `synthetic_test_runs_total` counter (also injected by `syntheticTestMetrics`) is removed in US3 — it is not replaced. Test pass/fail is captured via the `status` label on `synthetic_test_duration_seconds`.
