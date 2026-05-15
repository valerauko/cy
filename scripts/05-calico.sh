#!/usr/bin/env bash
set -euo pipefail

# Deploy Calico CNI using local declarative manifests
# Configured for dual-stack networking with wireguard encryption
# Run this on the control plane node after kubeadm init

MANIFESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../manifests/calico" && pwd)"

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
echo "Deploying Calico CNI (Declarative)"
echo "================================================"
echo ""
echo "Applying Calico manifests from: $MANIFESTS_DIR"
echo "Configuration:"
echo "  - Pod CIDR IPv4: 10.244.0.0/16 with wireguard"
echo "  - Pod CIDR IPv6: fd00:10:244::/108 with wireguard"
echo "  - Wireguard MTU: 1380"
echo ""

# Step 1: Apply CRDs
echo "[1/4] Applying Calico CustomResourceDefinitions..."
kubectl apply -f "$MANIFESTS_DIR/crds.yaml"
sleep 2

# Step 2: Apply ConfigMap and RBAC/Deployments
echo "[2/4] Applying ConfigMap, RBAC, and DaemonSets..."
kubectl apply -f "$MANIFESTS_DIR/config.yaml"
kubectl apply -f "$MANIFESTS_DIR/manifest.yaml"

# Step 3: Apply IP pools and wireguard configuration
echo "[3/4] Applying IP pools and wireguard configuration..."
kubectl apply -f "$MANIFESTS_DIR/ippools.yaml"

echo "[4/4] Waiting for Calico components to be ready..."

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
echo ""
echo "To customize IP pools, edit: $MANIFESTS_DIR/ippools.yaml"
echo "Then reapply with: kubectl apply -f $MANIFESTS_DIR/ippools.yaml"
