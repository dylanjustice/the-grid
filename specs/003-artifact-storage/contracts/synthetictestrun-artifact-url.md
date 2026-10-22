# Contract: SyntheticTestRun.Status.ArtifactURL

**Field path**: `status.artifactURL` on `SyntheticTestRun` (already declared in `synthetictestrun_types.go`)

## Format

```
s3://<bucket>/<test-name>/<workflow-name>/playwright-report
```

### Examples

| Backend | Example value |
|---------|---------------|
| AWS S3 | `s3://the-grid-artifacts/httbin-synthetic/httbin-synthetic-abc12345/playwright-report` |
| MinIO | `s3://the-grid-artifacts/httbin-synthetic/httbin-synthetic-abc12345/playwright-report` |
| GCS S3-interop | `s3://the-grid-artifacts/httbin-synthetic/httbin-synthetic-abc12345/playwright-report` |

The scheme is always `s3://` regardless of backend because Argo's `artifactURL()` path reads the `S3` artifact field (GCS and MinIO are configured via the S3-compatible endpoint). The bucket-relative path is always `<test-name>/<workflow-name>/playwright-report`.

## Population

The `SyntheticTestRunController.artifactURL()` function (line 110 of `synthetictestrun_controller.go`) iterates `workflow.Status.Nodes`, finds the artifact named `playwright-report`, and constructs `s3://<bucket>/<key>` from `artifact.S3.Bucket` and `artifact.S3.Key`.

No changes to `synthetictestrun_controller.go` are required for this feature — the extraction logic already handles the correct fields.

## Lifecycle

| Event | ArtifactURL value |
|-------|-----------------|
| Workflow running | `""` (empty) |
| Workflow completed, artifact storage disabled | `""` (empty) |
| Workflow completed, upload succeeded | `s3://...` (non-empty) |
| Workflow completed, upload failed (best-effort) | `""` (empty) — workflow still Succeeded/Failed per test result |

## Consumer guidance

The field is a stable reference to the artifact package root. To browse the HTML report, derive the `index.html` URL from the artifact URL by replacing the `s3://` scheme and bucket prefix with the appropriate object store console or presigned URL for the configured backend.
