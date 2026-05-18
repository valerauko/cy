#!/usr/bin/env bash
set -euo pipefail

# Enables DNS64 in CoreDNS by patching the kube-system/coredns ConfigMap.
# Safe to run multiple times: if dns64 is already present, no changes are made.

NAT64_PREFIX="${NAT64_PREFIX:-64:ff9b::/96}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

CM_YAML="${TMP_DIR}/coredns-cm.yaml"
PATCHED_CM_YAML="${TMP_DIR}/coredns-cm-patched.yaml"

kubectl -n kube-system get configmap coredns -o yaml > "${CM_YAML}"

python3 - <<'PY' "${CM_YAML}" "${PATCHED_CM_YAML}" "${NAT64_PREFIX}"
import sys
from pathlib import Path

cm_path = Path(sys.argv[1])
out_path = Path(sys.argv[2])
prefix = sys.argv[3]

yaml_text = cm_path.read_text()

marker = "Corefile: |"
idx = yaml_text.find(marker)
if idx == -1:
    raise SystemExit("Could not find CoreDNS Corefile in ConfigMap")

head = yaml_text[:idx]
rest = yaml_text[idx + len(marker):]

lines = rest.splitlines()

# Extract literal block lines (those that start with at least 4 spaces in this CM layout).
block = []
for line in lines:
    if line.startswith("    ") or line.strip() == "":
        block.append(line)
    else:
        break

corefile = "\n".join(line[4:] if line.startswith("    ") else line for line in block)

if "dns64" in corefile:
    out_path.write_text(yaml_text)
    print("dns64 already present; no-op")
    raise SystemExit(0)

inserted = False
new_lines = []
for line in corefile.splitlines():
    new_lines.append(line)
    if not inserted and line.strip() == "forward . /etc/resolv.conf":
        new_lines.append(f"    dns64 {{")
        new_lines.append(f"        prefix {prefix}")
        new_lines.append("    }")
        inserted = True

if not inserted:
    # Fallback: add near the top of the main server block.
    lines_cf = corefile.splitlines()
    for i, line in enumerate(lines_cf):
        if line.strip().endswith("{"):
            lines_cf.insert(i + 1, f"    dns64 {{")
            lines_cf.insert(i + 2, f"        prefix {prefix}")
            lines_cf.insert(i + 3, "    }")
            inserted = True
            break
    new_lines = lines_cf

if not inserted:
    raise SystemExit("Could not find insertion point in Corefile")

new_corefile = "\n".join(new_lines)
indented = "\n".join("    " + l for l in new_corefile.splitlines())

# Rebuild YAML by replacing only the original Corefile literal block.
post = "\n".join(lines[len(block):])
out = head + marker + "\n" + indented + ("\n" + post if post else "\n")
out_path.write_text(out)
print("dns64 inserted")
PY

kubectl apply -f "${PATCHED_CM_YAML}"
kubectl -n kube-system rollout restart deployment coredns
kubectl -n kube-system rollout status deployment coredns --timeout=120s

echo "CoreDNS dns64 is enabled with prefix ${NAT64_PREFIX}."
