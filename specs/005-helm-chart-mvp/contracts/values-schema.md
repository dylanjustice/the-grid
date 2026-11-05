# Contract: Helm Values Interface

This is the public interface of the chart — the complete set of values a user may set in their `values.yaml` or via `--set` flags. All other internals are implementation details.

## Stability guarantees

- Fields marked **stable** will not be renamed or removed in patch or minor releases.
- Fields marked **provisional** may change before v1.0.
- Unlisted fields have no stability guarantee.

---

## `operator` (stable)

Controls the operator `Deployment`.

| Field | Type | Default | Description |
|---|---|---|---|
| `operator.image` | string | *(set at release)* | Operator container image. Must be set before the chart is usable; the placeholder in `values.yaml` is replaced by CI during release. |
| `operator.resources.requests.cpu` | string | `10m` | CPU request for the operator pod. |
| `operator.resources.requests.memory` | string | `64Mi` | Memory request for the operator pod. |
| `operator.resources.limits.cpu` | string | `500m` | CPU limit for the operator pod. |
| `operator.resources.limits.memory` | string | `128Mi` | Memory limit for the operator pod. |

---

## `runner` (stable)

Configures the default container image for Synthetic Test runner pods.

| Field | Type | Default | Description |
|---|---|---|---|
| `runner.image` | string | *(set at release)* | Default runner image injected into every `CronWorkflow` when the `SyntheticTest` CR does not specify `spec.container.image`. Must be set at release time. |
| `runner.resources.requests.cpu` | string | `250m` | Passed to the operator as a default; individual CRs may override. |
| `runner.resources.requests.memory` | string | `512Mi` | Passed to the operator as a default; individual CRs may override. |

---

## `workloadNamespace` (stable)

| Field | Type | Default | Description |
|---|---|---|---|
| `workloadNamespace` | string | `the-grid-synthetics` | Namespace for runner pods, Pushgateway, and Argo Workflows. Created by the chart if it does not exist. Retained on `helm uninstall` (`helm.sh/resource-policy: keep`). |

---

## `argo-workflows` (stable)

Pass-through to the Argo Workflows subchart. Full values reference: [argo-helm](https://github.com/argoproj/argo-helm/tree/main/charts/argo-workflows).

| Field | Type | Default | Description |
|---|---|---|---|
| `argo-workflows.enabled` | bool | `true` | Deploy the bundled Argo Workflows. Set to `false` if Argo is already installed in the cluster. |

---

## `pushgateway` (stable)

Pass-through to the Prometheus Pushgateway subchart, plus one Grid-specific field.

| Field | Type | Default | Description |
|---|---|---|---|
| `pushgateway.enabled` | bool | `true` | Deploy the bundled Pushgateway. |
| `pushgateway.externalUrl` | string | `""` | When `enabled=false`, this URL is injected as `PUSHGATEWAY_URL` into every runner pod. Ignored when `enabled=true`. |

---

## `ui` (provisional)

| Field | Type | Default | Description |
|---|---|---|---|
| `ui.enabled` | bool | `false` | Reserved for the Run History UI milestone. Has no effect in the MVP chart — no resources are deployed. |

---

## Minimum required `values.yaml` override for a working install

```yaml
operator:
  image: <your-registry>/the-grid/operator:<version>

runner:
  image: <your-registry>/the-grid/runner:<version>
```

All other values have working defaults.

---

## Example: bring-your-own Argo + external Pushgateway

```yaml
operator:
  image: <registry>/the-grid/operator:v0.2.0

runner:
  image: <registry>/the-grid/runner:v0.2.0

argo-workflows:
  enabled: false

pushgateway:
  enabled: false
  externalUrl: http://my-pushgateway.monitoring.svc:9091
```
