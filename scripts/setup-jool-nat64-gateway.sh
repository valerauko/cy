#!/usr/bin/env bash
set -euo pipefail

# Run this on the NAT64 gateway node (your single public control node).
# It installs Jool from source with DKMS, enables forwarding, and starts a NAT64 instance.

JOOL_VERSION="${JOOL_VERSION:-4.1.15}"
NAT64_PREFIX="${NAT64_PREFIX:-64:ff9b::/96}"
INSTANCE_NAME="${INSTANCE_NAME:-nat64-main}"

echo "[1/6] Installing build dependencies"
sudo apt-get update
sudo apt-get install -y \
  build-essential pkg-config linux-headers-"$(uname -r)" \
  libnl-genl-3-dev libxtables-dev dkms git autoconf libtool wget curl

echo "[2/6] Downloading Jool ${JOOL_VERSION}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT
cd "${TMP_DIR}"
wget -q "https://github.com/NICMx/Jool/releases/download/v${JOOL_VERSION}/jool-${JOOL_VERSION}.tar.gz"
tar -xzf "jool-${JOOL_VERSION}.tar.gz"

JOOL_SRC_DIR="${TMP_DIR}/jool-${JOOL_VERSION}"

echo "[3/6] Installing Jool kernel module via DKMS"
sudo dkms install "${JOOL_SRC_DIR}/"

echo "[4/6] Installing Jool userspace tooling"
cd "${JOOL_SRC_DIR}"
./configure
make -j"$(nproc)"
sudo make install

# Ensure newly installed binaries are discoverable in non-login shells.
if ! command -v jool >/dev/null 2>&1; then
  export PATH="/usr/local/bin:/usr/local/sbin:${PATH}"
fi

echo "[5/6] Enabling IPv4/IPv6 forwarding"
sudo tee /etc/sysctl.d/98-nat64-forwarding.conf >/dev/null <<'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sudo sysctl --system >/dev/null

echo "[6/6] Starting Jool NAT64 instance"
sudo modprobe jool

# Idempotent cleanup of any pre-existing instance with the same name.
if sudo jool instance display 2>/dev/null | grep -q "${INSTANCE_NAME}"; then
  sudo jool instance remove "${INSTANCE_NAME}"
fi

sudo jool instance add "${INSTANCE_NAME}" --netfilter --pool6 "${NAT64_PREFIX}"

echo "[bonus] Installing persistent systemd autostart for Jool NAT64"
sudo install -d -m 0755 /etc/jool /usr/local/libexec

sudo tee /etc/jool/nat64.env >/dev/null <<EOF
INSTANCE_NAME="${INSTANCE_NAME}"
NAT64_PREFIX="${NAT64_PREFIX}"
EOF

sudo tee /usr/local/libexec/jool-nat64-up.sh >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

source /etc/jool/nat64.env

modprobe jool

if jool instance display 2>/dev/null | grep -q "${INSTANCE_NAME}"; then
  jool instance remove "${INSTANCE_NAME}" || true
fi

jool instance add "${INSTANCE_NAME}" --netfilter --pool6 "${NAT64_PREFIX}"
EOF

sudo tee /usr/local/libexec/jool-nat64-down.sh >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

source /etc/jool/nat64.env

jool instance remove "${INSTANCE_NAME}" || true
modprobe -r jool || true
EOF

sudo chmod 0755 /usr/local/libexec/jool-nat64-up.sh /usr/local/libexec/jool-nat64-down.sh

sudo tee /etc/systemd/system/jool-nat64.service >/dev/null <<'EOF'
[Unit]
Description=Jool NAT64 instance
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/libexec/jool-nat64-up.sh
ExecStop=/usr/local/libexec/jool-nat64-down.sh

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now jool-nat64.service

echo
echo "NAT64 instance is up. Current status:"
sudo jool instance display || true
sudo jool pool4 display --tcp || true
sudo systemctl --no-pager --full status jool-nat64.service || true

echo
echo "Next steps:"
echo "1) Configure DNS64 in CoreDNS (see README)."
echo "2) Add route ${NAT64_PREFIX} via this node on all cluster nodes."
