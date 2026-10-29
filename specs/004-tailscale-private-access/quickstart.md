# Quickstart: Tailscale Private Access

**Tailnet**: `<tailnet>.ts.net` | **Updated**: 2026-10-29

Platform UIs and `kubectl` are accessible over the Tailnet with no SSM tunnel or port-forwarding.

---

## One-Time Prerequisites

### 1. Install Tailscale

Download from tailscale.com and sign in. The EC2 instance joins the same tailnet.

### 2. Create a reusable auth key

Tailscale admin console → Settings → Keys → Generate auth key.
Check **Reusable** and set **Expiry** to "No expiry." Copy the key (shown once).

### 3. Seed the auth key in Secrets Manager

Terraform creates the secret container on `make live-apply`. Seed the value once:

```bash
aws secretsmanager put-secret-value \
  --region us-east-2 \
  --secret-id /the-grid/tailscale/auth-key \
  --secret-string "tskey-auth-XXXXX"
```

You never need to do this again unless rotating the key.

### 4. Approve subnet routes (first tailnet only)

After the first instance joins, go to the Tailscale admin console → the machine → Routes tab → approve `10.0.0.0/20`. This is a one-time step per tailnet; new instances advertising the same CIDR inherit approval automatically.

---

## Provisioning

```bash
make live-apply
```

The new instance will:
1. Fetch the auth key from Secrets Manager and join the Tailnet
2. Install k3s with the Tailscale MagicDNS hostname in the TLS SAN
3. Advertise VPC routes (`10.0.0.0/20`) to the Tailnet

Allow ~3 minutes for instance boot and k3s startup.

---

## Bootstrap

```bash
tailscale up                 # connect locally
make get-kubeconfig          # writes ~/.kube/the-grid kubeconfig
kubectl get nodes            # verify cluster access
make k3s-bootstrap           # install ArgoCD, Prometheus, configure Tailscale Serve
```

`k3s-bootstrap` waits for all workloads to be ready then runs `make tailscale-serve-setup` automatically.

**First-time Tailscale Serve**: On the very first `tailscale serve` call, the Tailscale admin console may prompt you to enable Serve for your tailnet. The `--yes` flag handles this automatically.

Allow ~5 additional minutes for ArgoCD to sync all applications.

---

## Service URLs

| Service | URL |
|---|---|
| ArgoCD | `https://<node>.<tailnet>.ts.net` |
| Argo Workflows | `https://<node>.<tailnet>.ts.net:2746` |
| Prometheus | `https://<node>.<tailnet>.ts.net:9090` |
| httpbin | `https://<node>.<tailnet>.ts.net:8080` |
| k3s API | `https://<node>.<tailnet>.ts.net:6443` |

The `<node>` segment changes on instance replacement. Find the current hostname via `tailscale status` or the admin console.

---

## After Instance Replacement

When the EC2 instance is replaced (`make k3s-destroy && make live-apply`):

```bash
tailscale status             # confirm new node appears
make get-kubeconfig          # update kubeconfig with new Tailscale hostname
make k3s-bootstrap           # re-deploy workloads and reconfigure Serve
```

Subnet route approval carries over automatically (same CIDR, same tailnet).

---

## Fallback: SSM Tunnel

If Tailscale is unavailable, the original SSM-based workflow still works:

```bash
make tunnel-start            # port-forward k3s API to localhost:6443
make get-kubeconfig          # falls back to localhost:6443
kubectl get nodes
make argo-ui                 # port-forward ArgoCD to localhost:2746
make tunnel-stop
```

---

## Troubleshooting

| Symptom | Check |
|---|---|
| EC2 doesn't appear in Tailscale admin | Check console output: `aws ec2 get-console-output --region us-east-2 --instance-id <id> --output text \| tail -50`; verify secret exists: `aws secretsmanager describe-secret --secret-id /the-grid/tailscale/auth-key` |
| Auth key invalid error in console output | Key was expired or revoked. Generate a new reusable key, update the secret, then run `tailscale up` manually via `make connect` |
| `kubectl` TLS error | Verify the Tailscale hostname is in k3s SANs: `openssl s_client -connect <ts-hostname>:6443 2>/dev/null \| openssl x509 -noout -text \| grep DNS` |
| Browser cert warning on UI | Tailscale Serve cert may still be provisioning; wait 60s and retry |
| UI returns 502 | Workloads not yet ready; check `kubectl get pods -A` |
| Subnet routes need approval | Tailscale admin → machine → Routes → approve `10.0.0.0/20` |
| `tailscale serve status` shows no config | Run `make tailscale-serve-setup` to reconfigure |
