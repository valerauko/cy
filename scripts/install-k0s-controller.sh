#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

K0S_VERSION="${K0S_VERSION:-v1.35.4+k0s.0}"
CRI_SOCKET="${CRI_SOCKET:-remote:unix:///var/run/crio/crio.sock}"
CONFIG_FILE="${CONFIG_FILE:-/etc/k0s/k0s.yaml}"
DISABLE_COMPONENTS="${DISABLE_COMPONENTS:-applier-manager,autopilot,helm,kube-proxy,metrics-server,update-prober,windows-node}"

curl -sSLf https://get.k0s.sh | sudo K0S_VERSION="${K0S_VERSION}" sh

sudo install -d -m 0755 /etc/k0s
sudo cp "${REPO_ROOT}/k0s.yaml" "${CONFIG_FILE}"

sudo k0s install controller \
  --cri-socket="${CRI_SOCKET}" \
  --disable-components="${DISABLE_COMPONENTS}" \
  -c "${CONFIG_FILE}"

sudo k0s start

sleep 2
sudo k0s status

echo
echo "Create a worker token with:"
echo "  sudo k0s token create --role=worker > worker.token"
