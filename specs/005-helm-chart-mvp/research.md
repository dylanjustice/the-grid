# Research: MVP Helm Chart

## CRD Placement Strategy

**Decision**: CRDs in `charts/the-grid-synthetics/crds/` (Helm native)

**Rationale**: Helm installs resources in `crds/` before any `templates/` resources, ensuring the API server accepts CRD-typed objects before the operator tries to register controllers. Helm skips CRDs in `crds/` on `helm upgrade` — this is intentional and matches the established pattern for operator charts (ArgoCD, cert-manager, Prometheus Operator). CRD schema upgrades require a manual `kubectl apply` step documented in release notes.

**Alternatives considered**:
- `templates/` with `helm.sh/resource-policy: keep` annotation: keeps CRDs on uninstall but still upgrades on `helm upgrade`, risking destructive schema migrations without user awareness. Rejected.
- Pre-upgrade hook running `kubectl apply`: adds a `Job` resource and service account to the chart for a one-time operation. More moving parts for marginal benefit. Rejected.

**Source files**: Copy `synthetics-operator/config/crd/bases/thegrid.io_synthetictests.yaml` and `thegrid.io_synthetictestruns.yaml`. Do NOT copy the `cache.the-grid.io_*` variants — those are stale kubebuilder artifacts.

---

## Operator Startup Flags

**Decision**: Add `--runner-image` and `--pushgateway-url` flags to `synthetics-operator/cmd/main.go` using the existing `flag` package; pass values as fields on `DefaultWorkflowBuilder`.

**Rationale**: The operator already uses `flag.StringVar` for all configuration (metrics address, probe address, leader election, cert paths). Adding two more flags is consistent with the existing pattern. The values flow: Helm `values.yaml` → operator `Deployment` env vars → `flag` reads env-sourced args or direct flags → passed to `DefaultWorkflowBuilder` struct fields → used in `buildWorkflowSpec`.

**Implementation path**:

```go
// cmd/main.go — add after existing flag declarations
var runnerImage string
var pushgatewayURL string
flag.StringVar(&runnerImage, "runner-image", "", "Default container image for runner pods")
flag.StringVar(&pushgatewayURL, "pushgateway-url", "", "Pushgateway URL injected into every CronWorkflow")

// Pass to builder
WorkflowBuilder: &controller.DefaultWorkflowBuilder{
    RunnerImage:    runnerImage,
    PushgatewayURL: pushgatewayURL,
},
```

```go
// internal/controller/workflow_builder.go
type DefaultWorkflowBuilder struct {
    RunnerImage    string
    PushgatewayURL string
}
```

The `buildWorkflowSpec` method uses `b.RunnerImage` as the fallback when `container.Image` is empty (replacing the `defaultImage` constant). `b.PushgatewayURL` is injected as `PUSHGATEWAY_URL` env var on the container spec.

**Validation**: If `--runner-image` is empty at startup, the operator should log a warning but not exit — users may always set `container.Image` on the CR directly. If `--pushgateway-url` is empty, existing behaviour is preserved (no env var injected; push failures are non-fatal per Constitution V).

**Alternatives considered**:
- Reading env vars directly in `buildWorkflowSpec`: bypasses flag infrastructure already in place and makes testing harder. Rejected.
- A separate config struct loaded from a ConfigMap: adds operator complexity for two values. Rejected.

---

## Helm Chart RBAC Pattern

**Decision**: ClusterRole + ClusterRoleBinding (cluster-scoped) for the operator's main permissions; namespaced Role + RoleBinding in the installation namespace for leader election.

**Rationale**: The operator watches `SyntheticTest` CRs cluster-wide and creates namespaced resources (CronWorkflows, ConfigMaps, RBAC) in the workload namespace. This requires cluster-scoped read access to `SyntheticTest` and `SyntheticTestRun`, and namespace-scoped write access to Argo and core resources in the workload namespace. The existing `config/rbac/role.yaml` is already a `ClusterRole` with exactly these permissions — reuse it verbatim.

**Naming**: Use `{{ include "the-grid-synthetics.fullname" . }}` for all RBAC resource names to avoid collisions across releases in the same cluster.

---

## Namespace Strategy

**Decision**: Operator runs in `{{ .Release.Namespace }}` (the installation namespace). A separate workload namespace (default: `the-grid-synthetics`, configurable via `workloadNamespace` in values) is created by the chart as a `Namespace` resource in `templates/namespace.yaml`.

**Rationale**: Separation mirrors the production intent: the operator is a platform component; the runner pods and Pushgateway are workload components. Users installing the chart into a namespace like `grid-system` don't want runner pods there. The workload namespace is owned by the chart release (annotated with `helm.sh/resource-policy: keep` to prevent accidental deletion of running test infrastructure on chart uninstall — user must delete manually).

**Pushgateway placement**: The Pushgateway dependency is deployed into the workload namespace by setting `pushgateway.namespaceOverride: {{ .Values.workloadNamespace }}` in the chart's dependency values passthrough.

**Argo Workflows placement**: Argo Workflows deploys into its own namespace (`argo` by default) as controlled by its own chart. The Grid chart sets the workload namespace in its values so the operator knows where to create `CronWorkflow` resources.

**Operator RBAC extension**: The ClusterRoleBinding for the operator's ServiceAccount must grant the ClusterRole regardless of which namespace the operator pod runs in. The leader election Role and RoleBinding are namespaced to the installation namespace only.

---

## GitHub Actions CI/Release Pipeline

**Decision**: Two workflows — `ci.yml` (every push/PR) and `release.yml` (semver tag push).

**`ci.yml`**:
- Trigger: `push` to `main`, `pull_request` targeting `main`
- Jobs: `go test ./...` for operator; `helm lint` + `helm template` for chart; `docker build` (no push) for operator image

**`release.yml`**:
- Trigger: `push` with tag pattern `v*.*.*`
- Steps:
  1. `docker/build-push-action` → push to configured registry with tags `${{ github.ref_name }}` and `latest`
  2. `helm package charts/the-grid-synthetics` → produces `.tgz`
  3. `helm registry login` + `helm push` → push OCI artifact to `oci://<registry>/charts/the-grid-synthetics`
  4. The chart version in `Chart.yaml` must match the git tag at release time — enforced by a pre-release validation step that checks `Chart.yaml` version == tag

**Registry configuration**: Registry URLs stored as GitHub Actions secrets (`REGISTRY_HOST`, `REGISTRY_USERNAME`, `REGISTRY_TOKEN`). The chart `Chart.yaml` is not auto-modified by CI — the maintainer bumps `Chart.yaml` version and the operator image tag in `values.yaml` as part of the release commit, then pushes the tag.

**Alternatives considered**:
- `helm/chart-releaser-action`: designed for GitHub Pages-hosted chart repos, not OCI. Rejected — OCI is the target.
- Auto-bumping `Chart.yaml` in CI: requires a git write-back step, adds complexity and a "bot commit." Rejected in favour of explicit maintainer version bumps.

---

## Helm Helpers Template

**Decision**: Standard `_helpers.tpl` with `fullname`, `name`, `labels`, and `selectorLabels` helpers following Helm starter chart conventions.

The `fullname` helper caps at 63 characters (Kubernetes label value limit) and handles `nameOverride` / `fullnameOverride` values. All resource names, label selectors, and RBAC bindings reference `{{ include "the-grid-synthetics.fullname" . }}` for consistency.
