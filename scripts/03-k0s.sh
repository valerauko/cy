#!/usr/bin/env bash
set -euo pipefail

K0S_VERSION="v1.35.3+k0s.0"

curl -sSLf https://get.k0s.sh | K0S_VERSION="${K0S_VERSION}" sh -
mkdir -p /etc/k0s
