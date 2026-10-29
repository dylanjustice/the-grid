# Tasks: Tailscale Private Access

**Input**: Design documents from `specs/004-tailscale-private-access/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/makefile-interface.md, quickstart.md

**Organization**: Tasks grouped by user story. Each story phase is independently testable.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no shared dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)

---

## Phase 1: Setup (Variable Scaffolding)

**Purpose**: Add Terraform variable declarations so downstream modules can conditionally enable Tailscale.

- [x] T001 Add variables `tailscale_enabled` (bool, default `false`), `tailscale_ssm_param_path` (string, default `"/the-grid/tailscale/auth-key"`), and `tailscale_advertise_routes` (string, no default) to `modules/k3s/variables.tf`
- [x] T002 [P] Add `tailscale_enabled` (bool, default `false`) to `live/flynn/variables.tf`; in `live/flynn/main.tf` module `"k3s"` call, pass `tailscale_enabled = var.tailscale_enabled`, `tailscale_ssm_param_path = "/the-grid/tailscale/auth-key"`, and `tailscale_advertise_routes = var.vpc_cidr`

**Checkpoint**: `terraform validate` passes in both `modules/k3s/` and `live/flynn/`

---

## Phase 2: Foundational (IAM + Template Wiring)

**Purpose**: Wire userdata templating and grant EC2 permission to read the SSM auth key. Must complete before any story can be tested end-to-end.

**⚠️ CRITICAL**: No story validation can succeed until the EC2 instance can be provisioned with Tailscale enabled.

- [x] T003 In `modules/k3s/main.tf`, change `terraform_data.k3s_user_data` from `file(...)` to `templatefile("${path.module}/userdata.sh", { tailscale_enabled = var.tailscale_enabled, tailscale_ssm_path = var.tailscale_ssm_param_path, tailscale_routes = var.tailscale_advertise_routes })`; update `aws_instance.k3s` to use the rendered template directly as `user_data`; rename `userdata.sh` to `userdata.sh.tpl` if needed to signal template syntax; escape all existing bash `${VAR}` references as `$${VAR}` (Terraform templatefile requires double-dollar for literal bash variable expansions)
- [x] T004 [P] Add `aws_iam_role_policy.k3s_tailscale_ssm` in `modules/k3s/main.tf` with `count = var.tailscale_enabled ? 1 : 0`; policy document grants `ssm:GetParameter` on `arn:aws:ssm:${var.region}:${var.account_id}:parameter/the-grid/tailscale/auth-key`; attach to `aws_iam_role.k3s`

**Checkpoint**: `terraform plan` in `live/flynn/` with `tailscale_enabled=true` shows IAM policy added and instance replacement triggered (userdata changed)

---

## Phase 3: User Story 1 - Access Platform UIs Without Port-Forward Commands (Priority: P1) 🎯 MVP

**Goal**: With Tailscale VPN connected, all four platform UIs (ArgoCD, Argo Workflows, Prometheus, httpbin) load in a browser over HTTPS with no certificate warning and no port-forward commands.

**Independent Test**: With VPN connected and no SSM tunnel or port-forward running, navigate to `https://<node>.tailXXXX.ts.net` — ArgoCD login page loads with a valid HTTPS cert.

### Implementation for User Story 1

- [x] T005 [US1] Add Tailscale install block to `modules/k3s/userdata.sh` (inside `%{ if tailscale_enabled }...%{ endif }` template guard): add Tailscale RPM repo from `https://pkgs.tailscale.com/stable/amazonlinux/2023/tailscale.repo`; `dnf install -y tailscale`; enable `net.ipv4.ip_forward = 1` in `/etc/sysctl.conf` and apply with `sysctl -p`; `systemctl enable --now tailscaled`; fetch auth key: `AUTH_KEY=$(aws ssm get-parameter --name "${tailscale_ssm_path}" --with-decryption --query Parameter.Value --output text 2>/dev/null)` — if empty, `echo "[FATAL] Tailscale auth key not found at ${tailscale_ssm_path}" >> /var/log/tailscale-setup.log` then `exit 1`; run `tailscale up --auth-key="$AUTH_KEY" --advertise-routes="${tailscale_routes}" --accept-dns=false`
- [x] T006 [US1] In `modules/k3s/userdata.sh`, immediately after `tailscale up` (within the tailscale_enabled block), capture `TS_HOSTNAME=$(tailscale status --json | jq -r '.Self.DNSName' | sed 's/\\.$//')` and log to `/var/log/tailscale-setup.log`; modify the existing k3s `curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="..."` line to append `--tls-san=$TS_HOSTNAME` so the k3s API server cert includes the MagicDNS hostname as a TLS SAN
- [x] T007 [P] [US1] Add `tailscale-serve-setup` target to `Makefile`; the target sends an SSM Run Command to the EC2 instance that: (1) discovers ClusterIPs for each service via `k3s kubectl get svc <name> -n <namespace> -o jsonpath='{.spec.clusterIP}'` using the service/namespace pairs from `data-model.md`; (2) runs `tailscale serve` to configure HTTPS proxy for each service per the port map in `data-model.md` (ArgoCD: port 443 → `https+insecure://ClusterIP:443`; Argo Workflows: port 2746 → `http://ClusterIP:2746`; Prometheus: port 9090 → `http://ClusterIP:80`; httpbin: port 8080 → `http://ClusterIP:80`); target must wait for the SSM command to complete and print its output
- [x] T008 [US1] Add `tailscale-serve-setup` invocation as final step in `scripts/bootstrap-k3s.sh`, after the existing `kubectl apply` lines; preceded by `kubectl wait --for=condition=ready pod --all -n argocd --timeout=300s` and equivalent waits for `the-grid-workflows`, `the-grid-monitoring`, `the-grid-synthetics`; calls `$(MAKE) tailscale-serve-setup`

**Checkpoint**: `make k3s-bootstrap` completes, `https://<node>.tailXXXX.ts.net` loads ArgoCD with no cert warning; same for the three other services on their respective ports

---

## Phase 4: User Story 2 - Access Kubernetes API Without SSM Tunnel (Priority: P2)

**Goal**: `kubectl get nodes` succeeds from a developer laptop with Tailscale connected and no SSM tunnel running.

**Independent Test**: With no `make tunnel-start` session active and Tailscale connected, `kubectl get pods -A` returns cluster state.

### Implementation for User Story 2

- [x] T009 [US2] Update `scripts/get-kubeconfig.sh`: after fetching `kubeconfig.yaml` via SSM, add a Tailscale hostname discovery step — send an SSM Run Command to execute `tailscale status --json | jq -r '.Self.DNSName' | sed 's/\\.$//'` on the EC2 instance and capture the output; if the command succeeds and output is non-empty, set `CLUSTER_SERVER="https://$TS_HOSTNAME:6443"`; if it fails (Tailscale not installed or not connected), log a warning and fall back to existing `CLUSTER_SERVER="https://localhost:6443"` behavior so `make tunnel-start` users are not broken

**Checkpoint**: Run `make get-kubeconfig` with Tailscale connected; run `kubectl get nodes` with no SSM tunnel — cluster node appears in output

---

## Phase 5: User Story 3 - Reproduce VPN from Fresh EC2 Instance (Priority: P3)

**Goal**: Destroying and reprovisioning the EC2 instance restores full VPN and UI access automatically, with no manual SSH or post-creation steps.

**Independent Test**: Run `make k3s-destroy && make live-apply`; within 10 minutes (instance boot + ArgoCD sync + serve setup), `kubectl get nodes` and all four UI URLs work with no manual intervention.

### Implementation for User Story 3

- [x] T010 [US3] Harden the Tailscale block in `modules/k3s/userdata.sh`: redirect all Tailscale setup output to `/var/log/tailscale-setup.log` with timestamps (`exec >> >(ts '[%Y-%m-%d %H:%M:%S]' >> /var/log/tailscale-setup.log) 2>&1` or equivalent); after `tailscale up`, verify with `tailscale status` and log result; if `tailscale status` exits non-zero, log `[FATAL] tailscale up failed` and `exit 1` to surface failure in EC2 console output (reachable via `aws ec2 get-console-output`)
- [x] T011 [P] [US3] Add `tailscale_enabled = true` to `live/flynn/terraform.tfvars` (create file if absent) and document in `quickstart.md` Step 4 that this file must exist before `make live-apply`; verify that `make live-apply` with a missing SSM parameter fails loudly with a visible error in EC2 console output (per Story 3 acceptance scenario 3)

**Checkpoint**: Destroy and reprovision EC2; confirm Tailscale node appears in admin console, subnet routes are pending approval, routes are approved, `kubectl get nodes` works, all four UIs load — zero manual steps beyond pre-provisioned SSM param and route approval

---

## Phase 6: Polish & Cross-Cutting Concerns

- [x] T012 Update `Makefile` help text: add `(fallback)` annotation to `tunnel-start`, `tunnel-stop`, `argo-ui`, `prometheus-ui`, `httpbin-ui` entries per `contracts/makefile-interface.md`; add `tailscale-serve-setup` to the help output with description `"Configure Tailscale Serve for platform UIs (run once after bootstrap)"`
- [x] T013 [P] Validate end-to-end against all acceptance scenarios in `quickstart.md`: Steps 1–7; record actual MagicDNS hostname and update `contracts/makefile-interface.md` Service URLs table with the real `tailXXXX` tailnet name
- [x] T014 [P] Approve subnet routes in Tailscale admin console (Routes tab for the EC2 node → approve `10.0.0.0/20`); document this one-time step in `quickstart.md` Step 1 with a callout that routes must be approved before `kubectl` or UI access works

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 — T003 and T004 can run in parallel with each other
- **US1 (Phase 3)**: Depends on Phase 2 — T005, T007 can start in parallel; T006 depends on T005; T008 depends on T007
- **US2 (Phase 4)**: Depends on Phase 2 — can run in parallel with US1
- **US3 (Phase 5)**: Depends on Phase 3 and Phase 4 being complete
- **Polish (Phase 6)**: Depends on US1 completion; T013/T014 can run in parallel

### User Story Dependencies

- **US1 (P1)**: Depends only on Foundational — no dependency on US2 or US3
- **US2 (P2)**: Depends only on Foundational — no dependency on US1
- **US3 (P3)**: Validates the full provisioning loop — depends on US1 and US2 being complete

### Within Each Story

- T005 → T006 (must install Tailscale before capturing hostname for k3s SAN)
- T007 → T008 (serve target must exist before bootstrap calls it)
- T010 and T011 are independent within US3

---

## Parallel Example: User Story 1

```bash
# After Phase 2 completes, these can run in parallel:
Task: T005 "Add Tailscale install block to modules/k3s/userdata.sh"  # then T006 follows
Task: T007 "Add tailscale-serve-setup Makefile target"               # then T008 follows
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001, T002)
2. Complete Phase 2: Foundational (T003, T004)
3. Complete Phase 3: US1 (T005 → T006, T007 → T008)
4. **STOP and VALIDATE**: Run `make k3s-bootstrap`, open `https://<node>.tailXXXX.ts.net` — ArgoCD should load with valid HTTPS cert
5. `make tunnel-start` + `make argo-ui` should still work as fallback (SC-005)

### Incremental Delivery

1. Setup + Foundational → Terraform-ready with Tailscale wired in
2. US1 → UIs accessible via browser with HTTPS, no port-forwarding
3. US2 → `kubectl` works without SSM tunnel
4. US3 → Fresh-instance reprovisioning is fully hands-free
5. Polish → Fallback help text updated, end-to-end validated

### Notes

- Terraform's `templatefile()` uses `${var}` for template variables and requires bash `${}` to be escaped as `$${}`; audit the existing userdata.sh carefully before converting
- The Tailscale block MUST run before k3s install in userdata (TLS SAN depends on TS_HOSTNAME)
- Route approval in the Tailscale admin console is a one-time manual step per Tailnet (not per EC2 instance replacement) — once approved for the account, new instances advertising the same CIDR inherit approval automatically if using the same auth key tag
- `tailscale serve` state is persisted by `tailscaled` across reboots; it only needs to be configured once per instance lifecycle (not on every reboot)
