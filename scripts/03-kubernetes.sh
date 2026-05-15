#!/usr/bin/env bash
set -euo pipefail

# Install Kubernetes components (kubeadm, kubelet, kubectl)
# This script prepares the system for cluster initialization

K8S_VERSION="1.36"

echo "Installing Kubernetes packages..."

apt-get update
apt-get install -y apt-transport-https ca-certificates curl gpg

# Add Kubernetes repository
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key |
    gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" |
    tee /etc/apt/sources.list.d/kubernetes.list

apt-get update

# Install specific versions to ensure compatibility
apt-get install -y kubelet=1.36.0-1.1 kubeadm=1.36.0-1.1 kubectl=1.36.0-1.1

# Prevent automatic updates
apt-mark hold kubelet kubeadm kubectl

systemctl enable kubelet
systemctl start kubelet
