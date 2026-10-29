# Quickstart: Tailscale Private Access Validation

**Branch**: `004-tailscale-private-access` | **Date**: 2026-10-28

End-to-end validation guide. Covers one-time prerequisites, provisioning, and acceptance scenario verification.

---

## Prerequisites

### 1. Install Tailscale on your local machine

Download and install from tailscale.com. Sign in to your Tailscale account. The EC2 instance will join the same Tailnet.

### 2. Create a reusable Tailscale auth key

1. Go to Tailscale admin console → Settings → Keys → Generate auth key.
2. Check **Reusable** and set **Expiry** to "No expiry."
3. Copy the key value (shown only once).

### 3. Seed the Tailscale auth key (one-time)

Terraform creates the Secrets Manager secret container. Seed the value once with the AWS CLI — you never need to do this again unless rotating:

```bash
aws secretsmanager put-secret-value \
  --region us-east-2 \
  --secret-id /the-grid/tailscale/auth-key \
  --secret-string "tskey-auth-XXXXX"
```

To rotate the key, repeat this command with the new key value.

---

## Provisioning

```bash
make live-apply
```

Terraform will replace the EC2 instance (userdata changed → `replace_triggered_by` fires). The new instance will:
1. Install Tailscale, join the Tailnet, advertise VPC routes.
2. Install k3s with the Tailscale hostname in the TLS SAN.
3. Start the `tailscale-serve-setup` systemd unit, which discovers ClusterIPs and configures Tailscale Serve.

Allow ~5 minutes for full startup (instance boot + k3s ready + ArgoCD sync + Tailscale Serve config).

---

## Verification Steps

### Step 1: Confirm EC2 joined the Tailnet

In Tailscale admin console, a new machine should appear (e.g., `ip-10-0-1-5`). Note the full MagicDNS hostname: `ip-10-0-1-5.tailXXXX.ts.net`.

Check that **subnet routes** are listed for `10.0.0.0/20`. If routes show as "awaiting approval," approve them in the admin console (Routes tab on the machine).

### Step 2: Connect Tailscale on your local machine

```bash
# macOS/Linux
tailscale up
tailscale status   # should show the EC2 machine as a peer
```

### Step 3: Refresh kubeconfig (no tunnel required)

```bash
make get-kubeconfig
kubectl get nodes   # should return the k3s node with no SSM tunnel running
```

Expected output:
```
NAME           STATUS   ROLES                  AGE   VERSION
ip-10-0-1-5   Ready    control-plane,master   5m    v1.31.x+k3s1
```

If this fails, verify Tailscale is connected (`tailscale status`) and that no SSM tunnel is active.

### Step 4: Verify HTTPS access to platform UIs

Open each URL in a browser. No certificate warnings should appear.

| Service | URL |
|---|---|
| ArgoCD | `https://ip-10-0-1-5.tailXXXX.ts.net` |
| Argo Workflows | `https://ip-10-0-1-5.tailXXXX.ts.net:2746` |
| Prometheus | `https://ip-10-0-1-5.tailXXXX.ts.net:9090` |
| httpbin | `https://ip-10-0-1-5.tailXXXX.ts.net:8080` |

Replace `ip-10-0-1-5.tailXXXX.ts.net` with your actual MagicDNS hostname from Step 1.

### Step 5: Confirm no public exposure (SC-004)

Disconnect Tailscale (`tailscale down`) and retry the URLs above. All should fail to load.

Reconnect Tailscale afterward.

### Step 6: Verify fallback targets still work (SC-005)

```bash
make tunnel-start   # SSM tunnel in background
make argo-ui        # port-forward ArgoCD to localhost:2746
# visit https://localhost:2746 — should load
# Ctrl-C to stop, then make tunnel-stop
```

### Step 7: Validate fresh-instance reprovisioning (Story 3)

```bash
make k3s-destroy     # destroys only the EC2 instance
make live-apply      # provisions a new instance
# Wait ~5 minutes
tailscale status     # new machine should appear
make get-kubeconfig
kubectl get nodes    # should succeed with no tunnel
```

---

## Troubleshooting

| Symptom | Check |
|---|---|
| EC2 doesn't appear in Tailscale admin | Check EC2 console output for userdata errors; verify `/the-grid/tailscale/auth-key` exists in Secrets Manager (`aws secretsmanager describe-secret --secret-id /the-grid/tailscale/auth-key`) |
| `kubectl` TLS error | Verify the Tailscale hostname is in k3s TLS SANs: `openssl s_client -connect <ts-hostname>:6443 2>/dev/null \| openssl x509 -noout -text \| grep DNS` |
| Browser cert warning on UI | Tailscale Serve may not have provisioned a cert yet; wait 60s and retry. `tailscale serve status` on the EC2 instance (via SSM) shows cert state |
| UI returns 502 | ArgoCD/Argo Workflows not yet ready; check `kubectl get pods -A` |
| Subnet routes need approval | Go to Tailscale admin → machine → Routes → Approve `10.0.0.0/20` |
