<!--
SYNC IMPACT REPORT (remove before committing)
=============================================
Version change: [unversioned placeholder] → 1.0.0
Added sections:
  - Core Principles (all 5 principles, initial ratification)
  - Technology Constraints (new)
  - Development Workflow (new)
  - Governance (new)
Modified principles: N/A (initial ratification)
Removed sections: N/A
Deferred TODOs: None
=============================================
-->

# The Grid Constitution

## Core Principles

### I. GitOps is the Single Source of Truth

All platform state MUST be declared in `gitops/` and reconciled by ArgoCD from the `main` branch.
Manual `kubectl apply` to production namespaces is prohibited. No exceptions for "quick fixes" —
every change goes through a commit and the GitOps reconciliation loop.

**Rationale:** Drift between the repo and the cluster is invisible and dangerous. The repo is
always authoritative; the cluster is always derived.

### II. The Helm Chart is the Product Boundary

Every feature MUST ship as a configurable part of the Helm chart (`gitops/workloads/`). If
a capability cannot be toggled via `values.yaml`, it is not yet a product feature — it is
infrastructure scaffolding in the dev environment only.

**Rationale:** The product vision is a single `helm install`. Anything that requires manual
post-install steps or out-of-band configuration fails that promise.

### III. The Operator Owns the Test Lifecycle

`SyntheticTest` and `SyntheticTestRun` CRDs are the user-facing API. The operator MUST manage
the complete lifecycle: CR create → CronWorkflow provision; CR update → CronWorkflow patch;
CR delete → CronWorkflow and ConfigMap cleanup. Direct CronWorkflow authorship (bypassing the
operator) is only permitted during pre-operator milestones and MUST be removed before the
operator milestone ships.

**Rationale:** Bypassing the operator creates unmanaged resources that the operator will fight
over. Consistency of ownership prevents split-brain cluster state.

### IV. Zero-Boilerplate Test Instrumentation

All synthetic tests MUST use `@the-grid/synthetics` once milestone 1 ships. Raw `prom-client`
calls in individual test files are a stopgap and MUST NOT be introduced after the library is
published. Standardized labels (`test_suite`, `step_name`, `status`, `environment`) are
non-negotiable — custom label sets are not permitted without a constitution amendment.

**Rationale:** Consistent labels are the prerequisite for every cross-test dashboard and
alerting rule. Label drift makes the metrics useless at scale.

### V. Observability is Non-Blocking

Every test run MUST push metrics to the Pushgateway; a push failure MUST surface as a logged
error and SHOULD NOT abort the test run itself. Artifact uploads (HTML report, screenshots,
traces) are best-effort: failures are logged but MUST NOT cause the workflow to fail.

**Rationale:** The job of a synthetic test is to report on the system under test, not to fail
because the monitoring pipeline had a hiccup. Partial observability is better than no test result.

## Technology Constraints

- **Operator runtime:** Go + controller-runtime (kubebuilder scaffold). No alternative languages
  for the operator core.
- **Synthetics library and runner:** TypeScript / Node 23. Test files are `.spec.ts` executed
  by Playwright.
- **Workflow engine:** Argo Workflows exclusively. No raw Kubernetes `CronJob` resources for
  test scheduling after the operator is in place.
- **Metrics pipeline:** `prom-client` → Prometheus Pushgateway → Prometheus. No direct Prometheus
  remote write from test runners.
- **Infrastructure:** Terraform for VPC/EC2/ECR (`live/flynn/`). ArgoCD for in-cluster workload
  lifecycle. No mixing of the two.
- **Container registry:** ECR for dev/CI images; `ghcr.io/the-grid/` for published release images.

## Development Workflow

- All common operations MUST go through `make`. Adding a new operation means adding a `make`
  target, not documenting a raw command.
- Tests (`playwright-synthetics/tests/`) MUST pass headlessly (`make test`) before any PR is
  merged. Interactive mode (`make test-ui`) is for local development only.
- Docker images are tagged with the short git SHA. `latest` is a convenience alias only; production
  manifests MUST reference SHA-tagged images.
- The dev k3s cluster (EC2 t4g.medium, ARM64) is the proving ground. Breaking it is acceptable;
  breaking the Helm chart contract is not.
- Pushing to `main` triggers ArgoCD reconciliation within ~3 minutes. Force-sync with
  `make argo-sync` is permitted but MUST NOT become a substitute for fixing root causes.

## Governance

This constitution supersedes all other engineering practices for The Grid. Conflicts between
this document and any other guide, README, or convention are resolved in favor of this document.

**Amendment procedure:**
1. Open a PR to `main` with the proposed change to `.specify/memory/constitution.md`.
2. State the version bump type (MAJOR/MINOR/PATCH) and rationale in the PR description.
3. At least one additional contributor MUST review and approve before merge.
4. Update `LAST_AMENDED_DATE` and `CONSTITUTION_VERSION` in the version line.

**Versioning policy:** Semantic versioning applies.
- MAJOR: Removal or redefinition of a principle that breaks backward compatibility with existing
  practices.
- MINOR: New principle, new section, or materially expanded guidance.
- PATCH: Clarifications, wording fixes, non-semantic refinements.

**Compliance:** All PRs MUST be evaluated against the principles above. A PR that violates a
principle MUST either be revised to comply or be accompanied by a constitution amendment that
explicitly revises the relevant principle.

**Version**: 1.0.0 | **Ratified**: 2026-10-13 | **Last Amended**: 2026-10-13
