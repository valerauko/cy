#!/usr/bin/env bash
set -euo pipefail

# Defaults match k0s/Kubernetes 1.36 line.
KUBERNETES_VERSION="${KUBERNETES_VERSION:-v1.36}"
CRIO_VERSION="${CRIO_VERSION:-v1.36}"

sudo install -d -m 0755 /etc/apt/keyrings

sudo apt-get update
sudo apt-get install -y ca-certificates curl gpg software-properties-common

curl -fsSL "https://pkgs.k8s.io/core:/stable:/${KUBERNETES_VERSION}/deb/Release.key" \
  | sudo gpg --batch --yes --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${KUBERNETES_VERSION}/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null

curl -fsSL "https://download.opensuse.org/repositories/isv:/cri-o:/stable:/${CRIO_VERSION}/deb/Release.key" \
  | sudo gpg --batch --yes --dearmor -o /etc/apt/keyrings/cri-o-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/cri-o-apt-keyring.gpg] https://download.opensuse.org/repositories/isv:/cri-o:/stable:/${CRIO_VERSION}/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/cri-o.list >/dev/null

sudo apt-get update
sudo apt-get install -y cri-o conmon crun cri-tools containernetworking-plugins ethtool iptables

sudo tee /etc/modules-load.d/k8s.conf >/dev/null <<'EOF'
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

sudo tee /etc/sysctl.d/99-kubernetes-cri.conf >/dev/null <<'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sudo sysctl --system

# Force CRI-O to use crun as the default OCI runtime.
sudo install -d -m 0755 /etc/crio/crio.conf.d
sudo tee /etc/crio/crio.conf.d/10-crun.conf >/dev/null <<'EOF'
[crio.runtime]
default_runtime = "crun"

[crio.runtime.runtimes.crun]
runtime_path = "/usr/bin/crun"
runtime_type = "oci"
runtime_root = "/run/crun"
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now crio

sudo crictl --runtime-endpoint unix:///var/run/crio/crio.sock info >/dev/null

echo "CRI-O + crun is installed and running."
