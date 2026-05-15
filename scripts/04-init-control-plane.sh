#!/usr/bin/env bash
set -euo pipefail

# Initialize the Kubernetes control plane with kubeadm
# Uses CIDRs that match manifests/calico/ippools.yaml
# Run this ONLY on the control plane node

CONTROL_PLANE_IP="${1:-}"
CONTROL_PLANE_IPV6="${2:-}"

# Must match manifests/calico/ippools.yaml
POD_CIDR_IPV4="10.244.0.0/16"
POD_CIDR_IPV6="fd00:10:244::/108"
SERVICE_CIDR_IPV4="10.96.0.0/12"
SERVICE_CIDR_IPV6="fd00:10:96::/108"

if [[ -z "$CONTROL_PLANE_IP" ]]; then
    echo "Usage: $0 <CONTROL_PLANE_IP_V4> [CONTROL_PLANE_IP_V6]"
    echo ""
    echo "Examples:"
    echo "  IPv4 only:"
    echo "    $0 192.168.1.10"
    echo ""
    echo "  Dual-stack (IPv4 + IPv6):"
    echo "    $0 192.168.1.10 2001:db8::10"
    echo ""
    echo "Note: Pod and service CIDRs are fixed to match manifests/calico/ippools.yaml:"
    echo "  Pod CIDR IPv4: $POD_CIDR_IPV4"
    echo "  Pod CIDR IPv6: $POD_CIDR_IPV6"
    echo "  Service CIDR IPv4: $SERVICE_CIDR_IPV4"
    echo "  Service CIDR IPv6: $SERVICE_CIDR_IPV6"
    echo ""
    echo "To use different CIDRs, edit this script and manifests/calico/ippools.yaml"
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
