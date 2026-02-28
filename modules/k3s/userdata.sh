#!/bin/bash
set -eux

# Update system
dnf update -y

# Install k3s
curl -sfL https://get.k3s.io | sh -

# Wait for node ready
sleep 30

# Make kubeconfig readable
chmod 644 /etc/rancher/k3s/k3s.yaml

# Optional: install kubectl symlink
ln -s /usr/local/bin/k3s /usr/local/bin/kubectl