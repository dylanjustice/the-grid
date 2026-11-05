# Feature Specification: MVP Helm Chart

**Feature Branch**: `005-helm-chart-mvp`

**Created**: 2026-11-02

**Status**: Draft

**Input**: User description: "I want to get the helm chart to MVP."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Install The Grid with a single Helm command (Priority: P1)

A developer at another company has a Kubernetes cluster with Argo Workflows available (or wants The Grid to install it). They run `helm install the-grid-synthetics` pointing at the published chart and the platform is running: the operator is deployed, the CRDs are registered, Argo Workflows is available, and the Pushgateway is ready to receive metrics.

**Why this priority**: This is the entire premise of distribution. Nothing else matters until someone outside the repo can install and run the platform. All other stories depend on this one succeeding.

**Independent Test**: Can be validated by running `helm install` against a clean cluster (kind, k3s, or EKS) and verifying the operator pod reaches `Running` and the CRDs are registered.

**Acceptance Scenarios**:

1. **Given** a Kubernetes cluster with no prior Grid installation, **When** a user runs `helm install` using the published chart, **Then** the operator deployment reaches `Running`, the `SyntheticTest` and `SyntheticTestRun` CRDs are registered, Argo Workflows is available, and the Pushgateway is running.
2. **Given** a cluster that already has Argo Workflows installed, **When** a user installs with `--set argo-workflows.enabled=false`, **Then** the operator deploys and the CRDs register without touching the existing Argo installation.
3. **Given** a cluster that already has a Prometheus Pushgateway, **When** a user installs with `--set pushgateway.enabled=false`, **Then** the chart does not deploy a second Pushgateway instance.

---

### User Story 2 - Apply a SyntheticTest and have it run (Priority: P2)

After installing the chart, the same developer writes a `SyntheticTest` CR with an inline Playwright test and a schedule. They apply it with `kubectl apply`. The operator reconciles it into a CronWorkflow. At the next scheduled time, the test runs and pushes metrics to the Pushgateway.

**Why this priority**: This validates the full end-to-end path: chart installs → operator runs → user creates a CR → test executes → metrics flow. It is the minimum proof that the platform is functional, not just deployable.

**Independent Test**: Can be validated by applying a sample `SyntheticTest` CR after a `helm install` and waiting for a CronWorkflow to appear and execute.

**Acceptance Scenarios**:

1. **Given** the chart is installed, **When** a user applies a `SyntheticTest` CR with `spec.source.inline` and a valid cron schedule, **Then** the operator creates a `CronWorkflow`, a `ConfigMap` with the test source, and the necessary RBAC resources, all without requiring the user to specify `PUSHGATEWAY_URL` explicitly.
2. **Given** the operator is running, **When** a `CronWorkflow` executes, **Then** the runner pod receives the Pushgateway URL automatically via an injected environment variable matching the chart-deployed Pushgateway service.
3. **Given** a `SyntheticTest` CR is deleted, **Then** the operator removes the owned `CronWorkflow`, `ConfigMap`, and RBAC resources.

---

### User Story 3 - Configure the runner image via values (Priority: P3)

A user installing the chart wants to use their own runner image (different registry, pinned version, custom additions). They set `runner.image` in their `values.yaml` and the operator uses that image for all test pods it creates — no code change or operator restart required beyond a `helm upgrade`.

**Why this priority**: The hardcoded ECR image URI in the current operator breaks any installation outside the maintainer's own AWS account. This must be configurable for the chart to be usable by anyone else.

**Independent Test**: Can be validated by installing with a custom `runner.image` value and verifying the CronWorkflow pods created by the operator use that image.

**Acceptance Scenarios**:

1. **Given** a chart installation with `runner.image` set to a custom registry URI, **When** the operator creates a `CronWorkflow` for a `SyntheticTest` CR that does not specify `container.image`, **Then** the pod uses the `runner.image` from the chart values.
2. **Given** a `SyntheticTest` CR with `spec.container.image` explicitly set, **When** the operator creates the workflow, **Then** the pod uses the CR-level image override, not the chart default.

---

### User Story 4 - Publish a new chart release via CI (Priority: P4)

A maintainer triggers a release. CI builds the operator image, tags it with the short git SHA, pushes it to the configured container registry, and publishes the updated Helm chart as an OCI artifact to the configured chart registry. The new chart version is available via `helm install` shortly after.

**Why this priority**: Without a publish pipeline, every release is a manual, error-prone operation. This is the difference between a product and a personal tool.

**Independent Test**: Can be validated by triggering a release and confirming a new chart version appears in the OCI registry.

**Acceptance Scenarios**:

1. **Given** a release is triggered, **When** the CI pipeline runs, **Then** a new operator image tagged with the short git SHA is pushed to the configured container registry, and a new Helm chart version is published to the configured OCI chart registry.
2. **Given** CI completes, **When** a user runs `helm install` with the new chart version, **Then** the installed operator image matches the SHA from the triggering commit.

---

### Edge Cases

- What happens when `helm install` is run on a cluster where the `thegrid.io` CRDs already exist (e.g., a prior manual install)? Helm skips CRDs in `crds/` if they already exist — no conflict. Prior manually-applied CRDs are left in place; users must delete them if they want Helm to re-own them.
- What happens on `helm upgrade` when the CRD schema has changed? Because CRDs live in `crds/`, Helm does NOT apply them on upgrade. Maintainers MUST document and provide a `kubectl apply` command for CRD upgrades in release notes.
- What happens if the Pushgateway is disabled (`pushgateway.enabled=false`) but no `pushgateway.externalUrl` is provided? The operator should still start; metrics push failures are logged and non-blocking per Constitution principle V.
- What happens when `helm upgrade` changes `runner.image`? Existing CronWorkflows should be patched to use the new image on the operator's next reconciliation cycle.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The chart MUST deploy the operator as a `Deployment` with the image configurable via `operator.image` in `values.yaml`. The default image MUST point to the published operator image in the project's chosen container registry.
- **FR-002**: The chart MUST install the `SyntheticTest` and `SyntheticTestRun` CRDs from the `thegrid.io` API group via Helm's native `crds/` directory (the `cache.the-grid.io` variants MUST NOT be included). CRDs are installed on first install; schema upgrades require manual `kubectl apply` on the CRD manifests, consistent with the pattern used by ArgoCD, cert-manager, and the Prometheus Operator.
- **FR-003**: The chart MUST create a `ServiceAccount`, `ClusterRole`, `ClusterRoleBinding`, and leader-election `Role` + `RoleBinding` for the operator, using `{{ .Release.Name }}` namespacing to avoid conflicts across installs. The operator runs in the installation namespace; test runner pods and the Pushgateway run in a separate workload namespace configurable via `workloadNamespace` in `values.yaml`, defaulting to `the-grid-synthetics`. The chart MUST create this namespace if it does not exist.
- **FR-004**: The operator MUST read `runner.image` from its startup configuration and use it as the default container image when building `CronWorkflow` pods, replacing the current hardcoded ECR URI.
- **FR-005**: The operator MUST automatically inject `PUSHGATEWAY_URL` into every `CronWorkflow` it creates, resolving the value from its own startup configuration (sourced from the chart-deployed Pushgateway service DNS). Users MUST NOT be required to set `PUSHGATEWAY_URL` in their `SyntheticTest` CR.
- **FR-006**: When `pushgateway.enabled=true`, the Pushgateway URL injected by the operator MUST resolve to the chart-deployed Pushgateway service. When `pushgateway.enabled=false` and `pushgateway.externalUrl` is set, the operator MUST use that URL instead.
- **FR-007**: The chart MUST pass `runner.image` and the resolved Pushgateway URL to the operator at deploy time, via environment variables or startup flags on the operator `Deployment`.
- **FR-008**: The chart MUST include a `values.yaml` `operator:` section with at minimum `image` and `resources` fields.
- **FR-009**: Pushing a semver git tag (e.g. `v0.2.0`) MUST trigger a CI release pipeline that builds the operator image, tags it with both the git tag and the short git SHA, and pushes it to the project's configured container registry. Merges to `main` MUST run tests and build images but MUST NOT publish a new chart version.
- **FR-010**: The release CI pipeline triggered by a git tag MUST package and publish the Helm chart as an OCI artifact to the project's configured chart registry, with the chart version matching the git tag.
- **FR-011**: Argo Workflows and the Pushgateway MUST remain independently toggleable via `argo-workflows.enabled` and `pushgateway.enabled` in `values.yaml`, consistent with the existing `Chart.yaml` dependency declarations.

### Key Entities

- **SyntheticTest CR**: The user-facing resource that declares a scheduled test — source, schedule, runner config. The operator owns its full lifecycle per Constitution principle III.
- **SyntheticTestRun CR**: A read-only record of each completed workflow execution, created by the operator after each run completes.
- **Operator Deployment**: The controller-runtime process that reconciles `SyntheticTest` CRs into Argo `CronWorkflow` resources.
- **Runner image**: The container image containing Playwright, browsers, and node_modules. No test files — those are injected via `ConfigMap` at pod startup.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A developer with no prior knowledge of The Grid's internals can go from zero to a running synthetic test by following the installation documentation — no steps outside of `helm install` + `kubectl apply` of a sample CR.
- **SC-002**: Running `helm install` on a clean cluster takes under 5 minutes to reach a fully operational state (operator running, CRDs registered, first test executable).
- **SC-003**: Pushing a release tag results in a new, installable chart version published to the OCI registry within 10 minutes.
- **SC-004**: A `SyntheticTest` CR with no `container.image` and no `PUSHGATEWAY_URL` env var produces a running workflow that pushes metrics successfully, using chart defaults for both.
- **SC-005**: Installing the chart with `argo-workflows.enabled=false` and `pushgateway.enabled=false` does not deploy those components, and the operator still starts correctly.

## Assumptions

- Users have a working Kubernetes cluster (any CNCF-conformant distribution) with permissions to install CRDs and create `ClusterRole` resources.
- `argo-workflows.enabled=true` is the default; users who bring their own Argo installation are expected to set it to `false`.
- The specific OCI registry for operator images and the Helm chart is not prescribed by this spec — it is a release infrastructure decision. ECR is used for dev/CI builds today and may serve as an interim registry.
- The Helm chart version matches the git release tag (semver). Releases are triggered by pushing a tag — not by merges to `main`. Breaking changes require a major/minor version bump in the tag.
- The chart does not bundle a UI in this milestone — `ui.enabled` remains in values.yaml as a forward-looking stub but does nothing.
- The operator accepts `--runner-image` and `--pushgateway-url` as startup flags (or equivalent env vars); adding these flags to the operator binary is in scope for this feature.
- GitHub Actions is the CI platform (consistent with the existing repo on GitHub).

## Clarifications

### Session 2026-11-04

- Q: Should the spec prescribe a specific OCI registry for published images and charts? → A: No — registry selection is a release infrastructure decision deferred from this spec. ECR is acceptable as an interim registry; ghcr.io and quay.io are likely long-term options for open source, but the spec should remain registry-agnostic.
- Q: How should CRD installation and upgrade be handled — Helm native `crds/` directory, `templates/` with auto-upgrade, or `templates/` with pre-upgrade hooks? → A: Option A — Helm native `crds/` directory. CRDs install on first install; schema upgrades require manual `kubectl apply`, consistent with ArgoCD, cert-manager, and Prometheus Operator.
- Q: Should `helm install` deploy everything into one namespace, or should test workloads run separately from the operator? → A: Operator runs in the installation namespace; test runner pods and Pushgateway run in a configurable separate workload namespace (default: `the-grid-synthetics`).
- Q: What should trigger a chart release — every merge to `main` or a git tag? → A: Git tag (e.g. `v0.2.0`) triggers the release. Merges to `main` run tests and build images only.
