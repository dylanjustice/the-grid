# Tasks: Artifact Storage

**Input**: Design documents from `specs/003-artifact-storage/`

**Prerequisites**: plan.md ✓, spec.md ✓, research.md ✓, data-model.md ✓, contracts/ ✓

**Organization**: Tasks grouped by user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks in the same phase)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Expand the CRD type and regenerate derived artifacts before any controller logic changes.

- [x] T001 Expand `ArtifactStorageSpec` in `synthetics-operator/api/v1alpha1/synthetictest_types.go` — replace the existing 1-field struct with the 6-field version from `specs/003-artifact-storage/contracts/artifact-storage-spec.go` adding `Bucket string`, `Endpoint string`, `Region string`, `CredentialsSecret string`, and `ServiceAccountAnnotations map[string]string`
- [x] T002 Regenerate deepcopy and CRD YAML — run `make generate manifests` in `synthetics-operator/` and commit the updated `synthetics-operator/api/v1alpha1/zz_generated.deepcopy.go` and any files under `synthetics-operator/config/crd/bases/`

**Checkpoint**: Type definition is complete; controller and builder can reference the new fields

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Wire the new fields into the WorkflowBuilder and SyntheticTestController. These three changes unblock all user stories.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [x] T003 In `synthetics-operator/internal/controller/workflow_builder.go`, update `buildWorkflowSpec` — inside the existing `if test.Spec.ArtifactStorage != nil && test.Spec.ArtifactStorage.Enabled` block (line ~111), also set `workflowSpec.ArtifactRepositoryRef = &wfv1.ArtifactRepositoryRef{ConfigMap: test.Name + "-artifact-repository", Key: "default"}`
- [x] T004 In `synthetics-operator/internal/controller/synthetictest_controller.go`, add a `reconcileArtifactRepository` helper method — when `ArtifactStorage != nil && Enabled && Bucket != ""`, build the `data.default` YAML string using the two variants from `specs/003-artifact-storage/contracts/artifact-repository-configmap.yaml` (IAM delegation: `useSDKCreds: true`, no credential keys; static creds: `accessKeySecret`/`secretKeySecret` referencing `CredentialsSecret`; keyFormat: `{{workflow.labels["the-grid.io/synthetic-test"]}}/{{workflow.name}}/playwright-report`); create/update a ConfigMap named `<test.Name>-artifact-repository` in the same namespace using `controllerutil.CreateOrUpdate` with `ctrl.SetControllerReference`; call this method from `Reconcile` after the existing CronWorkflow reconciliation
- [x] T005 In `synthetics-operator/internal/controller/synthetictest_controller.go`, update the ServiceAccount creation — change the `r.Create(ctx, serviceAccount)` call to `controllerutil.CreateOrUpdate` so the SA is patched on updates; when `ArtifactStorage != nil && len(ServiceAccountAnnotations) > 0`, merge `ServiceAccountAnnotations` into `serviceAccount.Annotations` before the upsert

**Checkpoint**: Foundation complete — controller creates the artifact-repository ConfigMap, sets artifactRepositoryRef on the CronWorkflow, and annotates the SA for IAM delegation. No user story is blocked.

---

## Phase 3: User Story 1 — Browse Failed Test Artifacts (Priority: P1) 🎯 MVP

**Goal**: After a test run completes, the engineer can follow the `status.artifactURL` on the `SyntheticTestRun` to the uploaded HTML report.

**Independent Test**: Enable artifact storage on the `httbin-synthetic` SyntheticTest with a MinIO backend, trigger a manual Workflow run, and confirm `SyntheticTestRun.status.artifactURL` is non-empty and the artifact exists at that path in the bucket.

- [x] T006 [P] [US1] In `synthetics-operator/internal/controller/workflow_builder_test.go`, add test `TestBuildCronWorkflow_ArtifactStorageEnabled_SetsArtifactRepositoryRef` — given a SyntheticTest with `ArtifactStorage.Enabled = true`, assert `WorkflowSpec.ArtifactRepositoryRef.ConfigMap == "<test-name>-artifact-repository"` and `Key == "default"`; add a second case with `Enabled = false` asserting `ArtifactRepositoryRef` is nil
- [x] T007 [P] [US1] In `synthetics-operator/internal/controller/synthetictest_controller_builder_test.go`, add test `TestReconcile_ArtifactStorage_StaticCreds` — reconcile a SyntheticTest with `Enabled=true`, `Bucket="my-bucket"`, `CredentialsSecret="artifact-creds"`; assert the `<name>-artifact-repository` ConfigMap is created; assert `data["default"]` contains `bucket: my-bucket`, `accessKeySecret.name: artifact-creds`, and the keyFormat substring `{{workflow.name}}`
- [x] T008 [US1] In `synthetics-operator/internal/controller/synthetictest_controller_builder_test.go`, add test `TestReconcile_ArtifactStorage_IAMDelegation` — reconcile a SyntheticTest with `Enabled=true`, `Bucket="my-bucket"`, `ServiceAccountAnnotations={"eks.amazonaws.com/role-arn":"arn:..."}` and no `CredentialsSecret`; assert ConfigMap `data["default"]` contains `useSDKCreds: true` and does NOT contain `accessKeySecret`; assert the ServiceAccount has annotation `eks.amazonaws.com/role-arn` set

**Checkpoint**: US1 complete — WorkflowBuilder and controller are fully tested; a real Argo workflow with artifact storage enabled will upload the playwright-report and the SyntheticTestRunController (already wired) will populate `status.artifactURL`

---

## Phase 4: User Story 2 — Configure Artifact Store at Install Time (Priority: P2)

**Goal**: A platform operator enables artifact storage by setting fields on the `SyntheticTest` CR in `gitops/workloads/playwright-synthetics/synthetics.yaml` and pushing to `main`. No additional steps are required.

**Independent Test**: Apply the updated `synthetics.yaml` to the dev cluster, trigger a test run, and confirm artifacts appear in the configured store within 2 minutes of run completion.

- [x] T009 [US2] In `synthetics-operator/internal/controller/synthetictest_controller.go`, add input validation in `Reconcile` — if `ArtifactStorage.Enabled == true && ArtifactStorage.Bucket == ""`, log the warning, and skip the `reconcileArtifactRepository` call (do not return an error — the workflow should still be reconciled)
- [x] T010 [P] [US2] Update `gitops/workloads/playwright-synthetics/synthetics.yaml` — add an `artifactStorage` block to the `SyntheticTest` spec with `enabled: false` and commented examples for MinIO and AWS IRSA configuration
- [x] T011 [P] [US2] Create `gitops/workloads/playwright-synthetics/artifact-credentials.yaml.example` — a commented example Secret with `metadata.name: artifact-credentials`, `metadata.namespace: the-grid-synthetics`, `data.accessKey: <base64>`, `data.secretKey: <base64>`, and a header comment explaining operators must copy this file, fill in real values, and apply it before enabling artifact storage

**Checkpoint**: US2 complete — the dev environment `SyntheticTest` CR declares artifact storage, and operators have a concrete example of the credentials Secret they must provide

---

## Phase 5: User Story 3 — Audit Historical Test Runs (Priority: P3)

**Goal**: Each test run produces a unique, non-overlapping artifact path; runs from any point in time remain accessible via the stored reference.

**Independent Test**: Trigger two manual Workflow runs for the same SyntheticTest and confirm that each resulting `SyntheticTestRun` has a distinct `status.artifactURL` path (different `workflow.name` segment).

- [x] T012 [P] [US3] In `synthetics-operator/internal/controller/synthetictestrun_controller_test.go`, add unit tests for `artifactURL()` — verify unique URLs for two runs of the same test, and that the URL encodes `workflow.name` as the path segment ensuring per-run uniqueness
- [x] T013 [US3] In `synthetics-operator/internal/controller/synthetictest_controller_builder_test.go`, the static-creds test asserts `data["default"]` contains `{{workflow.name}}` — keyFormat uniqueness is already covered

**Checkpoint**: US3 complete — uniqueness and per-run path isolation are unit-tested; all three user stories are independently deliverable

---

## Phase 6: Polish & Cross-Cutting Concerns

- [x] T014 [P] Run `make test` in `synthetics-operator/` — 21/23 specs pass; 2 pre-existing envtest placeholder failures (not caused by this feature)
- [ ] T015 Follow `specs/003-artifact-storage/quickstart.md` Option A (MinIO in-cluster) end-to-end against the dev cluster — deploy MinIO, create the credentials Secret, push the updated `synthetics.yaml` to `main`, trigger a manual Workflow, confirm `status.artifactURL` is populated and the artifact is accessible in MinIO

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on T001–T002 — BLOCKS all user story phases
- **US1 (Phase 3)**: Depends on Phase 2 completion
- **US2 (Phase 4)**: Depends on Phase 2 completion; can run in parallel with US1
- **US3 (Phase 5)**: Depends on Phase 2 completion; can run in parallel with US1 and US2
- **Polish (Phase 6)**: Depends on all desired user story phases being complete

### User Story Dependencies

- **US1 (P1)**: No dependency on US2 or US3 — independently testable after foundational
- **US2 (P2)**: No dependency on US1 or US3 — the CR update and credentials example are independent
- **US3 (P3)**: No dependency on US1 or US2 — uniqueness test is purely unit-level

### Within Each User Story

- Controller implementation (T004, T005) before controller tests (T007, T008)
- WorkflowBuilder implementation (T003) before WorkflowBuilder test (T006)
- Phase 2 complete before any CR or gitops changes (T010, T011) to avoid applying a CR that references unimplemented controller behavior

### Parallel Opportunities

- T006 and T007 can run in parallel (different test files)
- T010 and T011 can run in parallel (different files)
- T012 and T013 can run in parallel (different test files)
- T014 and T015 can be started together (T015 is cluster work; T014 is local)

---

## Parallel Example: Phase 3 (US1)

```text
# After T003–T005 complete, launch together:
Task T006: workflow_builder_test.go — ArtifactRepositoryRef test cases
Task T007: synthetictest_controller_builder_test.go — static creds ConfigMap test
# T008 depends on T007 (same file), so run after T007
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: T001–T002 (type expansion + code generation)
2. Complete Phase 2: T003–T005 (WorkflowBuilder + controller wiring)
3. Complete Phase 3: T006–T008 (US1 tests)
4. **STOP and VALIDATE**: Trigger a test run in the dev cluster and confirm `status.artifactURL` is populated
5. Deploy to dev — artifact upload is live

### Incremental Delivery

1. Phase 1 + Phase 2 → operator can upload artifacts (no validation yet)
2. Phase 3 (US1) → browsable artifacts, unit-tested, dev-cluster validated
3. Phase 4 (US2) → dev environment wired; operators have install example
4. Phase 5 (US3) → uniqueness proven by test; historical access confirmed
5. Phase 6 → full test suite green; quickstart validated end-to-end

### Notes

- `SyntheticTestRunController.artifactURL()` requires **no changes** — it already handles S3 key extraction (line 110 of `synthetictestrun_controller.go`)
- The playwright runner image requires **no changes** — Argo's artifact agent handles the upload outside the test container
- `zz_generated.deepcopy.go` is generated code; commit it but do not edit it manually
- The example `artifact-credentials.yaml.example` must never be committed with real credentials filled in
