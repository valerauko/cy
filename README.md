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

### Step 2: Initialize Control Plane (IPv4-only)

On the **control plane node only**, run:

```bash
export CP_IP=192.168.1.10  # Your control plane IP
sudo bash scripts/04-init-control-plane.sh $CP_IP
```

**Or for dual-stack (IPv4 + IPv6):**

```bash
export CP_IP=192.168.1.10
export CP_IPV6=2001:db8::10
sudo bash scripts/04-init-control-plane.sh $CP_IP $CP_IPV6 fd00:10:244::/108 fd00:10:96::/108
```

Arguments:
- `$CP_IP` — Control plane IPv4 address
- `$CP_IPV6` — Control plane IPv6 address (optional for dual-stack)
- IPv6 pod CIDR — Pod network range. Default: `fd00:10:244::/108` (**max /108** — larger ranges may cause silent failure)
- IPv6 service CIDR — Service network range. Default: `fd00:10:96::/108` (**max /108** — constraint observed in k0s, applies to kubeadm)

**Save the join token** from the output — you'll need it for data plane nodes.

### Step 3: Deploy Calico CNI with Wireguard

On the **control plane node** only:

```bash
# IPv4-only:
sudo bash scripts/05-calico.sh

# Or with dual-stack IPv6:
sudo bash scripts/05-calico.sh 2001:db8::10 fd00:10:244::/108
```

This applies the declarative Calico manifests from `manifests/calico/` and configures:
- ✓ Wireguard encryption for all inter-node traffic
- ✓ IPv4 and IPv6 pod networks (if dual-stack)
- ✓ /108 IPv6 pod network (safe maximum — larger ranges may fail silently)

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

## Calico Configuration (Declarative)

All Calico configuration is stored as manifests in `manifests/calico/`:

- **crds.yaml** — Calico CustomResourceDefinitions
- **config.yaml** — ConfigMap with CNI and BIRD configuration
- **manifest.yaml** — DaemonSets, Deployments, and RBAC
- **ippools.yaml** — Generated by `04a-patch-calico.sh` (IPv4 + IPv6 pools, wireguard)

**To modify Calico settings:**
1. Edit manifests in `manifests/calico/`
2. Run `04a-patch-calico.sh` to generate IP pools and wireguard config
3. Apply with `kubectl apply -f manifests/calico/`

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
The default CIDRs can be overridden at init time:

```bash
# IPv4-only (default)
sudo bash scripts/04-init-control-plane.sh 192.168.1.10

# Custom IPv4 CIDR (edit script directly)
# Edit scripts/04-init-control-plane.sh, change POD_CIDR_IPV4 and SERVICE_CIDR_IPV4

# Dual-stack with custom CIDRs (note: max /108 for IPv6)
sudo bash scripts/04-init-control-plane.sh \
    192.168.1.10 \
    2001:db8::10 \
    fd00:10:244::/108 \
    fd00:10:96::/108
```

Then ensure Calico's IP pools match:
```bash
sudo bash scripts/05-calico.sh 2001:db8::10 fd00:10:244::/108
```

**⚠️ Important:** IPv6 CIDR sizes are constrained:
- **Pod CIDR:** Must be ≤/108 (larger ranges may cause silent cluster failure)
- **Service CIDR:** Must be ≤/108

### Disable Wireguard (use VXLan instead)
Edit `manifests/calico/ippools.yaml`, change:
```yaml
encapsulation: Wireguard
```
to:
```yaml
encapsulation: VXLan
```

Then run: `kubectl apply -f manifests/calico/ippools.yaml`

### Adjust Wireguard MTU
Edit `scripts/04a-patch-calico.sh`, change `wireguardMTUOverride`:
```yaml
wireguardMTUOverride: 1380  # Adjust based on your network
```

### Disable Nat Outgoing (for external routing)
Edit `manifests/calico/ippools.yaml`, change:
```yaml
natOutgoing: Enabled
```
to:
```yaml
natOutgoing: Disabled
```

Then run: `kubectl apply -f manifests/calico/ippools.yaml`

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
│   ├── 04a-patch-calico.sh        # Patch for wireguard + IPv6
│   ├── 05-calico.sh               # Deploy Calico (declarative)
│   └── 06-join-worker.sh          # Join data plane nodes
└── manifests/
    └── calico/
        ├── crds.yaml              # CustomResourceDefinitions
        ├── config.yaml            # ConfigMap (CNI + BIRD)
        ├── manifest.yaml          # DaemonSets & Deployments
        └── ippools.yaml           # Generated by patch script
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
