.PHONY: help docker-login docker-build terraform-init terraform-plan terraform-apply terraform-destroy

# Variables
AWS_ACCOUNT ?= $(shell aws sts get-caller-identity --query Account --output text)
AWS_REGION ?= us-east-1
ECR_REPO_NAME ?= the-grid
TERRAFORM_AUTO_APPROVE ?= false

# Derive ECR URI from account and region
ECR_URL = $(AWS_ACCOUNT).dkr.ecr.$(AWS_REGION).amazonaws.com
ECR_REPO = $(ECR_URL)/$(ECR_REPO_NAME)

help:
	@echo "Available targets:"
	@echo "  docker-login          - Login to AWS ECR"
	@echo "  docker-build          - Build Docker image from src/"
	@echo "  docker-push           - Push Docker image to ECR"
	@echo "  bootstrap-init        - Terraform init in bootstrap/"
	@echo "  bootstrap-plan        - Terraform plan in bootstrap/"
	@echo "  bootstrap-apply       - Terraform apply in bootstrap/"
	@echo "  bootstrap-destroy     - Terraform destroy in bootstrap/"
	@echo "  live-init             - Terraform init in live/flynn/"
	@echo "  live-plan             - Terraform plan in live/flynn/"
	@echo "  live-apply            - Terraform apply in live/flynn/"
	@echo "  live-destroy          - Terraform destroy in live/flynn/"
	@echo ""
	@echo "Variables:"
	@echo "  AWS_ACCOUNT (default: auto-detected)"
	@echo "  AWS_REGION (default: us-east-1)"
	@echo "  ECR_REPO_NAME (default: the-grid)"
	@echo "  TERRAFORM_AUTO_APPROVE (default: false)"

# Docker targets
docker-login:
	@echo "Logging in to ECR at $(ECR_URL)..."
	aws ecr get-login-password --region $(AWS_REGION) | docker login --username AWS --password-stdin $(ECR_URL)

docker-build:
	@echo "Building Docker image: $(ECR_REPO):latest..."
	docker build -t $(ECR_REPO):latest src/

docker-push: docker-build docker-login
	@echo "Pushing Docker image to ECR..."
	docker push $(ECR_REPO):latest

# Bootstrap Terraform targets
bootstrap-init:
	@echo "Running terraform init in bootstrap/..."
	cd bootstrap && terraform init

bootstrap-plan: bootstrap-init
	@echo "Running terraform plan in bootstrap/..."
	cd bootstrap && terraform plan -out=tfplan

bootstrap-apply: bootstrap-plan
	@echo "Running terraform apply in bootstrap/..."
	cd bootstrap && terraform apply $(if $(filter true,$(TERRAFORM_AUTO_APPROVE)),-auto-approve,tfplan)

bootstrap-destroy: bootstrap-init
	@echo "Running terraform destroy in bootstrap/..."
	cd bootstrap && terraform destroy $(if $(filter true,$(TERRAFORM_AUTO_APPROVE)),-auto-approve,)

# Live (Flynn) Terraform targets
live-init:
	@echo "Running terraform init in live/flynn/..."
	cd live/flynn && terraform init

live-plan: live-init
	@echo "Running terraform plan in live/flynn/..."
	cd live/flynn && terraform plan -out=tfplan

live-apply: live-plan
	@echo "Running terraform apply in live/flynn/..."
	cd live/flynn && terraform apply $(if $(filter true,$(TERRAFORM_AUTO_APPROVE)),-auto-approve,tfplan)

live-destroy: live-init
	@echo "Running terraform destroy in live/flynn/..."
	cd live/flynn && terraform destroy $(if $(filter true,$(TERRAFORM_AUTO_APPROVE)),-auto-approve,)

# Convenience targets
all-init: bootstrap-init live-init
all-plan: bootstrap-plan live-plan
all-apply: bootstrap-apply live-apply
all-destroy: bootstrap-destroy live-destroy
