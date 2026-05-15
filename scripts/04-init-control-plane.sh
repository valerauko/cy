#!/usr/bin/env bash
set -euo pipefail

# Initialize the Kubernetes control plane with kubeadm
# Supports dual-stack (IPv4 + IPv6) networking with wireguard encryption
# Run this ONLY on the control plane node

CONTROL_PLANE_IP="${1:-}"
CONTROL_PLANE_IPV6="${2:-}"
POD_CIDR_IPV4="10.244.0.0/16"
POD_CIDR_IPV6="${3:-fd00:10:244::/108}"  # /108 for IPv6 pod network (safe upper limit)
SERVICE_CIDR_IPV4="10.96.0.0/12"
SERVICE_CIDR_IPV6="${4:-fd00:10:96::/108}"  # /108 for IPv6 service network (safe upper limit)

if [[ -z "$CONTROL_PLANE_IP" ]]; then
    echo "Usage: $0 <CONTROL_PLANE_IP_V4> [CONTROL_PLANE_IP_V6] [POD_CIDR_V6] [SERVICE_CIDR_V6]"
    echo ""
    echo "Examples:"
    echo "  IPv4 only:"
    echo "    $0 192.168.1.10"
    echo ""
    echo "  Dual-stack (IPv4 + IPv6):"
    echo "    $0 192.168.1.10 2001:db8::10"
    echo ""
    echo "  Custom CIDRs (note: max /108 for both pod and service):"
    echo "    $0 192.168.1.10 2001:db8::10 fd00:10:244::/108 fd00:10:96::/108"
    exit 1
fi

echo "Initializing Kubernetes control plane..."
echo "Control plane IPv4: $CONTROL_PLANE_IP"
[[ -n "$CONTROL_PLANE_IPV6" ]] && echo "Control plane IPv6: $CONTROL_PLANE_IPV6"
echo "Pod CIDR IPv4: $POD_CIDR_IPV4"
echo "Pod CIDR IPv6: $POD_CIDR_IPV6 (max /108)"
echo "Service CIDR IPv4: $SERVICE_CIDR_IPV4"
echo "Service CIDR IPv6: $SERVICE_CIDR_IPV6 (max /108)"
echo ""

# Pull required images first
kubeadm config images pull --kubernetes-version=1.36.0

# Build kubeadm init command with dual-stack support
KUBEADM_CMD="kubeadm init \
    --kubernetes-version=1.36.0 \
    --control-plane-endpoint=$CONTROL_PLANE_IP \
    --cri-socket=unix:///var/run/crio/crio.sock"

# Add IPv4 CIDRs
KUBEADM_CMD="$KUBEADM_CMD \
    --pod-network-cidr=$POD_CIDR_IPV4 \
    --service-cidr=$SERVICE_CIDR_IPV4"

# Add IPv6 CIDRs if provided
if [[ -n "$CONTROL_PLANE_IPV6" ]]; then
    KUBEADM_CMD="$KUBEADM_CMD \
        --pod-network-cidr=$POD_CIDR_IPV4,$POD_CIDR_IPV6 \
        --service-cidr=$SERVICE_CIDR_IPV4,$SERVICE_CIDR_IPV6"
fi

# Initialize control plane
eval "$KUBEADM_CMD"

# Set up kubeconfig for root user
mkdir -p /root/.kube
cp /etc/kubernetes/admin.conf /root/.kube/config
chown root:root /root/.kube/config

echo ""
echo "✓ Control plane initialized successfully!"
echo ""
echo "Next steps:"
echo "1. Run: source <(kubectl completion bash)"
echo "2. Configure Calico with wireguard: bash /path/to/05-calico.sh"
echo "3. Join data plane nodes using the token below"
echo ""
echo "To see the join command again, run:"
echo "  kubeadm token create --print-join-command"
