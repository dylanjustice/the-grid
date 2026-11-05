# Data Model: MVP Helm Chart

## Helm Values Schema

The public interface to the chart. All fields are configurable via `--set` or a user-supplied `values.yaml`.

### Top-level structure

```yaml
operator:
  image: <string>         # operator container image (required at release; no default in repo)
  resources:
    requests:
      cpu: <string>       # default: "10m"
      memory: <string>    # default: "64Mi"
    limits:
      cpu: <string>       # default: "500m"
      memory: <string>    # default: "128Mi"

runner:
  image: <string>         # default runner image for SyntheticTest pods (required at release)
  resources:
    requests:
      cpu: <string>       # default: "250m"
      memory: <string>    # default: "512Mi"

workloadNamespace: <string>   # namespace for runner pods + Pushgateway; default: "the-grid-synthetics"

argo-workflows:
  enabled: <bool>         # default: true — deploy bundled Argo Workflows
  # all other argo-workflows chart values pass through

pushgateway:
  enabled: <bool>         # default: true — deploy bundled Pushgateway
  externalUrl: <string>   # used when enabled=false; operator injects this URL into CronWorkflows
  # all other pushgateway chart values pass through

ui:
  enabled: <bool>         # default: false for MVP — stub only, deploys nothing
```

### Computed values (not user-settable)

| Value | Derivation | Used by |
|---|---|---|
| Pushgateway service URL | `http://{{ .Release.Name }}-prometheus-pushgateway.{{ .Values.workloadNamespace }}.svc:9091` when `pushgateway.enabled=true`; `{{ .Values.pushgateway.externalUrl }}` otherwise | operator Deployment `--pushgateway-url` flag |
| Operator full name | `{{ include "the-grid-synthetics.fullname" . }}` | All RBAC and Deployment resource names |
| Operator image | `{{ .Values.operator.image }}` | Deployment `.spec.template.spec.containers[0].image` |
| Runner image | `{{ .Values.runner.image }}` | Deployment `--runner-image` flag |

---

## Operator Startup Configuration

The operator binary reads these flags at startup. The chart injects them via the Deployment's `args:` list.

| Flag | Type | Source in Chart | Behaviour when empty |
|---|---|---|---|
| `--runner-image` | string | `{{ .Values.runner.image }}` | Log warning; operator falls back to empty string — CR must specify `container.image` |
| `--pushgateway-url` | string | Computed Pushgateway service URL (see above) | No `PUSHGATEWAY_URL` injected; push failures logged, non-fatal (Constitution V) |
| `--leader-elect` | bool | hardcoded `true` in chart | N/A |
| `--health-probe-bind-address` | string | hardcoded `:8081` | N/A |

---

## Kubernetes Resources Created by the Chart

### In the installation namespace (`{{ .Release.Namespace }}`)

| Resource | Kind | Name |
|---|---|---|
| Operator process | `Deployment` | `{{ fullname }}` |
| Operator identity | `ServiceAccount` | `{{ fullname }}` |
| Leader election permissions | `Role` | `{{ fullname }}-leader-election` |
| Leader election binding | `RoleBinding` | `{{ fullname }}-leader-election` |

### Cluster-scoped

| Resource | Kind | Name |
|---|---|---|
| Operator permissions | `ClusterRole` | `{{ fullname }}` |
| Operator permissions binding | `ClusterRoleBinding` | `{{ fullname }}` |
| Test declaration API | `CustomResourceDefinition` | `synthetictests.thegrid.io` |
| Test run record API | `CustomResourceDefinition` | `synthetictestruns.thegrid.io` |

### In the workload namespace (`{{ .Values.workloadNamespace }}`)

| Resource | Kind | Name | Owner |
|---|---|---|---|
| Workload namespace | `Namespace` | `{{ .Values.workloadNamespace }}` | chart (keep on uninstall) |
| Pushgateway (if enabled) | via dependency chart | `{{ .Release.Name }}-prometheus-pushgateway` | Pushgateway subchart |
| Argo Workflows (if enabled) | via dependency chart | Argo subchart default | Argo subchart |

### Per `SyntheticTest` CR (created by the operator at reconciliation time, not by the chart)

| Resource | Kind | Name |
|---|---|---|
| Test source | `ConfigMap` | `{{ cr.Name }}-config` |
| Runner identity | `ServiceAccount` | `{{ cr.Name }}` (or `spec.serviceAccountName`) |
| Runner permissions | `Role` | `{{ cr.Name }}` |
| Runner permissions binding | `RoleBinding` | `{{ cr.Name }}` |
| Scheduled test | `CronWorkflow` | `{{ cr.Name }}` |

---

## `DefaultWorkflowBuilder` Struct (updated)

```go
type DefaultWorkflowBuilder struct {
    RunnerImage    string  // from --runner-image flag; empty = no default, CR must specify
    PushgatewayURL string  // from --pushgateway-url flag; empty = no injection
}
```

`buildWorkflowSpec` changes:
1. `if container.Image == "" && b.RunnerImage != "" { container.Image = b.RunnerImage }` (replaces `defaultImage` constant)
2. If `b.PushgatewayURL != ""`, prepend `{Name: "PUSHGATEWAY_URL", Value: b.PushgatewayURL}` to `container.Env` (only if not already set by the CR, so CR-level overrides are respected)
