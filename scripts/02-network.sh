#!/usr/bin/env bash
set -euo pipefail

# Enable kernel modules required for Kubernetes networking and wireguard encryption
echo "Enabling kernel modules..."
modprobe overlay
modprobe br_netfilter
modprobe wireguard  # For encrypted inter-node traffic

# Configure sysctl for Kubernetes dual-stack networking
cat <<EOF > /etc/sysctl.d/42-kubernetes.conf
# IPv4 forwarding for pod routing
net.ipv4.ip_forward = 1

# IPv6 forwarding for dual-stack
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1

# Bridge netfilter for network policies (both IPv4 and IPv6)
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1

# Disable IPv6 privacy extensions (can interfere with pod networking)
net.ipv6.conf.all.use_tempaddr = 0
net.ipv6.conf.default.use_tempaddr = 0

# Accept router advertisements for proper IPv6 routing
net.ipv6.conf.all.accept_ra = 2
net.ipv6.conf.default.accept_ra = 2
EOF

sysctl --system

echo "✓ Kernel modules and network configuration ready"
