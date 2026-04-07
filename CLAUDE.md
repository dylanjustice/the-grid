# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

The Grid is a self-hosted synthetic testing platform — the goal is Datadog Synthetics without the bill. It ships as a Helm chart that users install into their own Kubernetes cluster. The full product vision and milestone plan are in `docs/project-plan.md`.

The current repo is also the dev environment: a single k3s node on EC2 (ARM64, t4g.medium) running the platform via ArgoCD GitOps. That's the proving ground, not the product.

## Commands

All common operations go through `make`. Run `make help` for the full list.

**Tests (run from repo root):**
```bash
make test        # headless
make test-ui     # interactive Playwright UI
```
Tests live in `playwright-synthetics/tests/`. Playwright config is `playwright-synthetics/playwright.config.ts`. Node 23 is required (`nvm use 23`).

**Docker:**
```bash
make docker-build   # tags with git SHA and :latest
make docker-push    # builds + logs into ECR + pushes
```
Image is tagged with the short git SHA. The ECR URL is derived from `aws sts get-caller-identity` at runtime — requires valid AWS credentials.

**Lab lifecycle:**
```bash
make tunnel-start     # SSM port-forward to k3s API on :6443
make get-kubeconfig   # pulls kubeconfig via SSM
make k3s-bootstrap    # installs ArgoCD + Prometheus + applies ArgoCD apps
make k3s-destroy      # tears down only the EC2 instance (preserves VPC/ECR)
make argo-ui          # port-forward Argo Workflows UI → https://localhost:2746
make prometheus-ui    # port-forward Prometheus → http://localhost:9090
```

**Terraform** has two workspaces: `bootstrap/` (S3 state backend, one-time) and `live/flynn/` (VPC, EC2, ECR). Both follow the `make <workspace>-init/plan/apply/destroy` pattern.

## Architecture

### How the platform works

1. A `CronWorkflow` in Argo Workflows runs `npx playwright test` on a schedule inside the runner container
2. Tests push Prometheus metrics to the Pushgateway via `prom-client` after each run
3. Prometheus scrapes the Pushgateway (static config, cross-namespace DNS)
4. Playwright's HTML report is generated but not yet shipped anywhere (S3 upload is a planned milestone)

### GitOps flow

ArgoCD manages everything in `gitops/`. Structure:
- `gitops/applications/` — ArgoCD `Application` manifests, one per workload
- `gitops/workloads/` — Helm charts that ArgoCD deploys; each wraps an upstream chart or is custom

All three applications auto-sync with prune + selfHeal. Pushing to `main` triggers reconciliation within ~3 minutes, or use `make argo-sync` to force it.

### Kubernetes namespaces

| Namespace | Contents |
|---|---|
| `argocd` | ArgoCD itself |
| `the-grid-workflows` | Argo Workflows controller + server |
| `the-grid-synthetics` | CronWorkflows + Pushgateway |
| `the-grid-monitoring` | Prometheus |

### Container image

Built from `playwright-synthetics/Dockerfile` (multi-stage). The runtime stage contains browsers and node_modules but test files are copied in at build time today. The plan is to decouple these so the runner image is stable and tests are injected via ConfigMap (inline) or S3 (published bundle) at pod startup — see `docs/project-plan.md` milestone 2.

### Metrics instrumentation

`prom-client` is used directly in `playwright-synthetics/tests/http-bin.spec.ts`. A shared library (`@the-grid/synthetics`) that wraps Playwright's `test` fixture and handles instrumentation automatically is a planned milestone. When building new tests, follow the existing pattern until that library exists.

### Planned: Kubernetes Operator

A kubebuilder-based operator (Go + controller-runtime) will manage `SyntheticTest` and `SyntheticTestRun` CRDs. The operator reconciles `SyntheticTest` → Argo `CronWorkflow`. This doesn't exist yet — current CronWorkflows are defined in `gitops/workloads/playwright-synthetics/templates/workflows.yaml` via Helm.
