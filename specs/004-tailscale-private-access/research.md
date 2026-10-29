# Research: Tailscale Private Access

**Branch**: `004-tailscale-private-access` | **Date**: 2026-10-28

## Decision 1: Tailscale Serve vs Traefik Ingress Subdomains

**Decision**: Use Tailscale Serve on the EC2 instance rather than Traefik ingress with subdomain routing.

**Rationale**: Tailscale machine certs (obtained via `tailscale cert`) are issued for `<node>.tailXXXX.ts.net` only — not wildcard `*.<node>.tailXXXX.ts.net`. Subdomain ingress rules would therefore produce TLS certificate errors on every browser visit. Tailscale Serve uses the machine cert natively and proxies each service on a distinct port: `https://<node>.tailXXXX.ts.net:<port>/`. Since the EC2 instance IS the k3s node, it has direct network access to all ClusterIPs without requiring NodePort changes.

**Alternatives considered**:
- Traefik subdomains + self-signed wildcard cert — rejected: browser cert warnings on every visit, requires users to trust a custom CA.
- Let's Encrypt for `*.tailXXXX.ts.net` — rejected: no HTTP-01 path (EC2 is private), no DNS-01 path (Tailscale does not expose DNS provider API).
- NodePort + Tailscale Serve — workable but unnecessary since ClusterIPs are locally routable on the k3s node.

## Decision 2: k3s TLS SAN for Tailscale Hostname

**Decision**: Run Tailscale first in userdata, capture the assigned MagicDNS hostname, then install k3s with `--tls-san=<tailscale-hostname>`. This makes the Tailscale hostname valid for the k3s API TLS certificate so `kubectl` clients connect without `--insecure-skip-tls-verify`.

**Rationale**: k3s generates a self-signed API server cert at install time. SANs default to `localhost`, `127.0.0.1`, and the node's private IP. The Tailscale IP (`100.x.x.x`) and hostname are not included unless explicitly passed. By installing Tailscale before k3s and extracting the hostname, the SAN can be embedded at install time without a cert rotation step later.

**Implementation detail**:
```bash
# In userdata.sh — after tailscaled is up and tailscale up has run:
TS_HOSTNAME=$(tailscale status --json | jq -r '.Self.DNSName' | sed 's/\.$//')
# Then install k3s with the SAN:
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--tls-san=$TS_HOSTNAME ..." sh -
```

**Alternatives considered**:
- Use EC2 private IP (already in k3s SAN by default) — viable but less ergonomic; IP changes on stop/start; hostname is more stable.
- Post-install cert rotation via `k3s certificate rotate` — requires a cluster restart; messier userdata flow.
- `--insecure-skip-tls-verify` in kubeconfig — rejected: unnecessary risk for a persistent kubeconfig.

## Decision 3: Auth Key Storage and Retrieval

**Decision**: Store the Tailscale auth key in AWS SSM Parameter Store as a `SecureString` at path `/the-grid/tailscale/auth-key`. Fetch it in userdata with `aws ssm get-parameter --with-decryption`.

**Rationale**: SSM Parameter Store is already in use (SSM VPC endpoints are deployed). The EC2 instance role already has SSM session permissions; adding `ssm:GetParameter` on a single path is a minimal IAM addition. SecureString encrypts the value at rest using the AWS-managed KMS key. The key never appears in userdata source, Terraform state, or git.

**Implementation detail**: The userdata script must handle the case where the SSM parameter does not exist — it should `exit 1` with a clear log message so the instance fails loudly (per Story 3 acceptance scenario 3) rather than silently starting without Tailscale.

**Alternatives considered**:
- Terraform variable passed at apply time — rejected: appears in Terraform state in plaintext.
- AWS Secrets Manager — viable but higher cost and more setup for a single string.
- Instance metadata / user-data variable — rejected: appears in Terraform configs and git.

## Decision 4: Subnet CIDR Advertisement and Route Approval

**Decision**: Advertise only the VPC CIDR (`10.0.0.0/20`) via `tailscale up --advertise-routes=10.0.0.0/20`. Route approval is done once manually in the Tailscale admin console after first deployment.

**Rationale**: The VPC CIDR gives Tailscale clients reach to the EC2 node's private IP. Services are accessed via Tailscale Serve (on the Tailscale IP), not via direct ClusterIP routing, so advertising k3s internal CIDRs (10.42.0.0/16, 10.43.0.0/16) is unnecessary. Manual route approval is a one-time step; auto-approval via ACL tags would require additional Tailscale admin console configuration outside the repo.

**VPC CIDR source**: `live/flynn/variables.tf` → `var.vpc_cidr` defaults to `10.0.0.0/20`. The Terraform module should pass this to userdata so the advertised route stays in sync.

## Decision 5: Tailscale Serve Port Assignments

**Decision**: Each service gets a fixed HTTPS port via `tailscale serve`. Ports mirror the service's native port where possible for familiarity.

| Service | Tailscale Serve port | Backend (ClusterIP:port) |
|---|---|---|
| ArgoCD | 443 (default HTTPS) | `argocd-server.argocd.svc.cluster.local:443` |
| Argo Workflows | 2746 | `argo-workflows-server.the-grid-workflows.svc.cluster.local:2746` |
| Prometheus | 9090 | `prometheus-server.the-grid-monitoring.svc.cluster.local:80` |
| httpbin | 8080 | `httpbin.the-grid-synthetics.svc.cluster.local:80` |

The EC2 instance resolves `*.svc.cluster.local` names via the k3s DNS server (CoreDNS). CoreDNS ClusterIP is `10.43.0.10` by default in k3s. The EC2 instance's `/etc/resolv.conf` does not point to CoreDNS — so DNS names cannot be used directly. **ClusterIPs must be discovered at runtime** via `k3s kubectl get svc` and passed to `tailscale serve`.

**Implementation**: A systemd oneshot unit (`tailscale-serve-setup.service`) runs after both `tailscaled.service` and `k3s.service` are active. It discovers ClusterIPs, configures serve, and exits. On future reboots, `tailscaled` restores serve config automatically from its state file.

**Alternatives considered**:
- NodePort services in GitOps — workable but requires GitOps changes; ClusterIP approach keeps the feature self-contained in the EC2 module.
- Hardcoded ClusterIPs — rejected: ClusterIPs can change if services are recreated.

## Decision 6: get-kubeconfig.sh Update

**Decision**: After Tailscale is set up, `get-kubeconfig.sh` fetches the Tailscale hostname via SSM Run Command (`tailscale status --json | jq -r '.Self.DNSName'`) and writes `CLUSTER_SERVER="https://<tailscale-hostname>:6443"`. The tunnel-start prerequisite is eliminated.

**Rationale**: The Tailscale hostname is stable (does not change on reboot or instance replacement within the same Tailnet account), and it is included in the k3s API TLS SAN. Clients only need Tailscale connected, not an SSM session.

**Fallback**: If `tailscale status` fails (Tailscale not yet up), the script falls back to the original `localhost:6443` path requiring `make tunnel-start`, ensuring backward compatibility per FR-006.
