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

### 1. AWS SSO Configuration

Install and configure [Granted](https://granted.dev/) or [Assume](https://github.com/remotecom/assume) for SSO access:

**Using Granted:**

```bash
# Install Granted
brew install granted

# Configure your AWS profiles
granted setup

# Login to an AWS account
granted assume <profile-name>
```

**Using Assume:**

```bash
# Install Assume
brew install remotecom/tap/assume

# Login to an AWS account
assume <account-id>
```

### 2. Node.js & Node Version Manager

Install and manage Node.js with `nvm`:

```bash
# Install nvm (if not already installed)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash

# Install the required Node version
nvm install 18
nvm use 18

# Verify installation
node --version
npm --version
```

### 3. Docker

Install Docker Desktop or Docker Engine:

```bash
# macOS (via Homebrew)
brew install docker

# Or download Docker Desktop: https://www.docker.com/products/docker-desktop
```

### 4. Terraform

Install Terraform:

```bash
# macOS (via Homebrew)
brew install terraform

# Verify installation
terraform --version
```

### 5. Kubernetes Tools

Install kubectl and ArgoCD CLI:

```bash
# kubectl
brew install kubectl

# ArgoCD CLI
brew install argocd
```

### 6. Playwright (for testing)

Playwright is used for end-to-end testing and synthetic monitoring. Dependencies are managed via npm:

```bash
# Install Playwright dependencies (already in package.json)
npm install

# Install browser binaries
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

### Terraform Operations

```bash
# Initialize Terraform in bootstrap
make bootstrap-init

# Plan infrastructure changes in bootstrap
make bootstrap-plan

# Apply infrastructure changes in bootstrap
make bootstrap-apply

# Destroy bootstrap infrastructure
make bootstrap-destroy

# Similarly for live/flynn environment:
make live-init
make live-plan
make live-apply
make live-destroy
```

### Running Tests

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

## AWS Access with Granted/Assume

Before running any AWS commands or Terraform operations, ensure you're authenticated:

```bash
# Using Granted
granted assume production

# Using Assume
assume 123456789012

# Verify access
aws sts get-caller-identity
```

## Environment Variables

Configure the following environment variables as needed:

```bash
# AWS configuration
export AWS_REGION=us-east-1
export AWS_ACCOUNT=123456789012

# Terraform overrides
export TERRAFORM_AUTO_APPROVE=false

# Docker / ECR
export ECR_REPO_NAME=the-grid
```

## Getting Started

1. **Install all requirements** using the Installation & Setup section above
2. **Authenticate to AWS** using Granted or Assume
3. **Verify credentials** with `aws sts get-caller-identity`
4. **Initialize Terraform** with `make bootstrap-init`
5. **Review infrastructure plan** with `make bootstrap-plan`
6. **Apply infrastructure** with `make bootstrap-apply`
7. **Run tests** with `npm test`

## Makefile Targets

Run `make help` to see all available targets for docker, terraform, and other operations.
