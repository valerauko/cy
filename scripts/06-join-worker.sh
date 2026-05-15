#!/usr/bin/env bash
set -euo pipefail

# Join a data plane node to an existing Kubernetes cluster
# Supports wireguard-encrypted dual-stack networking
# Run this script on data plane nodes AFTER running 00-prepare-node.sh or 01-03 scripts

JOIN_TOKEN="${1:-}"
CONTROL_PLANE_IP="${2:-}"
CONTROL_PLANE_PORT="${3:-6443}"

if [[ -z "$JOIN_TOKEN" || -z "$CONTROL_PLANE_IP" ]]; then
    echo "Usage: $0 <JOIN_TOKEN> <CONTROL_PLANE_IP> [CONTROL_PLANE_PORT]"
    echo ""
    echo "Example:"
    echo "  $0 'kubeadm join ...' 192.168.1.10"
    echo ""
    echo "Get the join token on control plane:"
    echo "  kubeadm token create --print-join-command"
    exit 1
fi

echo "Joining data plane node to cluster..."
echo "Control plane: $CONTROL_PLANE_IP:$CONTROL_PLANE_PORT"

# Join the cluster
kubeadm join "$CONTROL_PLANE_IP:$CONTROL_PLANE_PORT" \
    --token "$JOIN_TOKEN" \
    --cri-socket=unix:///var/run/crio/crio.sock \
    --discovery-token-unsafe-skip-ca-verification

echo ""
echo "✓ Data plane node joined successfully!"
echo ""
echo "Verify on control plane:"
echo "  kubectl get nodes -o wide"
echo ""
echo "Check wireguard connectivity:"
echo "  sudo ip link show type wireguard"
echo "  sudo wg show"
