# Feature Specification: Tailscale Private Access

**Feature Branch**: `004-tailscale-private-access`

**Created**: 2026-10-27

**Status**: Draft

**Input**: User description: "I'm considering integrating tailscale for exposing my vpc privately. This would help by eliminating the SSM tunneling, argo-ui, httpbin-ui, argocd etc commands. I could expose the services with a private hosted zone that resolves on a vpn"

## Clarifications

### Session 2026-10-27

- Q: What hostname scheme for reaching services, and is enabling Traefik ingress in scope? → A: MagicDNS auto-hostname + Traefik ingress rules — clean subdomain per service, no custom DNS zone (Option A)
- Q: What CIDRs should the subnet router advertise to the Tailnet? → A: VPC subnet CIDR only — node IP reachable, services via Traefik ingress (Option A)
- Q: Should the Tailscale auth key be reusable with no expiry, or ephemeral? → A: Reusable, non-expiring — instance rejoins Tailnet on any restart automatically (Option A)
- Q: Should browser connections to platform UIs be HTTPS with a valid cert, HTTP, or self-signed? → A: Tailscale HTTPS certs for `*.ts.net` — valid browser-trusted certs, no CA setup (Option A)
- Q: How should the platform surface Tailscale connectivity health? → A: No explicit check — connectivity is self-evident (try kubectl or open a browser)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Access Platform UIs Without Port-Forward Commands (Priority: P1)

As the platform operator, I want to open ArgoCD, Argo Workflows, Prometheus, and httpbin in a browser by visiting a stable hostname — without running any `make` tunneling commands first.

**Why this priority**: Every `make argo-ui` / `make tunnel-start` invocation is a recurring interruption that blocks other work and requires the terminal session to stay alive. Eliminating these commands is the primary motivator for the feature.

**Independent Test**: With VPN connected and no port-forwarding sessions open, navigate to `argocd.<node>.tail1234.ts.net` in a browser and confirm the ArgoCD login page loads.

**Acceptance Scenarios**:

1. **Given** Tailscale VPN is connected on the developer machine, **When** a browser navigates to the ArgoCD hostname, **Then** the ArgoCD UI loads without any additional commands.
2. **Given** Tailscale VPN is connected, **When** a browser navigates to the Argo Workflows hostname, **Then** the Argo Workflows UI loads.
3. **Given** Tailscale VPN is connected, **When** a browser navigates to the Prometheus hostname, **Then** the Prometheus UI loads.
4. **Given** Tailscale VPN is **not** connected, **When** a browser navigates to any internal hostname, **Then** the page fails to load (no public exposure).

---

### User Story 2 - Access Kubernetes API Without SSM Tunnel (Priority: P2)

As the platform operator, I want to run `kubectl` commands against the cluster without first running `make tunnel-start` and `make get-kubeconfig`.

**Why this priority**: The SSM port-forward to the k3s API (:6443) blocks a terminal session and must be restarted after every disconnect. Stable VPN-routed access to the API server eliminates this entirely.

**Independent Test**: With VPN connected and no SSM sessions open, run `kubectl get nodes` and confirm it returns the cluster node list.

**Acceptance Scenarios**:

1. **Given** Tailscale VPN is connected, **When** `kubectl get pods -A` is run, **Then** it returns cluster state without any SSM tunnel prerequisite.
2. **Given** Tailscale VPN is connected, **When** `make argo-sync` or any `make` target that calls `kubectl` is run, **Then** it succeeds without a prior `make tunnel-start`.

---

### User Story 3 - Reproduce VPN Access from a Fresh EC2 Instance (Priority: P3)

As the platform operator, I want a freshly provisioned EC2 instance to automatically join the Tailnet and restore VPN access without any manual post-creation steps beyond pre-populating the auth key in AWS SSM.

**Why this priority**: If the EC2 instance is recreated (e.g., after `make k3s-destroy` + `make terraform-apply`), VPN access must restore itself automatically. Manual SSH login to configure Tailscale breaks the Terraform-managed infrastructure model.

**Independent Test**: Destroy and recreate the EC2 instance via Terraform; confirm VPN access is restored within 5 minutes of the instance reaching running state, with no SSH or manual commands issued.

**Acceptance Scenarios**:

1. **Given** the Tailscale auth key is stored in AWS SSM Parameter Store, **When** Terraform provisions a new EC2 instance, **Then** userdata retrieves the key, installs Tailscale, and the instance joins the Tailnet automatically.
2. **Given** the EC2 instance reboots, **When** the instance reaches running state, **Then** Tailscale reconnects to the Tailnet without manual intervention.
3. **Given** the Tailscale auth key has not been pre-populated in SSM, **When** Terraform provisions the instance, **Then** the userdata script fails loudly with a clear error message (rather than silently joining with no VPN access).

---

### Edge Cases

- Auth key expiry is not a concern — a reusable non-expiring key is used; the instance reconnects to the Tailnet on any restart.
- What happens if the Tailscale systemd service on EC2 crashes — systemd restarts it automatically; brief disconnection is expected.
- What if the EC2 instance's private IP changes (e.g., stop/start cycle)? Are advertised routes refreshed?
- Can two concurrent developer machines connect to the Tailnet simultaneously without conflict?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The cluster MUST advertise its internal VPC subnet routes to the Tailnet so all services are reachable by their cluster-internal or node-level IP.
- **FR-002**: Internal services (ArgoCD, Argo Workflows, Prometheus, httpbin) MUST be reachable at stable HTTPS hostnames of the form `<service>.<node>.tail1234.ts.net` via Traefik ingress rules, using Tailscale-provisioned TLS certificates, from any machine connected to the Tailnet.
- **FR-003**: Tailscale MUST be installed and configured as an EC2 system service via Terraform userdata; it is NOT managed by ArgoCD or the Helm chart.
- **FR-004**: Enabling or disabling Tailscale on the EC2 instance MUST be controlled by a Terraform variable; no changes to the k3s cluster or Helm values are required.
- **FR-005**: The Tailscale auth key MUST be stored in AWS SSM Parameter Store and fetched by the userdata script at instance startup; it MUST NOT be committed to git or embedded in Terraform state in plaintext.
- **FR-006**: The `make tunnel-start`, `make argo-ui`, `make prometheus-ui`, and equivalent port-forward targets MUST remain functional as a fallback but MUST NOT be required for normal operation once this feature is enabled.
- **FR-007**: DNS resolution for internal hostnames MUST work exclusively on the Tailnet; hostnames MUST NOT resolve from public internet.
- **FR-008**: The kubeconfig used by `kubectl` MUST connect to the k3s API via the Tailscale-routed address, removing the dependency on `make tunnel-start`.

### Key Entities

- **Tailnet**: The private overlay network managed by Tailscale; the EC2 instance joins as a subnet router node.
- **Subnet Router**: The Tailscale daemon running on the EC2 instance that advertises the VPC CIDR routes to the Tailnet, making node-level IPs reachable from VPN-connected machines.
- **Auth Key**: A Tailscale-issued credential that allows a new node to join the Tailnet without interactive approval; stored in AWS SSM Parameter Store and fetched at EC2 instance startup.
- **MagicDNS Hostname**: The auto-assigned Tailscale hostname for the EC2 node (e.g., `<node>.tail1234.ts.net`); stable across reboots and used as the base for service ingress subdomains.
- **Ingress Rule**: A Traefik ingress resource that routes a subdomain hostname (e.g., `argocd.<node>.tail1234.ts.net`) to the corresponding in-cluster service.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A developer can open the ArgoCD UI in a browser over HTTPS with no certificate warning, in under 10 seconds from the moment VPN is connected, with zero terminal commands required.
- **SC-002**: All four platform UIs (ArgoCD, Argo Workflows, Prometheus, httpbin) are accessible via hostname within 60 seconds of the subnet router pod reaching ready state after a fresh deploy.
- **SC-003**: A fresh EC2 + bootstrap cycle restores full VPN access automatically — zero manual post-bootstrap steps beyond injecting the pre-provisioned auth key secret.
- **SC-004**: None of the internal hostnames resolve from a machine that is not connected to the Tailnet (confirming no public exposure).
- **SC-005**: The `make` tunnel/UI targets continue to work as a fallback so no existing workflows are broken for users who prefer them.

## Assumptions

- Tailnet ACLs are left at default (allow all) for now; per-user access restrictions are out of scope.
- DNS resolution uses Tailscale MagicDNS for the EC2 node hostname; service subdomains are routed via Traefik ingress rules. No Route53 private hosted zone is provisioned.
- The EC2 instance's Tailscale MagicDNS hostname is stable across reboots; advertised subnet routes are re-registered automatically on Tailscale service restart.
- The Tailscale auth key is stored in AWS SSM Parameter Store before Terraform provisions the EC2 instance; it is fetched by userdata at startup.
- `make get-kubeconfig` will be updated to write a kubeconfig targeting the EC2 node's Tailscale IP rather than `localhost:6443`.
- Only the VPC subnet CIDR is advertised to the Tailnet (not pod/service CIDRs); services are accessed via Traefik ingress, not direct ClusterIP routing.
- Tailscale is managed entirely by Terraform (EC2 userdata), not by ArgoCD or the Helm chart.
