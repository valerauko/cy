#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <token-file>"
  exit 1
fi

TOKEN_FILE="$1"
K0S_VERSION="${K0S_VERSION:-v1.36.0+k0s.0}"
CRI_SOCKET="${CRI_SOCKET:-remote:unix:///var/run/crio/crio.sock}"

if [[ ! -f "${TOKEN_FILE}" ]]; then
  echo "Token file not found: ${TOKEN_FILE}"
  exit 1
fi

curl -sSLf https://get.k0s.sh | sudo K0S_VERSION="${K0S_VERSION}" sh

sudo k0s install worker \
  --token-file "${TOKEN_FILE}" \
  --cri-socket="${CRI_SOCKET}"

sudo k0s start

sleep 2
sudo k0s status
