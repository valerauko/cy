#!/usr/bin/env bash
set -euo pipefail

# CRI-O version must match Kubernetes version
CRIO_VERSION="v1.36"

# Disable unattended upgrades to avoid conflicts
pkill -9 unattended 2>/dev/null || true

apt-get update
apt-get upgrade --with-new-pkgs -y
apt-get install -y software-properties-common curl

curl -fsSL https://download.opensuse.org/repositories/isv:/cri-o:/stable:/$CRIO_VERSION/deb/Release.key |
    gpg --dearmor -o /etc/apt/keyrings/cri-o-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/cri-o-apt-keyring.gpg] https://download.opensuse.org/repositories/isv:/cri-o:/stable:/$CRIO_VERSION/deb/ /" |
    tee /etc/apt/sources.list.d/cri-o.list

apt-get update
apt-get install -y cri-o crun conmon
apt-get autoremove -y
apt-get autoclean

systemctl start crio.service
