# Research: Artifact Storage

**Date**: 2026-10-20

## Decision 1: Argo Native Artifact Storage vs Custom Upload Script

**Decision**: Use Argo Workflows' built-in artifact storage mechanism — declare `outputs.artifacts` on the workflow template and reference an `artifact-repositories` ConfigMap via `artifactRepositoryRef`.

**Rationale**: The operator already emits the output artifact stub in `workflow_builder.go` (lines 111–119). The `SyntheticTestRunController.artifactURL()` already reads `workflow.Status.Nodes[*].Outputs.Artifacts[name="playwright-report"].S3.Key` to populate `status.ArtifactURL`. Argo's artifact storage handles the upload as a built-in post-step — it runs after the main container exits, a failure does not change the workflow phase (satisfies Constitution V), and it supports S3, GCS, and any S3-compatible endpoint with a single config format.

A custom Node.js upload script running in the test container was evaluated but rejected because it mixes concerns (test runner + upload logic), requires the test container to hold S3 SDK credentials, and cannot be toggled via the CR without changing the container command.

**Alternatives considered**:
- Custom upload script in the playwright container: rejected — entangles upload config with test-runner image lifecycle
- Argo exit handler in a separate pod: rejected — the exit handler pod cannot access the main pod's filesystem without a PVC; would require adding persistent storage infrastructure

---

## Decision 2: Per-Workflow `artifactRepositoryRef` vs Global Argo Controller Config

**Decision**: Use `artifactRepositoryRef` on each generated workflow spec, pointing to an `artifact-repositories` ConfigMap in the `the-grid-synthetics` namespace.

**Rationale**: The global Argo controller config (`workflow-controller-configmap` in `the-grid-workflows` namespace) is owned by the Argo Workflows Helm chart. Modifying it would create a cross-chart dependency and violate Constitution I (each GitOps application manages its own resources). The `artifactRepositoryRef` field lets each workflow reference a ConfigMap in its own namespace, keeping artifact storage config co-located with the synthetic tests.

**Alternatives considered**:
- Modify `workflow-controller-configmap`: rejected — cross-application config coupling; ArgoCD would fight over ownership

---

## Decision 3: Credential Mode Implementation

**Decision**: Support two modes via `ArtifactStorageSpec` fields:
1. **Static credentials** (`credentialsSecret: "<secret-name>"`) — the ConfigMap's `accessKeySecret`/`secretKeySecret` reference a named Secret in the same namespace
2. **IAM delegation** (`serviceAccountAnnotations: {"eks.amazonaws.com/role-arn": "..."}`) — the operator merges these annotations onto the workflow's ServiceAccount; the ConfigMap uses `useSDKCreds: true`; the AWS SDK in the Argo artifact store agent picks up credentials via IRSA token projection

Both modes are mutually exclusive. If both are set, IAM delegation takes precedence (static credentials are ignored). This avoids accidentally leaking keys when upgrading from static to IRSA.

**Rationale**: Static credentials work for every backend including MinIO. IAM delegation is AWS best practice for cloud deployments and avoids long-lived keys. Supporting both maximises operator choice while keeping the CR surface minimal.

**Alternatives considered**:
- Static credentials only: rejected — long-lived keys in Secrets are a security liability for cloud deployments (user explicitly chose Option B in spec phase)
- IAM delegation only: rejected — breaks MinIO and GCS S3-interop which do not support OIDC-based IAM

---

## Decision 4: `ArtifactStorageSpec` Expansion

**Decision**: Expand `ArtifactStorageSpec` in `synthetictest_types.go` with five new fields: `Bucket`, `Endpoint`, `Region`, `CredentialsSecret`, `ServiceAccountAnnotations`. The `Enabled` bool remains the feature gate; all other fields are optional strings/maps.

**Rationale**: All storage config lives in the CR rather than splitting between the CR and a separate platform-level ConfigMap. This means operators can run multiple `SyntheticTest` CRs pointing to different buckets (e.g., prod bucket vs staging bucket) without changing cluster-level config. The operator derives the `artifact-repositories` ConfigMap content from the CR fields.

The key format within the bucket is fixed to `{{workflow.labels["the-grid.io/synthetic-test"]}}/{{workflow.name}}/playwright-report` — matching the spec path `<test-name>/<workflow-id>/playwright-report`. This label is already applied to every generated workflow by the `WorkflowBuilder`.

**Alternatives considered**:
- Platform-level ConfigMap with no per-test overrides: rejected — prevents multi-bucket deployments; less flexible for operators
- Separate `ArtifactRepository` CRD: rejected — adds a second CRD for a concern that is a simple extension of the existing `SyntheticTest` spec; over-engineered for current scope

---

## Decision 5: ConfigMap Ownership

**Decision**: The `artifact-repositories` ConfigMap is created and owned by the `SyntheticTestController` (set via `ctrl.SetControllerReference`), not committed as a static GitOps manifest. The controller derives the ConfigMap content from the `ArtifactStorageSpec` on the triggering `SyntheticTest` CR.

**Rationale**: The ConfigMap content (bucket, endpoint, credential references) varies per `SyntheticTest`. If multiple tests exist with different storage configs, each gets its own ConfigMap keyed by `<test-name>-artifact-repository`. The `artifactRepositoryRef` on the workflow points to the correct ConfigMap. The static GitOps manifest in `gitops/workloads/playwright-synthetics/` only needs to declare the `SyntheticTest` CR with the desired `artifactStorage` fields; all derived resources follow from the operator.

**Note on the existing `artifact-repository.yaml`**: The contract artifact `contracts/artifact-repository-configmap.yaml` documents the schema the controller generates. It should NOT be committed as a static manifest — it is operator-managed.
