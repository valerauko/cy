#!/usr/bin/env bash
set -euo pipefail

CRIO_VERSION="v1.35"

echo "cnh-01" > /etc/hostname

pkill -9 unattended

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
