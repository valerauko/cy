#!/usr/bin/env bash
set -euo pipefail

# Run this on every cluster node (including the gateway itself).
# It ensures traffic for the NAT64 prefix reaches the gateway node.

NAT64_PREFIX="${NAT64_PREFIX:-64:ff9b::/96}"
GATEWAY_V6="${GATEWAY_V6:-2400:8500:2002:3318:163:44:115:241}"

# Replace if route exists, add if it doesn't.
sudo ip -6 route replace "${NAT64_PREFIX}" via "${GATEWAY_V6}"

ip -6 route show "${NAT64_PREFIX}"
