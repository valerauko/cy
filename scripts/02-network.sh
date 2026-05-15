#!/usr/bin/env bash
set -euo pipefail

cat <<EOF > /etc/sysctl.d/42-ip-forward.conf
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
EOF
