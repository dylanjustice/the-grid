# Implementation Plan: Tailscale Private Access

**Branch**: `004-tailscale-private-access` | **Date**: 2026-10-28 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/004-tailscale-private-access/spec.md`

## Summary

Install Tailscale as an EC2 system service via Terraform userdata. The EC2 instance acts as a Tailscale subnet router, advertising the VPC CIDR (`10.0.0.0/20`) to the Tailnet. Tailscale Serve proxies HTTPS traffic with auto-managed Tailscale certs to the four platform services (ArgoCD, Argo Workflows, Prometheus, httpbin) by routing directly to their ClusterIPs — the EC2 instance IS the k3s node, so all ClusterIPs are locally reachable. The kubeconfig server address changes from `localhost:6443` to the node's Tailscale hostname, which is added to k3s TLS SANs at install time. The auth key is stored in AWS SSM Parameter Store as a SecureString.

## Technical Context

**Infrastructure Runtime**: Amazon Linux 2023 (ARM64, t4g.medium)

**Primary Dependencies**:
- Tailscale (system service, managed by Terraform userdata)
- k3s (existing; TLS SAN extended to include Tailscale hostname)
- AWS SSM Parameter Store (auth key storage)
- Terraform `modules/k3s` (userdata, IAM, variables)

**Storage**: SSM Parameter Store SecureString at `/the-grid/tailscale/auth-key`

**Testing**: Manual end-to-end per `quickstart.md`

**Target Platform**: EC2 private subnet, ARM64

**Project Type**: Infrastructure / developer tooling

**Performance Goals**: UI load under 10 seconds after VPN connect (SC-001); VPN access restored within 5 minutes of EC2 provisioning (Story 3)

**Constraints**: Auth key MUST NOT appear in git or Terraform state in plaintext. Tailscale subnet router requires IP forwarding enabled at kernel level.

**Scale/Scope**: Single node, 3 Tailnet members

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. GitOps is Source of Truth | **COMPLIANT** | Tailscale is EC2 infrastructure managed by Terraform, same as the SSM VPC endpoints. No ArgoCD-managed resources are affected. |
| II. Helm Chart is Product Boundary | **COMPLIANT (exempt)** | The constitution explicitly classifies non-Helm capabilities as "dev environment infrastructure scaffolding." Tailscale is dev access infrastructure, not a product feature shipped to users. |
| III. Operator Owns Test Lifecycle | **NOT APPLICABLE** | No CRDs or workflows modified. |
| IV. Zero-Boilerplate Instrumentation | **NOT APPLICABLE** | No test instrumentation involved. |
| V. Observability is Non-Blocking | **NOT APPLICABLE** | No test runner changes. |

**Gate result: PASS** — no violations. Proceed to Phase 1.

## Project Structure

### Documentation (this feature)

```text
specs/004-tailscale-private-access/
├── plan.md              ← this file
├── research.md          ← Phase 0 findings
├── data-model.md        ← Phase 1 configuration schema
├── quickstart.md        ← Phase 1 validation guide
├── contracts/
│   └── makefile-interface.md   ← updated make targets
└── tasks.md             ← Phase 2 (/speckit-tasks, not created here)
```

### Source Code (repository root)

```text
modules/k3s/
├── userdata.sh          ← Tailscale install, serve config, k3s TLS SAN
├── variables.tf         ← tailscale_enabled, tailscale_ssm_param_path
├── main.tf              ← IAM policy for SSM GetParameter
└── outputs.tf           ← tailscale_hostname output

live/flynn/
└── main.tf              ← wire tailscale vars into k3s module

scripts/
└── get-kubeconfig.sh    ← replace hardcoded localhost:6443 with Tailscale hostname

Makefile                 ← update tunnel-start/argo-ui/etc help text to "(fallback)"
```

**Structure Decision**: All changes are within the existing Terraform module and scripts tree. No new top-level directories. GitOps workloads are unchanged — Tailscale Serve proxies directly to ClusterIPs, avoiding any need for NodePort changes.
