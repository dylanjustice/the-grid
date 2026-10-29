# Contract: Makefile Interface Changes

**Branch**: `004-tailscale-private-access` | **Date**: 2026-10-28

This document describes changes to the `make` interface. All existing targets are preserved as fallbacks per FR-006.

---

## Modified Targets

### `get-kubeconfig`

**Before**: Fetches kubeconfig and hardcodes `server: https://localhost:6443`. Requires `make tunnel-start` to be running before `kubectl` can be used.

**After**: Fetches kubeconfig and sets `server: https://<tailscale-hostname>:6443`. Requires only Tailscale VPN to be connected. Falls back to `localhost:6443` if the Tailscale hostname cannot be discovered.

**Callers**: All `make` targets that invoke `kubectl` benefit automatically once `get-kubeconfig` has been re-run with Tailscale active.

---

## Unchanged Targets (now fallback only)

The following targets remain functional but are no longer required for normal operation when Tailscale is enabled:

| Target | Was required for | Now |
|---|---|---|
| `make tunnel-start` | All kubectl and UI access | Fallback only |
| `make tunnel-stop` | Cleanup | Fallback only |
| `make argo-ui` | ArgoCD browser access | Fallback only |
| `make prometheus-ui` | Prometheus browser access | Fallback only |
| `make httpbin-ui` | httpbin browser access | Fallback only |

Help text for these targets should be updated to indicate fallback status, e.g.:
```
tunnel-start  - (fallback) Start SSM port forward to k3s API
argo-ui       - (fallback) Port-forward ArgoCD UI to https://localhost:2746
```

---

## Service URLs (when Tailscale active)

These are the stable URLs once Tailscale Serve is configured. The `<node>` segment is the MagicDNS hostname assigned by Tailscale (e.g., `ip-10-0-1-5`).

| Service | URL |
|---|---|
| ArgoCD | `https://<node>.<tailnet>.ts.net` |
| Argo Workflows | `https://<node>.<tailnet>.ts.net:2746` |
| Prometheus | `https://<node>.<tailnet>.ts.net:9090` |
| httpbin | `https://<node>.<tailnet>.ts.net:8080` |
| k3s API | `https://<node>.<tailnet>.ts.net:6443` |

`<node>` is the MagicDNS hostname (e.g. `ip-10-0-0-233`). Find it via `tailscale status` or the Tailscale admin console. The node segment changes on instance replacement; the tailnet domain (`<tailnet>.ts.net`) is permanent.

---

## New Terraform Variables

| Variable | Location | Required | Description |
|---|---|---|---|
| `tailscale_enabled` | `live/flynn/variables.tf` | No (default `false`) | Set to `true` to enable Tailscale in the next `make live-apply` |

No new `make` targets are introduced. Tailscale is enabled/disabled via Terraform, not via `make`.
