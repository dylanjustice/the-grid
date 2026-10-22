# Feature Specification: Artifact Storage

**Feature Branch**: `003-artifact-storage`

**Created**: 2026-10-20

**Status**: Draft

**Input**: User description: "Every test run produces browsable screenshots, HTML reports, and traces stored durably in a configurable S3-compatible object store."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Browse Failed Test Artifacts (Priority: P1)

An engineer whose synthetic test returned a failure wants to understand what went wrong. They navigate to the test run record, follow the artifact link, and open the HTML report in their browser. The report shows the test timeline, embedded screenshots at the point of failure, and a link to open the trace in Playwright's trace viewer.

**Why this priority**: This is the direct productivity payoff for artifact storage. Without it, failures require re-running the test locally to reproduce the issue — slow and unreliable for intermittent failures. This is the Datadog feature users actually pay for.

**Independent Test**: Trigger a test run that includes a failure. After the run completes, verify that an artifact link is present in the test run record and that the link leads to an accessible HTML report with embedded screenshots.

**Acceptance Scenarios**:

1. **Given** a test run has completed with at least one failure, **When** the engineer follows the artifact link in the test run record, **Then** they can view the HTML report in a browser with screenshots and traces embedded or linked.
2. **Given** a test run has completed successfully, **When** the engineer follows the artifact link, **Then** they can view the full HTML report including passing test details.
3. **Given** a test run produced screenshots and traces, **When** the engineer views the HTML report, **Then** screenshots are visible inline and trace files are accessible for download or direct viewer navigation.

---

### User Story 2 - Configure Artifact Store at Install Time (Priority: P2)

A platform operator installs The Grid via Helm into their Kubernetes cluster. They configure an artifact storage destination — either a cloud-hosted bucket (AWS S3 or GCS) or a self-hosted store (MinIO) — by setting values in the Helm chart. After the first test run completes, artifacts appear in the configured store at the expected path.

**Why this priority**: Artifact storage is useless without a working store configuration. Getting this right at install time prevents operators from needing to reconfigure the platform later.

**Independent Test**: Deploy the Helm chart with artifact store values set to a MinIO instance in the same cluster. Trigger a test run and confirm that artifacts appear in MinIO at the correct path with no additional manual steps.

**Acceptance Scenarios**:

1. **Given** an operator has set the artifact store endpoint, bucket name, and credentials in `values.yaml`, **When** the platform is deployed via Helm, **Then** subsequent test runs upload artifacts to that store automatically.
2. **Given** the platform is deployed with artifact storage enabled, **When** a test run completes, **Then** artifacts appear at the path `<bucket>/<test-name>/<run-id>/` within 2 minutes of run completion.
3. **Given** an operator has not configured an artifact store, **When** a test run completes, **Then** the workflow completes normally and logs a message indicating that artifact storage is disabled.

---

### User Story 3 - Audit Historical Test Runs (Priority: P3)

An engineer wants to compare screenshots from two different test runs — one from last week and one from today — to spot a UI regression. They retrieve artifact links from the two test run records and open both HTML reports side by side.

**Why this priority**: Historical access unlocks comparison workflows and incident retrospectives. It builds on P1 and P2 working correctly.

**Independent Test**: After two or more test runs have completed, verify that each test run record contains a distinct artifact link pointing to non-overlapping storage paths, and that both links remain accessible.

**Acceptance Scenarios**:

1. **Given** multiple test runs have completed over time, **When** an engineer retrieves their test run records, **Then** each record contains a unique artifact link pointing to that run's artifacts.
2. **Given** a test run completed 30 days ago, **When** the engineer follows its artifact link, **Then** the artifacts are still accessible (subject to operator-configured retention policy).

---

### Edge Cases

- What happens when the artifact store is unreachable at upload time? Upload failure is logged but does not mark the test run as failed; artifacts are not retried automatically.
- What happens when a test run produces no artifacts (e.g., the runner crashed before Playwright generated the report)? The upload step is skipped; the test run record contains no artifact link.
- What happens when the artifact bucket does not exist or the credentials are incorrect? The upload step fails with a logged error; the workflow completes; the platform operator is responsible for fixing the configuration.
- What happens when two test runs for the same test name occur simultaneously? Each run's artifacts are stored under a unique run identifier, preventing collision.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The platform MUST upload the complete artifact package (HTML report, screenshots, traces) to the configured store after each test run completes.
- **FR-002**: Artifact storage MUST be configurable through the platform's Helm chart `values.yaml`; no out-of-band configuration steps are permitted.
- **FR-003**: Each test run's artifacts MUST be stored at a path of the form `<test-name>/<run-id>/` within the configured bucket.
- **FR-004**: The platform MUST support any S3-compatible object store as the artifact backend.
- **FR-005**: Artifact upload failures MUST NOT cause the test workflow to be reported as failed; failures MUST be recorded in workflow logs.
- **FR-006**: Each test run record MUST store the full artifact location (bucket + path) upon successful upload so that consumers can navigate directly to the artifacts.
- **FR-007**: Artifact storage MUST be an opt-in feature; operators who have not configured a store MUST still be able to run the platform with no errors.
- **FR-008**: The platform MUST support two credential modes for the artifact store: static credentials (access key and secret) supplied via Helm values for self-hosted and GCS-interop deployments, and cloud-native IAM delegation (e.g., service account annotation on the workflow pod) for cloud deployments where no long-lived secret should be stored. Both modes MUST be configurable through `values.yaml` with no additional manual steps.

### Key Entities *(include if feature involves data)*

- **Test Run Artifact Package**: The set of output files produced by a single completed test run — the HTML report, embedded or linked screenshots, and one or more trace archives. Scoped to a single workflow execution.
- **Artifact Location**: A fully-qualified address for a test run's artifact package, consisting of a store endpoint (or named provider), a bucket name, and a prefix path encoding the test name and run identifier. Stored in the test run record after successful upload.
- **Artifact Store Configuration**: The operator-supplied settings (endpoint, bucket, credentials, enabled flag) that govern where and how artifacts are stored. Declared in Helm values; applied uniformly across all test runs on the platform.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of test runs that complete and produce a Playwright report have their artifacts uploaded to the configured store within 2 minutes of run completion.
- **SC-002**: A platform operator can enable artifact storage and complete a first successful artifact upload with no steps outside the Helm installation workflow.
- **SC-003**: Engineers can navigate to a specific test run's full artifact package in under 30 seconds by following the link in the test run record.
- **SC-004**: Artifact upload failures have zero impact on test pass/fail reporting; every failure is visible in the workflow's log output.
- **SC-005**: The platform works with at least three artifact store backends (a cloud S3 service, a GCS bucket in S3-interop mode, and a self-hosted MinIO instance) using only values-file configuration.

## Assumptions

- Artifact retention, lifecycle policies, and bucket access permissions are the platform operator's responsibility; the platform does not create or manage buckets.
- Test artifact packages are bounded in size by normal Playwright output (typically under 100 MB per run); unusually large packages may exceed upload time bounds but are not a design target.
- The test run record entity (and its artifact location field) is available when this feature ships; the spec does not prescribe the implementation of that record.
- Artifact browsing via a purpose-built UI is out of scope; the artifact link in the test run record is sufficient for this milestone.
- The artifact store is network-accessible from within the Kubernetes cluster where the platform is deployed.
