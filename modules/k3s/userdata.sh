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

%{ if tailscale_enabled }
# ============================================================
# Tailscale (runs BEFORE k3s to capture TLS SAN hostname)
# ============================================================

# Fetch auth key from Secrets Manager
AUTH_KEY=$(aws secretsmanager get-secret-value \
  --secret-id "${tailscale_secret_arn}" \
  --query SecretString \
  --output text 2>/dev/null || true)

if [ -z "$${AUTH_KEY}" ]; then
  echo "[FATAL] $(date -u): Tailscale auth key not found at ${tailscale_secret_arn}" | tee -a /var/log/tailscale-setup.log >&2
  exit 1
fi

# Add Tailscale RPM repository
curl -fsSL https://pkgs.tailscale.com/stable/amazon-linux/2023/tailscale.repo \
  -o /etc/yum.repos.d/tailscale.repo

# Install Tailscale and jq (jq parses tailscale status JSON)
dnf install -y tailscale jq

# Enable IP forwarding
echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
echo 'net.ipv6.conf.all.forwarding = 1' >> /etc/sysctl.conf
sysctl -p /etc/sysctl.conf

# Start and enable the Tailscale daemon
systemctl enable --now tailscaled

# Join the Tailnet
tailscale up \
  --auth-key="$${AUTH_KEY}" \
  --advertise-routes="${tailscale_routes}" \
  --accept-dns=false

echo "$(date -u): Tailscale connected" >> /var/log/tailscale-setup.log

# Verify connection
if ! tailscale status &>/dev/null; then
  echo "[FATAL] $(date -u): tailscale status failed after tailscale up" | tee -a /var/log/tailscale-setup.log >&2
  exit 1
fi

# Capture MagicDNS hostname for k3s TLS SAN
TS_HOSTNAME=$(tailscale status --json | jq -r '.Self.DNSName' | sed 's/\.$//')
echo "$(date -u): Tailscale MagicDNS hostname: $${TS_HOSTNAME}" >> /var/log/tailscale-setup.log

K3S_TLS_SAN="--tls-san=$${TS_HOSTNAME}"
%{ endif }

# Install k3s with kubelet credential provider args
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="\
  --kubelet-arg=image-credential-provider-config=/etc/rancher/k3s/credential-provider-config.yaml \
  --kubelet-arg=image-credential-provider-bin-dir=/usr/local/bin $${K3S_TLS_SAN:-}" sh -

# Wait for node ready
sleep 30

# Make kubeconfig readable
chmod 644 /etc/rancher/k3s/k3s.yaml

# Optional: install kubectl symlink
ln -s /usr/local/bin/k3s /usr/local/bin/kubectl || true
