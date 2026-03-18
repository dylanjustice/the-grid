# The Grid

Synthetic reality, real lessons.

## Requirements

### Required Tools

- **Terraform** 1.14+
- **Docker** (latest stable)
- **Node.js** 18+ (managed via `nvm`)
- **kubectl** (Kubernetes CLI)
- **ArgoCD** CLI

### AWS Access

- **Granted** or **Assume** - For SSO access to AWS accounts
- AWS CLI configured with appropriate credentials

### Optional Tools

- **Playwright** - For end-to-end testing and synthetic monitoring
- **Make** - For running common tasks via Makefile

## Installation & Setup

### 1. AWS CLI & Session Manager Plugin

Install AWS CLI and the Session Manager plugin for secure session access:

```bash
# Install AWS CLI
brew install awscli

# Install Session Manager plugin
brew install --cask session-manager-plugin

# Verify installations
aws --version
session-manager-plugin --version
```

### 2. AWS SSO Configuration

```bash
aws configure sso
# SSO session name (Recommended): the-grid
# SSO start URL [None]: https://d-90661fcf12.awsapps.com/start
# SSO region [None]: us-east-1
# SSO registration scopes [None]: sso:account:access
```

Install and configure [Granted](https://granted.dev/) or [Assume](https://github.com/remotecom/assume) for SSO access:

**Using Granted:**

```bash
# Install Granted
brew tap fwdcloudsec/granted
brew install fwdcloudsec/granted/granted

granted -v
```

**Using Assume:**

```bash
assume
```

### 3. Node.js & Node Version Manager

Install and manage Node.js with `nvm`:

```bash
# Install nvm (if not already installed)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash

nvm install 23
nvm use 23

node --version
npm --version
```

### 4. Docker

Install Docker Desktop or Docker Engine:

```bash
brew install docker
```

### 5. Terraform

Install Terraform:

```bash
brew install terraform

terraform --version
```

### 6. Kubernetes Tools

Install kubectl and ArgoCD CLI:

```bash
brew install kubectl

brew install argocd
```

### 7. Playwright (for testing)

Playwright is used for end-to-end testing and synthetic monitoring. Dependencies are managed via npm:

```bash
cd src
npm install
npx playwright install
```

## Project Structure

```
bootstrap/          - Infrastructure bootstrap with Terraform
live/               - Live environment configurations (Flynn)
gitops/             - ArgoCD applications and workloads
  workloads/        - Helm chart workloads
    playwright-synthetics/  - Playwright test workflows
    kube-prometheus/ - Kubernetes monitoring
    argo-workflows/  - Argo Workflows for orchestration
src/                - Application source code
  tests/            - Playwright tests
  Dockerfile        - Container image definition
```

## Common Tasks

### Docker Operations

```bash
# Login to AWS ECR
make docker-login

# Build Docker image
make docker-build

# Build and push to ECR
make docker-push
```

### Spinning Up The Lab

```bash
# Start the instance
make live-apply

# Open an SSM tunnel to the instance
make tunnel-start

# Configure kubectl
./scripts/get-kubeconfig.sh

# Start infrastructure
./scripts/bootstrap-k3s.sh
```

### Spinning Down the Lab

```bash
# Keep everything but the k3s instance
make k3s-destroy

make tunnel-stop
```

## kubectl

Run `kubectl` against the lab environment in k3s

```bash
# Start a tunnel session
make tunnel-start

# Check nodes
kubectl get nodes

# Kill tunnels
make tunnel-stop
```

### Running Playwright Tests

```bash
# Install dependencies
npm install

# Run Playwright tests
npm test

# Run tests with UI mode
npm run test:ui

# View test report
npm run test:report
```

## Environment Variables

Configure the following environment variables as needed:

```bash
# AWS configuration
export AWS_REGION=us-east-2
```

## Makefile Targets

Run `make help` to see all available targets for docker, terraform, and other operations.
