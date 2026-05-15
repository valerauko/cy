# Container Yard

A lightweight, fully-customizable Kubernetes 1.36 cluster using **kubeadm**, **CRI-O**, **Calico**, and **Wireguard** for encrypted networking.

**Why this approach?** Unlike k0s and k3s, kubeadm provides full control over every component without hidden abstractions, making it ideal for learning and customization. Wireguard provides transparent encryption for inter-node traffic without operational overhead.

## Architecture

| Component | Version | Purpose |
|-----------|---------|---------|
| **Kubernetes** | 1.36 | Orchestration |
| **kubeadm** | 1.36 | Cluster initialization |
| **CRI-O** | 1.36 | Container runtime (with crun) |
| **Calico** | 3.29 | Network policy & CNI with declarative manifests |
| **Wireguard** | Kernel module | Encrypted tunnel for inter-node traffic |
| **Networking** | Dual-stack | IPv4 + IPv6 with /64 per node |
| **OS** | Ubuntu 26.04 | Host OS with wireguard kernel support |

## Prerequisites

- **Hardware:** Each node needs ≥2 CPUs, ≥2GB RAM
- **Network:** All nodes have wireguard kernel module support (Ubuntu 26.04 standard)
- **Network separation:** Nodes can be on different physical networks (wireguard tunnels traffic)
- **Sudo access** on all nodes
- **No swap** (Kubernetes requirement — disable if present)
- **IPv6 addressing:** Each node should have an IPv6 address or address pool assigned
- **IPv6 CIDR constraints:** If using dual-stack, pod and service CIDRs must be ≤/108 (smaller ranges cause silent failure)

## Quick Start

### Step 1: Prepare All Nodes

Run these scripts on **every node** (control plane + data plane):

**Option A: Run individually** (for debugging/understanding):
```bash
sudo bash scripts/01-crio.sh
sudo bash scripts/02-network.sh
sudo bash scripts/03-kubernetes.sh
```

**Option B: All at once** (recommended for quick setup):
```bash
sudo bash scripts/00-prepare-node.sh
```

After these complete, verify CRI-O and wireguard are ready:
```bash
sudo systemctl status crio
sudo crictl ps  # Should work without errors
sudo modprobe wireguard && echo "✓ Wireguard ready"
```

### Step 2: Initialize Control Plane

On the **control plane node only**, run:

```bash
# IPv4-only
export CP_IP=192.168.1.10
sudo bash scripts/04-init-control-plane.sh $CP_IP

# Or dual-stack (IPv4 + IPv6)
export CP_IP=192.168.1.10
export CP_IPV6=2001:db8::10
sudo bash scripts/04-init-control-plane.sh $CP_IP $CP_IPV6
```

**CIDRs are fixed** to match `manifests/calico/ippools.yaml`:
- Pod CIDR IPv4: `10.244.0.0/16`
- Pod CIDR IPv6: `fd00:10:244::/108`
- Service CIDR IPv4: `10.96.0.0/12`
- Service CIDR IPv6: `fd00:10:96::/108`

To use different CIDRs, edit both:
- `scripts/04-init-control-plane.sh` (control plane CIDR variables)
- `manifests/calico/ippools.yaml` (Calico IP pools)

**Save the join token** from the output — you'll need it for data plane nodes.

### Step 3: Deploy Calico CNI with Wireguard

On the **control plane node** only:

```bash
sudo bash scripts/05-calico.sh
```

This applies the declarative Calico manifests from `manifests/calico/` and configures:
- ✓ Wireguard encryption for all inter-node traffic
- ✓ IPv4 and IPv6 pod networks
- ✓ /108 IPv6 pod network (safe maximum — larger ranges may fail silently)

**Defaults applied:**
- IPv4 pod CIDR: `10.244.0.0/16`
- IPv6 pod CIDR: `fd00:10:244::/108`
- Service IP blocks: Auto-managed by kubeadm

Verify all components are ready:
```bash
kubectl get nodes  # Should show control plane as Ready (after ~1-2 min)
kubectl get pods -n kube-system -l k8s-app=calico-node
kubectl describe ippool default-ipv4-ippool  # Check wireguard config
```

### Step 4: Join Data Plane Nodes (Optional)

On each **data plane node**, run:

```bash
# Get this from control plane output or run: kubeadm token create --print-join-command
sudo bash scripts/06-join-worker.sh '<TOKEN>' '<CONTROL_PLANE_IP>'
```

Wait for nodes to join and wireguard tunnels to establish:
```bash
# On control plane
kubectl get nodes -w

# On a data plane node, verify wireguard tunnel
sudo ip link show type wireguard
sudo wg show
```

## Network Architecture

### Dual-Stack (IPv4 + IPv6)

**IPv4 Pod Network:**
- CIDR: `10.244.0.0/16`
- Block size: `/26` per node
- Encapsulation: Wireguard
- Nat Outgoing: Enabled

**IPv6 Pod Network (if enabled):**
- CIDR: `fd00:10:244::/108` (default, customizable — **max /108**)
- Block size: `/122` (combines to `/64` per node, but constrained by parent /108 limit)
- Encapsulation: Wireguard
- Nat Outgoing: Disabled (IPv6 has built-in address uniqueness)
- **Note:** Kubernetes IPv6 support has practical limits; /108 is the safe maximum (tested constraint)

### Wireguard Encryption

All inter-node traffic is encrypted via Wireguard:
- **MTU adjusted:** 1380 bytes (accounts for wireguard overhead of ~80 bytes)
- **Transparent:** No application changes required
- **Automatic:** Calico manages key exchange and peer discovery
- **Verification:**
  ```bash
  sudo ip link show type wireguard
  sudo wg show
  ```

### Network-Separated Nodes

Nodes can be on completely different networks (e.g., different subnets, sites, clouds):
- Wireguard creates encrypted tunnels between nodes
- Calico's BIRD BGP handles routing across wireguard links
- IPv6 addresses should be unique per node; IPv4 is automatic per /26 block

## IPv6 CIDR Constraints

Kubernetes has practical limits on IPv6 CIDR sizes that differ from theoretical maximums:

| Parameter | Limit | Reason |
|-----------|-------|--------|
| **Pod CIDR** | ≤/108 | Larger ranges (e.g., /56, /48) cause silent cluster failure |
| **Service CIDR** | ≤/108 | Constraint observed in k0s; applies to kubeadm |
| **Per-node block** | /122 | Combines to /64 per node (2^(108-122) = 16384 pods max per node) |

**Defaults used:**
- Pod CIDR: `fd00:10:244::/108`
- Service CIDR: `fd00:10:96::/108`

If you need more addresses:
- Use multiple pod pools (e.g., `fd00:10:244::/108` and `fd00:10:245::/108`)
- Increase node count rather than expanding single CIDR
- Consider IPv4-only if IPv6 constraints are problematic

## Calico Configuration (Fully Declarative)

All Calico configuration is stored as static manifests in `manifests/calico/`:

- **crds.yaml** — Calico CustomResourceDefinitions
- **config.yaml** — ConfigMap with CNI and BIRD configuration (uses Kubernetes DNS for API discovery)
- **manifest.yaml** — DaemonSets, Deployments, and RBAC
- **ippools.yaml** — IPv4 and IPv6 IP pools with wireguard configuration

**Customizable settings** (after cluster init):
- Encapsulation type (Wireguard/VXLan/IPIPCrossSubnet)
- Wireguard MTU and threading
- Nat Outgoing behavior

**Fixed settings** (must match at init time):
- Pod and service CIDRs (configured in both `04-init-control-plane.sh` and `ippools.yaml`)

**To modify after cluster init:**
1. Edit `manifests/calico/ippools.yaml`
2. Apply: `kubectl apply -f manifests/calico/ippools.yaml`

**To change CIDRs** (requires cluster reset):
1. Edit both `scripts/04-init-control-plane.sh` and `manifests/calico/ippools.yaml`
2. Reset cluster and reinitialize

## Useful Commands

### Cluster Status
```bash
kubectl get nodes -o wide
kubectl get pods -A
```

### Container Runtime (CRI-O)
```bash
sudo crictl ps
sudo crictl pods
sudo systemctl status crio
sudo journalctl -u crio -f
```

### Kubelet Status
```bash
sudo systemctl status kubelet
sudo journalctl -u kubelet -f
```

### Calico & Networking
```bash
# View node IP assignments
kubectl get nodes -o custom-columns=NAME:.metadata.name,PODS:.spec.podCIDR,PODS6:.spec.podCIDRs

# Check IP pools
kubectl get ippools
kubectl describe ippool default-ipv4-ippool
kubectl describe ippool default-ipv6-ippool

# Verify wireguard
sudo ip link show type wireguard
sudo wg show
sudo wg set wg0 peer <public-key> endpoint <ip>:<port>  # Manual config if needed

# View Calico nodes
calicoctl get nodes
calicoctl get ippool

# BIRD BGP status (inside calico-node pod)
kubectl exec -it -n kube-system ds/calico-node -- /bin/bash
birdcl> show status
birdcl> show protocols
```

### Debugging
```bash
# Pod scheduling issues
kubectl describe pod <POD> -n <NS>
kubectl logs <POD> -n <NS>

# Node issues
kubectl describe node <NODE>
kubectl logs -n kube-system -l k8s-app=calico-node --tail=50

# Test connectivity
kubectl run -it --rm debug --image=busybox --restart=Never -- sh
# Inside pod: ping <service-ip>, nc <service-ip> <port>
```

## Customization

### Change Pod Network CIDR

Pod and service CIDRs are **fixed** to maintain consistency between kubeadm and Calico. To change them:

1. **Edit kubeadm init script:**
   ```bash
   nano scripts/04-init-control-plane.sh
   # Update POD_CIDR_IPV4, POD_CIDR_IPV6, SERVICE_CIDR_IPV4, SERVICE_CIDR_IPV6
   ```

2. **Edit Calico manifests:**
   ```bash
   nano manifests/calico/ippools.yaml
   # Update cidr field in both IPPool resources
   ```

3. **Re-initialize cluster:**
   ```bash
   # Start fresh (kubeadm reset, etc.)
   sudo bash scripts/04-init-control-plane.sh <CP_IP> [CP_IPV6]
   sudo bash scripts/05-calico.sh
   ```

**Important constraints:**
- Pod CIDR IPv6 must be ≤/108 (larger ranges may cause silent cluster failure)
- Service CIDR IPv6 must be ≤/108
- Both kubeadm and Calico must use the same CIDRs

### Change Encapsulation (Wireguard → VXLan)

Edit `manifests/calico/ippools.yaml`, change `encapsulation` in the IPPool resources:

```yaml
apiVersion: crd.projectcalico.org/v1
kind: IPPool
metadata:
  name: default-ipv4-ippool
spec:
  encapsulation: VXLan        # Changed from Wireguard
  # ... rest of config
```

Then reapply without cluster reset:
```bash
kubectl apply -f manifests/calico/ippools.yaml
```

**Supported encapsulations:**
- `Wireguard` — Encrypted inter-node traffic (default, best performance)
- `VXLan` — Unencrypted VXLAN tunneling
- `IPIPCrossSubnet` — IP-in-IP for cross-subnet traffic only

### Adjust Wireguard MTU

Edit `manifests/calico/ippools.yaml`, update the FelixConfiguration:
```yaml
apiVersion: crd.projectcalico.org/v1
kind: FelixConfiguration
metadata:
  name: default
spec:
  wireguardEnabled: true
  wireguardMTUOverride: 1380  # Adjust based on your network
```

Then reapply: `kubectl apply -f manifests/calico/ippools.yaml`

### Disable Nat Outgoing (for external routing)

Edit `manifests/calico/ippools.yaml`, change for each pool:
```yaml
natOutgoing: Disabled
```

Then reapply: `kubectl apply -f manifests/calico/ippools.yaml`

### Adjust Kubelet Settings
```bash
# Edit kubelet extra args
sudo nano /etc/default/kubelet
# Example: KUBELET_EXTRA_ARGS="--max-pods=50 --cpu-cfs-quota=false"

sudo systemctl restart kubelet
```

### Use Different CRI-O Version
Edit [scripts/01-crio.sh](scripts/01-crio.sh), change `CRIO_VERSION`:
```bash
CRIO_VERSION="v1.37"  # Or v1.35, v1.34, etc.
```

### Use Different Kubernetes Version
Edit [scripts/03-kubernetes.sh](scripts/03-kubernetes.sh) and [scripts/04-init-control-plane.sh](scripts/04-init-control-plane.sh):
```bash
K8S_VERSION="1.37"
kubelet=1.37.0-1.1 kubeadm=1.37.0-1.1 kubectl=1.37.0-1.1
--kubernetes-version=1.37.0
```

## Troubleshooting

### Nodes Stuck in "NotReady"

**Check kubelet:**
```bash
sudo systemctl status kubelet
sudo journalctl -u kubelet -n 50
```

**Check CRI-O:**
```bash
sudo systemctl status crio
sudo crictl ps
```

**Check Calico pods:**
```bash
kubectl get pods -n kube-system -l k8s-app=calico-node
kubectl logs -n kube-system -l k8s-app=calico-node --tail=50
```

### Pods Not Getting IPs

**Check IP pools:**
```bash
kubectl get ippools
kubectl get nodes -o custom-columns=NAME:.metadata.name,PODS:.spec.podCIDR
```

**Check IPAM daemon:**
```bash
kubectl logs -n kube-system -l k8s-app=calico-node -c install-cni --tail=50
```

### Wireguard Not Connecting

**Check tunnel is created:**
```bash
sudo ip link show type wireguard
sudo wg show
```

**Check Felix logs (inside calico-node pod):**
```bash
kubectl exec -it -n kube-system <calico-node-pod> -- \
    tail -f /var/log/calico/felix/felix.log
```

**Verify kernel support:**
```bash
modprobe wireguard && echo "OK"
```

### Certificate Issues

**Renew kubeadm certs:**
```bash
sudo kubeadm certs renew all
sudo systemctl restart kubelet
```

## Performance Tuning

**For single-node testing:**
- Disable swap
- Use `--max-pods=10` for limited resources
- Monitor with `kubectl top nodes`

**For multi-node production:**
- Use wireguard MTU 1380 (or auto-detect)
- Monitor BGP peers: `calicoctl get bgppeers`
- Enable IP cache in Felix: `birdcl> set memcache on`
- Consider `metrics-server` and `prometheus` for monitoring

## File Structure

```
cy/
├── scripts/
│   ├── 00-prepare-node.sh         # All-in-one node prep
│   ├── 01-crio.sh                 # Install CRI-O
│   ├── 02-network.sh              # Kernel config + wireguard
│   ├── 03-kubernetes.sh           # Install kubeadm/kubelet
│   ├── 04-init-control-plane.sh   # Init control plane (dual-stack)
│   ├── 05-calico.sh               # Deploy Calico (declarative manifests)
│   └── 06-join-worker.sh          # Join data plane nodes
└── manifests/
    └── calico/
        ├── crds.yaml              # CustomResourceDefinitions
        ├── config.yaml            # ConfigMap (CNI + BIRD)
        ├── manifest.yaml          # DaemonSets & Deployments
        └── ippools.yaml           # IP pools & wireguard configuration (static)
```
```

### Certificate issues
```bash
# Renew certificates (on control plane)
sudo kubeadm certs renew all
sudo systemctl restart kubelet
```

## Performance Tuning

For minimal footprint (single-node lab):
- Disable swap completely
- Use `--max-pods` flag if needed (default: 110)
- Consider `--kubelet-extra-args` for resource constraints

For multi-node production-like setup:
- Use `--apiserver-advertise-address` for HA
- Set up etcd backup regularly
- Monitor with `metrics-server` and `prometheus`
