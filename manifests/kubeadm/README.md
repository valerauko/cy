# Kubernetes kubeadm Configuration

This directory contains kubeadm configuration files for cluster initialization.

## Files

### `init-config.yaml`

Kubeadm configuration for control plane initialization. Defines:

- **Dual-stack networking**: IPv4 + IPv6
  - Pod CIDR IPv4: `10.244.0.0/16` (node mask: `/26`)
  - Pod CIDR IPv6: `fd00:10:244::/108` (node mask: `/122`)
  - Service CIDR IPv4: `10.96.0.0/12`
  - Service CIDR IPv6: `fd00:10:96::/108`

- **Node CIDR mask sizes**:
  - IPv4: `/26` per node (supports 62 pods per node)
  - IPv6: `/122` per node (supports ~16K pods per node) — **must match Calico blockSize**

- **CRI socket**: `/var/run/crio/crio.sock` (CRI-O container runtime)

- **Control plane endpoint**: `163.44.115.241:6443` (hardcoded)

## Customization

To use different network settings:

1. Edit `init-config.yaml`:
   - Change `controlPlaneEndpoint` to match your control plane IP
   - Change `networking.podSubnet` and `networking.serviceSubnet` as needed
   - Adjust `node-cidr-mask-size-ipv4` and `node-cidr-mask-size-ipv6` if changing pod CIDR sizes

2. Update corresponding values in:
   - `scripts/04-init-control-plane.sh` (pod/service CIDR variables at top)
   - `manifests/calico/config.yaml` (control plane IPv6 for API discovery)
   - `manifests/calico/ippools.yaml` (IP pool CIDRs and blockSize)

## Usage

Referenced by `scripts/04-init-control-plane.sh`:

```bash
kubeadm init --config=manifests/kubeadm/init-config.yaml
```

Must be run from the cluster setup directory so the relative path resolves correctly.
