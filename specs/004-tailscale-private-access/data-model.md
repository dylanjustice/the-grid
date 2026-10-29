# Data Model: Tailscale Private Access

**Branch**: `004-tailscale-private-access` | **Date**: 2026-10-28

This feature has no persistent application data model. Configuration artifacts are described below.

---

## Terraform Variable Schema

### `modules/k3s/variables.tf` additions

| Variable | Type | Default | Description |
|---|---|---|---|
| `tailscale_enabled` | `bool` | `false` | When true, userdata installs Tailscale and configures subnet router + serve |
| `tailscale_ssm_param_path` | `string` | `"/the-grid/tailscale/auth-key"` | SSM Parameter Store path for the reusable auth key |
| `tailscale_advertise_routes` | `string` | `""` | CIDR to advertise; populated from `var.vpc_cidr` in the calling module |

### `live/flynn/main.tf` additions (k3s module call)

```hcl
tailscale_enabled          = var.tailscale_enabled
tailscale_ssm_param_path   = "/the-grid/tailscale/auth-key"
tailscale_advertise_routes = var.vpc_cidr
```

### `live/flynn/variables.tf` addition

| Variable | Type | Default | Description |
|---|---|---|---|
| `tailscale_enabled` | `bool` | `false` | Propagated to the k3s module |

---

## IAM Policy Addition

### Resource: `aws_iam_role_policy.k3s_tailscale_ssm`

Attached to `aws_iam_role.k3s` in `modules/k3s/main.tf`.

```
Effect: Allow
Actions:
  - ssm:GetParameter
Resources:
  - arn:aws:ssm:<region>:<account>:parameter/the-grid/tailscale/auth-key
```

---

## Userdata Configuration Phases

### Phase A — Tailscale install and join (before k3s)

```
Input:   SSM parameter at tailscale_ssm_param_path
Process: Install tailscaled → systemctl enable/start → tailscale up --auth-key --advertise-routes
Output:  Tailscale MagicDNS hostname captured in TS_HOSTNAME shell variable
Failure: Exit 1 with log message if SSM parameter missing or tailscale up fails
```

### Phase B — k3s install (after Tailscale, using TS_HOSTNAME)

```
Input:   TS_HOSTNAME from Phase A; existing INSTALL_K3S_EXEC args
Process: Install k3s with --tls-san=$TS_HOSTNAME appended to INSTALL_K3S_EXEC
Output:  k3s API server cert includes Tailscale hostname as a SAN
```

### Phase C — Tailscale Serve setup systemd unit

```
Unit:    tailscale-serve-setup.service (Type=oneshot)
After:   tailscaled.service k3s.service
Process: Discover ClusterIPs via k3s kubectl; run tailscale serve for each service
State:   tailscaled persists serve config across reboots automatically
```

---

## Tailscale Serve Configuration State

Managed by `tailscaled` daemon; configured via `tailscale serve` CLI in the systemd oneshot unit.

| Service | Port | Backend resolution |
|---|---|---|
| ArgoCD | 443 | `k3s kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.clusterIP}'` → `https://<ip>:443` |
| Argo Workflows | 2746 | `k3s kubectl get svc argo-workflows-server -n the-grid-workflows -o jsonpath='{.spec.clusterIP}'` → `http://<ip>:2746` |
| Prometheus | 9090 | `k3s kubectl get svc prometheus-server -n the-grid-monitoring -o jsonpath='{.spec.clusterIP}'` → `http://<ip>:80` |
| httpbin | 8080 | `k3s kubectl get svc httpbin -n the-grid-synthetics -o jsonpath='{.spec.clusterIP}'` → `http://<ip>:80` |

ArgoCD backend uses `https+insecure` to skip the internal self-signed cert; Argo Workflows, Prometheus, and httpbin backends are plain HTTP.

---

## kubeconfig Entry

### Current (requires tunnel-start)

```yaml
clusters:
  - cluster:
      server: https://localhost:6443
```

### New (Tailscale-routed, no tunnel needed)

```yaml
clusters:
  - cluster:
      server: https://<tailscale-hostname>:6443   # e.g., ec2-node.tail1234.ts.net
```

`get-kubeconfig.sh` discovers `<tailscale-hostname>` via SSM Run Command: `tailscale status --json | jq -r '.Self.DNSName' | sed 's/\.$//'`. If discovery fails (Tailscale not up), falls back to `localhost:6443`.

---

## SSM Parameter Store Entry (pre-provisioned by operator)

| Field | Value |
|---|---|
| Name | `/the-grid/tailscale/auth-key` |
| Type | `SecureString` |
| KMS Key | AWS-managed (`aws/ssm`) |
| Value | Tailscale reusable auth key (no expiry) |
| Who creates it | Operator, manually via AWS Console or CLI, before `make live-apply` |
