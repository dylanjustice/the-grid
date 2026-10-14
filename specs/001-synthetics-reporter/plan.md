# Implementation Plan: The Synthetics Reporter

**Branch**: `001-synthetics-reporter` | **Date**: 2026-10-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/001-synthetics-reporter/spec.md`

## Summary

Build `@the-grid/synthetics/reporter` — a Playwright Reporter plugin that auto-instruments every
Test Step and Synthetic Test with Prometheus histograms, pushing to a Pushgateway after each test.
Remove the conflicting Argo metric injection from the operator. Zero changes required to test files.

## Technical Context

**Language/Version**: TypeScript / Node 23

**Primary Dependencies**: `@playwright/test ^1.58` (reporter API), `prom-client ^15`
(histograms + Pushgateway client)

**Storage**: N/A — metrics are pushed to Pushgateway; no local persistence

**Testing**: Playwright test runner (integration), Jest or Vitest for unit tests of LabelResolver
and status derivation logic

**Target Platform**: Node.js process co-located with Playwright worker; Linux container (runner image)

**Project Type**: Library (`@the-grid/synthetics`) with sub-path export (`/reporter`)

**Performance Goals**: Push latency < 500ms per test; no measurable overhead on step duration

**Constraints**: Must not abort test run on push failure; `pushAdd` semantics required for parallel
worker safety; step depth filtering must exclude nested steps

**Scale/Scope**: One reporter instance per Playwright worker process; one metric push per test

## Constitution Check

_GATE: Must pass before Phase 0 research. Re-check after Phase 1 design._

| Principle                                                               | Status  | Notes                                                       |
| ----------------------------------------------------------------------- | ------- | ----------------------------------------------------------- |
| I. GitOps is the Single Source of Truth                                 | ✅ PASS | Library code in repo; no out-of-band deployment             |
| II. Helm Chart is the Product Boundary                                  | ✅ PASS | Reporter is a library dependency, not a deployed workload   |
| III. Operator Owns the Test Lifecycle                                   | ✅ PASS | Removing `syntheticTestMetrics()` cleans up operator scope  |
| IV. Zero-Boilerplate Test Instrumentation                               | ✅ PASS | This feature IS the implementation of Principle IV          |
| V. Observability is Non-Blocking                                        | ✅ PASS | FR-007 explicitly requires push failures not abort test run |
| Standard Labels (test_suite, test_name, step_name, status, environment) | ✅ PASS | FR-001–006 encode all five labels                           |

**No violations. Gate passes.**

## Project Structure

### Documentation (this feature)

```text
specs/001-synthetics-reporter/
├── plan.md              ← this file
├── research.md          ← Phase 0 output
├── data-model.md        ← Phase 1 output
├── quickstart.md        ← Phase 1 output
├── contracts/           ← Phase 1 output
└── tasks.md             ← Phase 2 output (/speckit-tasks)
```

### Source Code (repository root)

```text
packages/synthetics/
├── package.json                   # name: @the-grid/synthetics
├── tsconfig.json
├── src/
│   ├── reporter/
│   │   ├── index.ts               # SyntheticsReporter class (Reporter impl)
│   │   ├── label-resolver.ts      # LabelResolver — test_suite, status derivation
│   │   └── status.ts              # Status enum + derivation from TestResult/TestStep
│   └── index.ts                   # package root (re-exports; /reporter sub-path)
└── tests/
    ├── unit/
    │   ├── label-resolver.test.ts
    │   └── status.test.ts
    └── integration/
        └── reporter.spec.ts        # Playwright test that validates metric push

synthetics-operator/internal/controller/
└── synthetictest_controller.go    # remove syntheticTestMetrics() + call site

playwright-synthetics/
├── playwright.config.ts           # add reporter config
└── tests/
    └── http-bin.spec.ts           # remove prom-client boilerplate (6 lines → 0)
```

**Structure Decision**: New `packages/synthetics/` monorepo package. Keeps the library separate
from the dev test suite (`playwright-synthetics/`) while living in the same repo. The runner image
will pick it up as a local workspace dependency.

## Complexity Tracking

No constitution violations — section not required.
