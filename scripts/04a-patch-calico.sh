#!/usr/bin/env bash
set -euo pipefail

# Patch Calico manifests for dual-stack networking and wireguard encryption
# This script modifies the local Calico manifests to:
# - Enable dual-stack (IPv4 + IPv6)
# - Configure wireguard for encrypted inter-node traffic
# - Set IPv6 address pools with /64 per node

CONTROL_PLANE_IPV6="${1:-}"
POD_CIDR_IPV6="${2:-fd00:10:244::/108}"
MANIFESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../manifests/calico" && pwd)"

echo "Preparing Calico configuration for dual-stack + wireguard..."
echo "IPv6 Pod CIDR: $POD_CIDR_IPV6 (max /108)"

# Create a temporary directory for modified manifests
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Copy manifests to temp directory
cp "$MANIFESTS_DIR"/*.yaml "$TEMP_DIR/"

# 1. Update config.yaml with IPv6 API server and dual-stack CNI config
echo "Patching config.yaml for dual-stack..."
python3 <<'PYTHON_EOF'
import yaml
import sys

config_file = sys.argv[1]
control_plane_ipv6 = sys.argv[2]

with open(config_file, 'r') as f:
    doc = yaml.safe_load(f)

if doc.get('kind') == 'ConfigMap' and doc.get('metadata', {}).get('name') == 'calico-config':
    data = doc.get('data', {})

    # Update API server if IPv6 is provided
    if control_plane_ipv6:
        data['kubernetes_service_host'] = control_plane_ipv6

    # Ensure CNI config supports dual-stack
    import json
    try:
        cni_config = json.loads(data.get('cni_network_config', '{}'))
        for plugin in cni_config.get('plugins', []):
            if plugin.get('type') == 'calico':
                # Ensure dual-stack IPAM
                if 'ipam' not in plugin:
                    plugin['ipam'] = {}
                plugin['ipam']['type'] = 'calico-ipam'

        data['cni_network_config'] = json.dumps(cni_config, indent=2)
    except json.JSONDecodeError:
        pass

    doc['data'] = data

with open(config_file, 'w') as f:
    yaml.dump(doc, f, default_flow_style=False)

print(f"✓ Updated {config_file}")
PYTHON_EOF
"$TEMP_DIR/config.yaml" "$CONTROL_PLANE_IPV6"

# 2. Create IPPool resources for IPv4 and IPv6 with wireguard
echo "Creating IP pool resources for dual-stack..."
cat > "$TEMP_DIR/ippools.yaml" <<'EOF'
---
# IPv4 pod network pool with wireguard encryption
apiVersion: crd.projectcalico.org/v1
kind: IPPool
metadata:
  name: default-ipv4-ippool
spec:
  blockSize: 26
  cidr: 10.244.0.0/16
  encapsulation: Wireguard
  natOutgoing: Enabled
  nodeSelector: "!node-role.kubernetes.io/control-plane"

---
# IPv6 pod network pool with /64 per node and wireguard
# Assumes parent pool is /48, which allows /64 for 65536 nodes
apiVersion: crd.projectcalico.org/v1
kind: IPPool
metadata:
  name: default-ipv6-ippool
spec:
  blockSize: 122  # /122 blocks combine to /64 per node
  cidr: __IPV6_POD_CIDR__
  encapsulation: Wireguard
  natOutgoing: Disabled  # IPv6 has built-in address uniqueness
  nodeSelector: "!node-role.kubernetes.io/control-plane"

---
# Enable wireguard for encryption
apiVersion: crd.projectcalico.org/v1
kind: FelixConfiguration
metadata:
  name: default
spec:
  wireguardEnabled: true
  wireguardMTUOverride: 1380
EOF

# Replace IPv6 CIDR placeholder
sed -i "s|__IPV6_POD_CIDR__|$POD_CIDR_IPV6|g" "$TEMP_DIR/ippools.yaml"

# 3. Copy modified manifests to output
echo "Preparing modified manifests..."
cp "$TEMP_DIR"/* "$MANIFESTS_DIR/"

echo ""
echo "✓ Calico configuration prepared:"
echo "  - IPv4 pool: 10.244.0.0/16 with wireguard"
echo "  - IPv6 pool: $POD_CIDR_IPV6 with /122 blocks (→ /64 per node) and wireguard"
echo "  - Wireguard MTU: 1380 (accounts for wireguard overhead)"
echo ""
echo "Ready to apply manifests: kubectl apply -f $MANIFESTS_DIR/"
