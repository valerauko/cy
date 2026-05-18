# Container Yard

- Control Plane IPv4: `163.44.115.241`
- Control Plane IPv6: `2400:8500:2002:3318:163:44:115:241`
- Pod CIDR IPv4: `10.42.0.0/16` (node mask: `/26`)
- Pod CIDR IPv6: `fd00:cafe:42::/108` (node mask: `/122`)
- Service CIDR IPv4: `10.43.0.0/12`
- Service CIDR IPv6: `fd00:cafe:43::/108`

## Chosen Design

- k0s single-controller cluster
- API endpoint family default: IPv6 (`2400:8500:2002:3318:163:44:115:241`)
- CRI: CRI-O with `crun`
- CNI: Calico (k0s-managed), dual-stack, IPv6-primary
- Data plane trial: Calico eBPF (kube-proxy replacement)
- Encryption: Calico WireGuard
- Keep: CoreDNS, system-rbac, konnectivity
- Disable: `applier-manager,autopilot,helm,kube-proxy,metrics-server,update-prober,windows-node`

## Generated Files

- `k0s.yaml` - cluster configuration
- `scripts/install-crio-crun-ubuntu.sh` - install and configure CRI-O + crun
- `scripts/install-k0s-controller.sh` - install/start controller with disable-components
- `scripts/install-k0s-worker.sh` - install/start worker

## Bootstrapping

### 1) On every node: install CRI-O + crun

```bash
./scripts/install-crio-crun-ubuntu.sh
```

### 2) On the controller: install/start k0s

```bash
./scripts/install-k0s-controller.sh
```

### 3) On the controller: create a worker join token

```bash
sudo k0s token create --role=worker > worker.token
```

Copy `worker.token` to each worker.

### 4) On each worker: join cluster

```bash
./scripts/install-k0s-worker.sh ./worker.token
```

### 5) Verify

```bash
sudo k0s kubectl get nodes -o wide
sudo k0s kubectl get pods -A

# kube-proxy should be absent in eBPF mode
sudo k0s kubectl -n kube-system get ds kube-proxy

# confirm Calico is running and check eBPF log line
sudo k0s kubectl -n kube-system get pods -l k8s-app=calico-node
sudo k0s kubectl -n kube-system logs ds/calico-node | grep -E "BPF enabled|not supported" -m1
```

## Notes On kube-proxy and NAT

- This setup intentionally tries Calico eBPF mode and disables kube-proxy.
- eBPF mode needs VXLAN allowed between nodes for NodePort forwarding (UDP 4789 by default).
- If this trial is unstable, rollback is straightforward:

```bash
# 1) Re-enable kube-proxy in k0s
DISABLE_COMPONENTS="applier-manager,autopilot,helm,metrics-server,update-prober,windows-node" ./scripts/install-k0s-controller.sh

# 2) Disable Calico eBPF and restore iptables data plane
sudo k0s kubectl patch felixconfiguration default --type merge -p '{"spec":{"bpfEnabled":false}}'
```

After rollback, validate service traffic again and ensure kube-proxy DaemonSet exists.

- `CALICO_IPV6POOL_NAT_OUTGOING=true` (set in `k0s.yaml`) provides IPv6 SNAT for pod egress out of the pod CIDR.
- This does **not** provide IPv6-to-IPv4 translation. For IPv6-only hosts/nodes that must reach IPv4 destinations, you still need NAT64 (host-level or centralized gateway).

## In-Cluster NAT64 Options

- **Recommended tool:** Jool (`jool` + `jool_siit`/NAT64 mode) as a dedicated gateway workload.
- **Alternative:** TAYGA in a gateway pod/VM.

Practical guidance:

- Run NAT64 gateway pods on nodes that have both IPv6 and IPv4 internet reachability.
- Use `hostNetwork: true` and privileged/NET_ADMIN capabilities.
- Pair it with DNS64 so AAAA synthesis points IPv6-only clients to the NAT64 prefix (for example `64:ff9b::/96` or your own).
- Route that NAT64 prefix from worker nodes/pods to the gateway nodes.

Important limitation:

- NAT64 inside the cluster can solve **pod/workload** egress if routing/DNS64 are set correctly.
- It does **not** automatically solve host OS package-manager traffic on IPv6-only nodes unless host routing and DNS are also pointed at NAT64.

## Single-Gateway NAT64 (Jool + CoreDNS DNS64)

This repo now includes a single-gateway NAT64 path tailored for your topology (one public control node).

### Files

- `scripts/setup-jool-nat64-gateway.sh`
- `scripts/enable-coredns-dns64.sh`
- `scripts/configure-nat64-route-on-node.sh`

### Rollout

1) On the control node (gateway), install and start Jool NAT64:

```bash
./scripts/setup-jool-nat64-gateway.sh
```

This script now also installs and enables `jool-nat64.service`, so NAT64 comes back automatically after reboot.

2) Enable DNS64 in CoreDNS from a machine with cluster-admin `kubectl` context:

```bash
./scripts/enable-coredns-dns64.sh
```

3) On every node (controllers and workers), route NAT64 prefix via the gateway:

```bash
GATEWAY_V6=2400:8500:2002:3318:163:44:115:241 ./scripts/configure-nat64-route-on-node.sh
```

4) Validate from a pod:

```bash
sudo k0s kubectl run -it --rm test-v6 --image=busybox:1.36 --restart=Never -- sh
# Inside pod:
nslookup ipv4only.arpa
wget -O- http://example.com
```

### Rollback

1) Remove DNS64 (manually edit CoreDNS ConfigMap and remove `dns64` block), then restart CoreDNS:

```bash
sudo k0s kubectl -n kube-system edit configmap coredns
sudo k0s kubectl -n kube-system rollout restart deployment coredns
```

2) Remove NAT64 route on each node:

```bash
sudo ip -6 route del 64:ff9b::/96 || true
```

3) Stop Jool on gateway:

```bash
sudo jool instance remove nat64-main || true
sudo modprobe -r jool || true
```

4) Disable autostart service on gateway (optional):

```bash
sudo systemctl disable --now jool-nat64.service
sudo rm -f /etc/systemd/system/jool-nat64.service
sudo systemctl daemon-reload
```

### Notes

- Jool requires a kernel module on the gateway node; that is why gateway prep is host-level.
- DNS64 synthesis uses prefix `64:ff9b::/96` by default in this setup.

### Operations

- Check service status:

```bash
sudo systemctl status jool-nat64.service
```

- Restart Jool NAT64 service:

```bash
sudo systemctl restart jool-nat64.service
```

- Change prefix or instance name persistently:

```bash
sudoedit /etc/jool/nat64.env
sudo systemctl restart jool-nat64.service
```
