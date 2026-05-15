#!/usr/bin/env bash
set -euo pipefail

# Initialize the Kubernetes control plane with kubeadm
# Uses CIDRs and addresses that match manifests/calico/ippools.yaml and config.yaml
# Run this ONLY on the control plane node

# Hardcoded network configuration (must match manifests/calico/)
CONTROL_PLANE_IP="163.44.115.241"
CONTROL_PLANE_IPV6="2400:8500:2002:3318:163:44:115:241"

# Must match manifests/calico/ippools.yaml
POD_CIDR_IPV4="10.244.0.0/16"
POD_CIDR_IPV6="fd00:10:244::/108"
SERVICE_CIDR_IPV4="10.96.0.0/12"
SERVICE_CIDR_IPV6="fd00:10:96::/108"

echo "Initializing Kubernetes control plane..."
echo "Control plane IPv4: $CONTROL_PLANE_IP"
echo "Control plane IPv6: $CONTROL_PLANE_IPV6"
echo "Pod CIDR IPv4: $POD_CIDR_IPV4"
echo "Pod CIDR IPv6: $POD_CIDR_IPV6 (max /108)"
echo "Service CIDR IPv4: $SERVICE_CIDR_IPV4"
echo "Service CIDR IPv6: $SERVICE_CIDR_IPV6 (max /108)"
echo ""

# Install and configure kine with sqlite backend
echo "Setting up kine with sqlite backend..."
if ! command -v kine &> /dev/null; then
    echo "  Installing kine binary..."
    curl -sfL -o /usr/local/bin/kine --max-redirs 1 https://github.com/k3s-io/kine/releases/download/v0.15.0/kine-amd64
    chmod +x /usr/local/bin/kine
fi

# Create kine data directory
mkdir -p /var/lib/kine

# Install kine systemd service
echo "  Installing kine systemd service..."
cp manifests/kine/kine.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable kine.service
systemctl start kine.service

# Wait for kine to be ready (max 30 seconds)
echo "  Waiting for kine to be ready..."
for i in {1..30}; do
    if systemctl is-active --quiet kine.service && nc -z 127.0.0.1 2379 &> /dev/null; then
        echo "  ✓ Kine is ready"
        break
    fi
    sleep 1
    if [ $i -eq 30 ]; then
        echo "Error: kine failed to start within 30 seconds"
        systemctl status kine.service
        exit 1
    fi
done

# Pull required images first
kubeadm config images pull --kubernetes-version=1.36.0

# Initialize control plane with kubeadm config file
# IPv4: /26 per node (fits into /16), IPv6: /122 per node (fits into /108, matches Calico blockSize)
kubeadm init --config=manifests/kubeadm/init-config.yaml --ignore-preflight-errors=Mem

# Set up kubeconfig for root user
mkdir -p /root/.kube
cp /etc/kubernetes/admin.conf /root/.kube/config
chown root:root /root/.kube/config

echo ""
echo "✓ Control plane initialized successfully!"
echo ""
echo "Kine is installed and enabled as a systemd service"
echo "  Status: sudo systemctl status kine.service"
echo "  Logs: sudo journalctl -u kine.service -f"
echo ""
echo "Next steps:"
echo "1. Run: source <(kubectl completion bash)"
echo "2. Deploy Calico CNI: sudo bash scripts/05-calico.sh"
echo "3. Join data plane nodes using the token below"
echo ""
echo "To see the join command again, run:"
echo "  kubeadm token create --print-join-command"
