#!/usr/bin/env bash
set -euo pipefail

# Complete node setup in one go
# Run this FIRST on every node (control plane and workers)
# This executes steps 1-3 from the README

echo "================================================"
echo "Kubernetes 1.36 Node Preparation"
echo "================================================"
echo ""
echo "This script will:"
echo "  1. Install CRI-O 1.36 with crun"
echo "  2. Configure kernel networking"
echo "  3. Install Kubernetes packages"
echo ""
echo "After this completes, on the control plane run:"
echo "  sudo bash scripts/04-init-control-plane.sh <IP>"
echo "Then: sudo bash scripts/05-calico.sh"
echo ""

# Get the scripts directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Run all foundation scripts
echo "[1/3] Installing CRI-O..."
bash "$SCRIPT_DIR/01-crio.sh"

echo ""
echo "[2/3] Configuring kernel networking..."
bash "$SCRIPT_DIR/02-network.sh"

echo ""
echo "[3/3] Installing Kubernetes packages..."
bash "$SCRIPT_DIR/03-kubernetes.sh"

echo ""
echo "================================================"
echo "✓ Node preparation complete!"
echo "================================================"
echo ""
echo "Next steps:"
echo ""
echo "On control plane node:"
echo "  export CP_IP=<YOUR_CONTROL_PLANE_IP>"
echo "  sudo bash scripts/04-init-control-plane.sh \$CP_IP"
echo "  sudo bash scripts/05-calico.sh"
echo ""
echo "On worker nodes (after control plane is ready):"
echo "  sudo bash scripts/06-join-worker.sh '<TOKEN>' '<CONTROL_PLANE_IP>'"
echo ""
