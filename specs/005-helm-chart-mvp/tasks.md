# Tasks: MVP Helm Chart

**Input**: Design documents from `specs/005-helm-chart-mvp/`

**Prerequisites**: plan.md ✓, spec.md ✓, research.md ✓, data-model.md ✓, contracts/values-schema.md ✓, quickstart.md ✓

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story. No test tasks (not requested in spec).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks in this phase)
- **[Story]**: Which user story this task belongs to (US1–US4)

---

## Phase 1: Setup

**Purpose**: Chart skeleton and CRD files in place. No operator code changes yet.

- [X] T001 Create `charts/the-grid-synthetics/templates/_helpers.tpl` defining: `the-grid-synthetics.name`, `the-grid-synthetics.fullname` (capped at 63 chars, respects `nameOverride`/`fullnameOverride`), `the-grid-synthetics.labels` (including `helm.sh/chart`, `app.kubernetes.io/name`, `app.kubernetes.io/instance`, `app.kubernetes.io/managed-by`), `the-grid-synthetics.selectorLabels` (`app.kubernetes.io/name` + `instance`), and `the-grid-synthetics.pushgatewayURL` (returns `http://{{ .Release.Name }}-prometheus-pushgateway.{{ .Values.workloadNamespace }}.svc:9091` when `pushgateway.enabled=true`, otherwise `{{ .Values.pushgateway.externalUrl }}`)

- [X] T002 Update `charts/the-grid-synthetics/values.yaml` to add: `operator.image: ""` (placeholder, set at release), `operator.resources.requests.cpu: 10m`, `operator.resources.requests.memory: 64Mi`, `operator.resources.limits.cpu: 500m`, `operator.resources.limits.memory: 128Mi`, and `workloadNamespace: the-grid-synthetics` — keeping existing `runner:`, `argo-workflows:`, `pushgateway:`, and `ui:` sections intact

- [X] T003 [P] Copy `synthetics-operator/config/crd/bases/thegrid.io_synthetictests.yaml` and `synthetics-operator/config/crd/bases/thegrid.io_synthetictestruns.yaml` into `charts/the-grid-synthetics/crds/` — do NOT copy the `cache.the-grid.io_*` variants

- [X] T004 [P] Run `helm dependency update charts/the-grid-synthetics` from the repo root to pull the `argo-workflows` and `prometheus-pushgateway` dependency charts into `charts/the-grid-synthetics/charts/`

---

## Phase 2: Foundational — Operator startup flags

**Purpose**: Operator binary gains `--runner-image` and `--pushgateway-url` flags. These block US2 and US3 (the chart wires these flags in Phase 3).

**⚠️ CRITICAL**: The chart Deployment template (Phase 3 T015) cannot correctly wire values until these changes are in place.

- [X] T005 Add `RunnerImage string` and `PushgatewayURL string` fields to the `DefaultWorkflowBuilder` struct in `synthetics-operator/internal/controller/workflow_builder.go` — no other changes to the struct or interface

- [X] T006 Update `buildWorkflowSpec` in `synthetics-operator/internal/controller/workflow_builder.go`:
  1. Replace `container.Image = defaultImage` with `container.Image = b.RunnerImage` (keep the `if container.Image == ""` guard — only set when CR did not specify an image; if `b.RunnerImage` is also empty, leave `container.Image` empty rather than using the old ECR constant)
  2. After resolving the container image, if `b.PushgatewayURL != ""` and `PUSHGATEWAY_URL` is not already present in `container.Env`, prepend `corev1.EnvVar{Name: "PUSHGATEWAY_URL", Value: b.PushgatewayURL}` to `container.Env`
  3. Remove the `defaultImage` constant from `workflow_builder.go`

- [X] T007 Add two flags to `synthetics-operator/cmd/main.go` after the existing `flag.BoolVar(&enableHTTP2 ...)` declaration:
  ```go
  var runnerImage string
  var pushgatewayURL string
  flag.StringVar(&runnerImage, "runner-image", "", "Default container image for runner pods (overridden by SyntheticTest spec.container.image)")
  flag.StringVar(&pushgatewayURL, "pushgateway-url", "", "Pushgateway URL injected as PUSHGATEWAY_URL env var into every CronWorkflow")
  ```
  Then update the `SyntheticTestReconciler` instantiation to pass `WorkflowBuilder: &controller.DefaultWorkflowBuilder{RunnerImage: runnerImage, PushgatewayURL: pushgatewayURL}`

- [X] T008 [P] Update `synthetics-operator/internal/controller/workflow_builder_test.go` and `synthetics-operator/internal/controller/synthetictest_controller_builder_test.go`: replace all `DefaultWorkflowBuilder{}` instantiations with `DefaultWorkflowBuilder{RunnerImage: "test-runner:latest", PushgatewayURL: "http://pushgateway:9091"}` (or appropriate test values); add one test case to `workflow_builder_test.go` asserting that when `PushgatewayURL` is set the generated container env contains `PUSHGATEWAY_URL=<value>`, and that when `container.Image` is empty in the CR the `RunnerImage` field value is used; run `go test ./...` from `synthetics-operator/` and confirm all pass

**Checkpoint**: `go test ./...` passes. Operator binary accepts `--runner-image` and `--pushgateway-url` flags.

---

## Phase 3: User Story 1 — Install The Grid with a single Helm command (Priority: P1) 🎯 MVP

**Goal**: `helm install` deploys operator, registers CRDs, creates workload namespace, deploys Argo and Pushgateway.

**Independent Test**: `helm install` on a clean cluster → operator pod `Running`, CRDs registered, `the-grid-synthetics` namespace exists. See quickstart.md Scenario 1.

- [X] T009 [P] [US1] Create `charts/the-grid-synthetics/templates/serviceaccount.yaml` — a `ServiceAccount` named `{{ include "the-grid-synthetics.fullname" . }}` in `{{ .Release.Namespace }}` with standard labels from `the-grid-synthetics.labels`

- [X] T010 [P] [US1] Create `charts/the-grid-synthetics/templates/clusterrole.yaml` — adapt `synthetics-operator/config/rbac/role.yaml` into a Helm template: kind `ClusterRole`, name `{{ include "the-grid-synthetics.fullname" . }}`, preserve all rules verbatim from `config/rbac/role.yaml`, add standard labels

- [X] T011 [P] [US1] Create `charts/the-grid-synthetics/templates/clusterrolebinding.yaml` — kind `ClusterRoleBinding`, name `{{ include "the-grid-synthetics.fullname" . }}`, roleRef to the ClusterRole, subject the operator ServiceAccount in `{{ .Release.Namespace }}`

- [X] T012 [P] [US1] Create `charts/the-grid-synthetics/templates/leader-election-role.yaml` — adapt `synthetics-operator/config/rbac/leader_election_role.yaml` into a Helm template: kind `Role` (namespaced), name `{{ include "the-grid-synthetics.fullname" . }}-leader-election`, namespace `{{ .Release.Namespace }}`, preserve rules verbatim

- [X] T013 [P] [US1] Create `charts/the-grid-synthetics/templates/leader-election-rolebinding.yaml` — kind `RoleBinding`, name `{{ include "the-grid-synthetics.fullname" . }}-leader-election`, namespace `{{ .Release.Namespace }}`, roleRef to the leader-election Role, subject the operator ServiceAccount

- [X] T014 [P] [US1] Create `charts/the-grid-synthetics/templates/namespace.yaml` — kind `Namespace`, name `{{ .Values.workloadNamespace }}`, annotations `helm.sh/resource-policy: keep` (retains namespace and running test infrastructure on `helm uninstall`), standard labels

- [X] T015 [US1] Create `charts/the-grid-synthetics/templates/deployment.yaml` for the operator — adapt `synthetics-operator/config/manager/manager.yaml` into a Helm template:
  - `name: {{ include "the-grid-synthetics.fullname" . }}`
  - `namespace: {{ .Release.Namespace }}`
  - `image: {{ .Values.operator.image }}`
  - `resources: {{ toYaml .Values.operator.resources | nindent 12 }}`
  - `serviceAccountName: {{ include "the-grid-synthetics.fullname" . }}`
  - `args:` include `--leader-elect`, `--health-probe-bind-address=:8081`, `--runner-image={{ .Values.runner.image }}`, `--pushgateway-url={{ include "the-grid-synthetics.pushgatewayURL" . }}`
  - Preserve `livenessProbe`, `readinessProbe`, and `securityContext` from `manager.yaml` verbatim

- [X] T016 [US1] Run `helm lint charts/the-grid-synthetics` and resolve any errors or warnings

- [X] T017 [US1] Run `helm template the-grid charts/the-grid-synthetics --set operator.image=test/op:v1 --set runner.image=test/runner:v1` and confirm: operator Deployment present with correct image and args, ClusterRole and ClusterRoleBinding present, leader-election Role and RoleBinding present, workload Namespace present, CRD files present under `crds/`

**Checkpoint**: `helm lint` passes. `helm template` output is correct. Ready for cluster install.

---

## Phase 4: User Story 2 — SyntheticTest reconciles with auto-injected Pushgateway URL (Priority: P2)

**Goal**: A SyntheticTest CR applied after `helm install` produces a CronWorkflow with `PUSHGATEWAY_URL` already set — no manual env var in the CR.

**Independent Test**: Apply sample CR → inspect CronWorkflow env → `PUSHGATEWAY_URL` present and matches Pushgateway service. See quickstart.md Scenario 2.

- [X] T018 [US2] Run `helm template` with default values and pipe the Deployment through `grep pushgateway-url` to confirm the `--pushgateway-url` arg resolves to `http://the-grid-prometheus-pushgateway.the-grid-synthetics.svc:9091` (using release name `the-grid` and default `workloadNamespace`)

- [X] T019 [P] [US2] Run `helm template the-grid charts/the-grid-synthetics --set operator.image=test/op:v1 --set runner.image=test/runner:v1 --set pushgateway.enabled=false --set pushgateway.externalUrl=http://external-gw:9091` and confirm the `--pushgateway-url` arg in the Deployment equals `http://external-gw:9091`

- [X] T020 [US2] Update both `SyntheticTest` CRs in `gitops/workloads/playwright-synthetics/synthetics.yaml` — remove the `PUSHGATEWAY_URL` env var entry from both CRs' `spec.container.env` lists (the operator will now inject it automatically); keep `GRID_ENV` and `GRID_JOB_NAME` entries

**Checkpoint**: `helm template` wiring verified for both pushgateway modes. Dev cluster CRs updated — no PUSHGATEWAY_URL in CR spec.

---

## Phase 5: User Story 3 — Runner image configurable via values (Priority: P3)

**Goal**: `runner.image` in values flows through to CronWorkflow pods; CR-level `container.image` overrides it.

**Independent Test**: `helm install --set runner.image=custom/runner:v2` → apply SyntheticTest CR without `container.image` → CronWorkflow pod uses `custom/runner:v2`. See quickstart.md Scenario 3.

- [X] T021 [P] [US3] Run `helm template the-grid charts/the-grid-synthetics --set operator.image=test/op:v1 --set runner.image=custom/runner:v2` and confirm `--runner-image=custom/runner:v2` appears in the Deployment args

- [X] T022 [US3] Add a test case to `synthetics-operator/internal/controller/workflow_builder_test.go` asserting that when a `SyntheticTest` CR has `spec.container.image: "cr-override:latest"` set, the resulting CronWorkflow container image is `cr-override:latest` and NOT the `DefaultWorkflowBuilder.RunnerImage` value; run `go test ./...` from `synthetics-operator/` to confirm it passes

**Checkpoint**: Runner image flows from chart values to pod. CR-level override is confirmed by a passing unit test.

---

## Phase 6: User Story 4 — Publish a new chart release via CI (Priority: P4)

**Goal**: Pushing a semver git tag triggers CI to build + push the operator image and publish the Helm chart as an OCI artifact.

**Independent Test**: Push `v0.2.0` tag → CI completes → `helm pull oci://<registry>/charts/the-grid-synthetics --version 0.2.0` succeeds. See quickstart.md Scenario 6.

- [X] T023 [P] [US4] Create `.github/workflows/ci.yml`:
  - Triggers: `push` to `main`, `pull_request` targeting `main`
  - Job `test-operator`: checkout, `go test ./...` from `synthetics-operator/`
  - Job `lint-chart`: checkout, `helm lint charts/the-grid-synthetics`
  - Job `build-operator-image`: checkout, `docker build -f playwright-synthetics/Dockerfile .` (build only, no push — validates Dockerfile compiles)

- [X] T024 [US4] Create `.github/workflows/release.yml`:
  - Trigger: `push` with tag pattern `v*.*.*`
  - Job `validate-version`: checkout, extract tag name, read `version` field from `charts/the-grid-synthetics/Chart.yaml`, fail with an error message if they do not match (e.g. tag is `v0.2.0` but `Chart.yaml` has `version: 0.1.2`)
  - Job `release` (depends on `validate-version`):
    1. Checkout
    2. `docker/login-action` using secrets `REGISTRY_HOST`, `REGISTRY_USERNAME`, `REGISTRY_TOKEN`
    3. `docker/build-push-action` targeting `playwright-synthetics/Dockerfile`, push with tags `${{ secrets.REGISTRY_HOST }}/the-grid/operator:${{ github.ref_name }}` and `.../operator:latest`
    4. `helm registry login ${{ secrets.REGISTRY_HOST }}` using same secrets
    5. `helm package charts/the-grid-synthetics`
    6. `helm push the-grid-synthetics-*.tgz oci://${{ secrets.REGISTRY_HOST }}/charts`

- [X] T025 [P] [US4] Add `REGISTRY_HOST`, `REGISTRY_USERNAME`, and `REGISTRY_TOKEN` to the repo's GitHub Actions secrets documentation — create or update `docs/releasing.md` documenting: required secrets, how to bump `Chart.yaml` version before tagging, the tagging command (`git tag v0.x.y && git push origin v0.x.y`), and the CRD manual upgrade procedure for releases that change the CRD schema

**Checkpoint**: Both workflows present and syntactically valid (`act --list` or GitHub Actions UI). Release pipeline fails fast if Chart.yaml version and git tag are mismatched.

---

## Final Phase: Polish & Validation

**Purpose**: Clean up, verify end-to-end, update dev environment.

- [X] T026 [P] Update `charts/the-grid-synthetics/values.yaml` `operator.image` and `runner.image` placeholders to reference the actual first published image coordinates once the registry decision is made (can be done as part of the first real release commit)

- [X] T027 [P] Run `go test ./...` from `synthetics-operator/` to confirm the full test suite passes with all `DefaultWorkflowBuilder` struct changes

- [X] T028 Run quickstart.md Scenario 1 against a local kind or k3s cluster: `helm install` → verify operator `Running`, CRDs registered, workload namespace created

- [X] T029 Run quickstart.md Scenario 2 against the same cluster: apply the sample `SyntheticTest` CR → verify CronWorkflow created with `PUSHGATEWAY_URL` in env and correct `runner.image`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately; T003 and T004 are parallel
- **Phase 2 (Foundational)**: No dependency on Phase 1 (different files) — can run in parallel with Phase 1; T008 depends on T005+T006
- **Phase 3 (US1)**: Depends on Phase 1 (needs `_helpers.tpl` and `values.yaml`) and Phase 2 (T015 uses `--runner-image`/`--pushgateway-url` flags); T009–T014 parallelizable after T001; T015 depends on T001 and T014 (Namespace)
- **Phase 4 (US2)**: Depends on Phase 3 (chart wiring) and Phase 2 (operator flags); T020 is independent
- **Phase 5 (US3)**: Depends on Phase 2 (T005–T006); T021 depends on Phase 3 (T015)
- **Phase 6 (US4)**: Independent of Phases 2–5; can begin after Phase 1
- **Final Phase**: Depends on all prior phases

### User Story Dependencies

- **US1 (P1)**: Depends on Phase 1 + Phase 2 completion
- **US2 (P2)**: Depends on US1 + Phase 2; T020 (gitops update) is independent once Phase 2 is done
- **US3 (P3)**: Depends on Phase 2; verification tasks depend on Phase 3
- **US4 (P4)**: Independent — CI pipeline can be authored while Phases 2–3 are in progress

### Parallel Opportunities

- Phase 1 T003 + Phase 2 T005 + Phase 6 T023: can all start on day one
- Phase 3 RBAC templates T009–T014: all parallelizable once T001 exists
- Phase 5 T021 + Phase 6 T024: parallelizable

---

## Parallel Example: Phase 3 (US1 RBAC templates)

```
T009  serviceaccount.yaml
T010  clusterrole.yaml
T011  clusterrolebinding.yaml     ← all five can run in parallel
T012  leader-election-role.yaml
T013  leader-election-rolebinding.yaml
T014  namespace.yaml
              ↓ all complete
T015  deployment.yaml  (depends on T001 helpers + T009–T014 for the SA name reference)
              ↓
T016  helm lint
T017  helm template verify
```

---

## Implementation Strategy

### MVP First (US1 only)

1. Complete Phase 1: Setup (T001–T004)
2. Complete Phase 2: Foundational operator flags (T005–T008)
3. Complete Phase 3: US1 chart templates (T009–T017)
4. **STOP and validate**: `helm install` on a clean cluster per quickstart.md Scenario 1
5. MVP is shippable at this point — operator deploys, CRDs register, platform is installable

### Incremental Delivery

1. Phase 1 + Phase 2 → operator accepts flags
2. Phase 3 → `helm install` works (US1 ✓)
3. Phase 4 → Pushgateway URL auto-injected, dev CRs cleaned up (US2 ✓)
4. Phase 5 → runner image wiring confirmed end-to-end (US3 ✓)
5. Phase 6 → CI pipeline in place, ready to tag first release (US4 ✓)
6. Final Phase → validation + polish
