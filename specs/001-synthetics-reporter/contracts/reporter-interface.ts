/**
 * Contract: @the-grid/synthetics/reporter
 *
 * This file defines the public interface of the Synthetics Reporter package.
 * It is a design contract — not runnable code — used to verify the implementation.
 */

// ─── Configuration ─────────────────────────────────────────────────────────

/**
 * Options accepted by SyntheticsReporter as the second argument in
 * playwright.config.ts reporter configuration.
 *
 * @example
 * // playwright.config.ts
 * reporter: [['@the-grid/synthetics/reporter', {
 *   pushgatewayUrl: 'http://pushgateway.the-grid-synthetics:9091',
 *   jobName: 'the-grid',
 * }]]
 */
export interface SyntheticsReporterOptions {
  /**
   * Prometheus Pushgateway URL.
   * Falls back to process.env.PUSHGATEWAY_URL if not supplied.
   * If neither is set, a warning is logged and metrics are not pushed.
   */
  pushgatewayUrl?: string;

  /**
   * Pushgateway job name used in the push request.
   * Defaults to "synthetic-tests".
   */
  jobName?: string;
}

// ─── Status types ───────────────────────────────────────────────────────────

/** Status values on synthetic_test_duration_seconds */
export type TestStatus = 'success' | 'failure' | 'timeout' | 'skip';

/** Status values on synthetic_step_duration_seconds */
export type StepStatus = 'success' | 'failure' | 'timeout';

// ─── Label contract ─────────────────────────────────────────────────────────

/**
 * Standard labels on synthetic_step_duration_seconds.
 * All five fields MUST be present on every observation.
 */
export interface StepLabels {
  test_suite: string;   // outermost describe block title; fallback: spec filename
  test_name: string;    // TestCase.title
  step_name: string;    // TestStep.title
  status: StepStatus;
  environment: string;  // process.env.GRID_ENV ?? 'unknown'
}

/**
 * Standard labels on synthetic_test_duration_seconds.
 * step_name is absent at the test level.
 */
export interface TestLabels {
  test_suite: string;
  test_name: string;
  status: TestStatus;
  environment: string;
}

// ─── LabelResolver contract ─────────────────────────────────────────────────

/**
 * Pure logic for deriving Prometheus labels from Playwright's reporter API.
 * No I/O. Fully unit-testable.
 */
export interface LabelResolver {
  /**
   * Derive test_suite from the TestCase's suite hierarchy.
   * Returns the first describe-type suite title walking up from test.parent.
   * Falls back to path.basename of the file suite title.
   */
  resolveTestSuite(test: import('@playwright/test/reporter').TestCase): string;

  /** Map TestResult.status to TestStatus. */
  resolveTestStatus(result: import('@playwright/test/reporter').TestResult): TestStatus;

  /**
   * Derive StepStatus from TestStep.error.
   * 'timeout' is best-effort: inferred from error message matching /timeout/i.
   */
  resolveStepStatus(step: import('@playwright/test/reporter').TestStep): StepStatus;
}

// ─── SyntheticsReporter contract ────────────────────────────────────────────

/**
 * Playwright Reporter implementation.
 * Constructed once per worker process by Playwright.
 *
 * Emits:
 *   synthetic_step_duration_seconds — per top-level test.step()
 *   synthetic_test_duration_seconds — per test, pushes to Pushgateway
 *
 * The reporter MUST NOT cause test failures due to push errors.
 */
export declare class SyntheticsReporter
  implements import('@playwright/test/reporter').Reporter
{
  constructor(options?: SyntheticsReporterOptions);
}

// ─── Package exports ────────────────────────────────────────────────────────

/**
 * @the-grid/synthetics/reporter exports SyntheticsReporter as the default
 * and named export.
 *
 * playwright.config.ts references the sub-path directly:
 *   reporter: [['@the-grid/synthetics/reporter', options]]
 *
 * TypeScript consumers can also import the types:
 *   import type { SyntheticsReporterOptions } from '@the-grid/synthetics/reporter'
 */
