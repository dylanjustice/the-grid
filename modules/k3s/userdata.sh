#!/bin/bash
set -eux

# Update system
dnf update -y

# Create k3s config directory
mkdir -p /etc/rancher/k3s

# Install ecr credential provider (arm64 to match instance arch)
curl -L -o /usr/local/bin/ecr-credential-provider https://github.com/dntosas/ecr-credential-provider/releases/download/v1.2.0/ecr-credential-provider-linux-arm64
chmod +x /usr/local/bin/ecr-credential-provider

# Configure kubelet credential provider for ECR
cat <<EOF > /etc/rancher/k3s/credential-provider-config.yaml
apiVersion: kubelet.config.k8s.io/v1
kind: CredentialProviderConfig
providers:
- name: ecr-credential-provider
  matchImages:
  - "*.dkr.ecr.*.amazonaws.com"
  defaultCacheDuration: "12h"
  apiVersion: credentialprovider.kubelet.k8s.io/v1
EOF

# Install k3s with kubelet credential provider args
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="\
  --kubelet-arg=image-credential-provider-config=/etc/rancher/k3s/credential-provider-config.yaml \
  --kubelet-arg=image-credential-provider-bin-dir=/usr/local/bin" sh -

# Wait for node ready
sleep 30

# Make kubeconfig readable
chmod 644 /etc/rancher/k3s/k3s.yaml

# Optional: install kubectl symlink
ln -s /usr/local/bin/k3s /usr/local/bin/kubectl || true

# Replace that EC2 dammit!