#!/usr/bin/env bash
set -euo pipefail

# Deploy Calico CNI using local declarative manifests
# Configured for dual-stack networking with wireguard encryption
# Run this on the control plane node after kubeadm init

CONTROL_PLANE_IPV6="${1:-}"
POD_CIDR_IPV6="${2:-fd00:10:244::/108}"
MANIFESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../manifests/calico" && pwd)"
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "kubectl not found. Please ensure Kubernetes is installed."
    exit 1
fi

# Verify cluster is ready
echo "Checking cluster status..."
if ! kubectl get nodes &> /dev/null; then
    echo "Cannot connect to cluster. Ensure control plane is initialized."
    exit 1
fi

echo "================================================"
echo "Deploying Calico CNI"
echo "================================================"
echo ""
echo "Configuration:"
echo "  Manifests: $MANIFESTS_DIR"
[[ -n "$CONTROL_PLANE_IPV6" ]] && echo "  Control Plane IPv6: $CONTROL_PLANE_IPV6"
echo "  IPv6 Pod CIDR: $POD_CIDR_IPV6 (max /108)"
echo ""

# Step 1: Patch Calico manifests for dual-stack + wireguard
echo "[1/3] Patching Calico configuration for dual-stack + wireguard..."
if [[ -f "$SCRIPTS_DIR/04a-patch-calico.sh" ]]; then
    bash "$SCRIPTS_DIR/04a-patch-calico.sh" "$CONTROL_PLANE_IPV6" "$POD_CIDR_IPV6"
else
    echo "Warning: Patch script not found. Skipping advanced configuration."
fi

# Step 2: Create Calico namespace and RBAC
echo "[2/3] Applying Calico manifests (CRDs, config, deployments)..."
kubectl apply -f "$MANIFESTS_DIR/crds.yaml"
sleep 2

# Step 3: Apply remaining manifests in order
kubectl apply -f "$MANIFESTS_DIR/config.yaml"
kubectl apply -f "$MANIFESTS_DIR/manifest.yaml"

# Apply custom IP pools and wireguard configuration
if [[ -f "$MANIFESTS_DIR/ippools.yaml" ]]; then
    echo "  Applying IP pools and wireguard configuration..."
    kubectl apply -f "$MANIFESTS_DIR/ippools.yaml"
fi

echo ""
echo "[3/3] Waiting for Calico components to be ready..."

# Wait for Calico node DaemonSet to be ready (if it exists)
if kubectl get daemonset -n kube-system calico-node &>/dev/null; then
    echo "  Waiting for calico-node daemonset..."
    kubectl rollout status daemonset/calico-node -n kube-system --timeout=300s 2>/dev/null || {
        echo "  Calico node still initializing. Check status with:"
        echo "    kubectl get pods -n kube-system -l k8s-app=calico-node -w"
    }
fi

# Wait for Calico kube-controllers
if kubectl get deployment -n kube-system calico-kube-controllers &>/dev/null; then
    echo "  Waiting for calico-kube-controllers deployment..."
    kubectl rollout status deployment/calico-kube-controllers -n kube-system --timeout=300s 2>/dev/null || true
fi

echo ""
echo "================================================"
echo "✓ Calico CNI deployment complete!"
echo "================================================"
echo ""
echo "Verify installation:"
echo "  kubectl get pods -n kube-system -l k8s-app=calico-node"
echo "  kubectl get nodes -o wide"
echo ""
echo "Check wireguard status on nodes:"
echo "  sudo ip link show type wireguard"
echo "  sudo wg show"
echo ""
echo "View IP pool configuration:"
echo "  kubectl get ippools"
echo "  kubectl describe ippool default-ipv4-ippool"
echo "  kubectl describe ippool default-ipv6-ippool"
