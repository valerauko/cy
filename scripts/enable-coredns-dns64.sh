#!/usr/bin/env bash
set -euo pipefail

# Enables DNS64 in CoreDNS by patching the CoreDNS ConfigMap.
# Safe to run multiple times: if dns64 is already present, no changes are made.
#
# Optional overrides:
#   KUBECTL_CMD="k0s kubectl"    (default)
#   CORE_DNS_CM_NAMESPACE="kube-system"
#   CORE_DNS_CM_NAME="coredns"
#   CORE_DNS_DEPLOYMENT_NAME="coredns"

NAT64_PREFIX="${NAT64_PREFIX:-64:ff9b::/96}"
KUBECTL_CMD="${KUBECTL_CMD:-k0s kubectl}"

read -r -a KCTL <<< "${KUBECTL_CMD}"

kc() {
    "${KCTL[@]}" "$@"
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

CM_YAML="${TMP_DIR}/coredns-cm.yaml"
PATCHED_CM_YAML="${TMP_DIR}/coredns-cm-patched.yaml"

CM_NAMESPACE="${CORE_DNS_CM_NAMESPACE:-}"
CM_NAME="${CORE_DNS_CM_NAME:-}"
DEPLOYMENT_NAME="${CORE_DNS_DEPLOYMENT_NAME:-}"

if [[ -z "${CM_NAMESPACE}" || -z "${CM_NAME}" ]]; then
    # Fast path: common names in kube-system.
    for candidate in coredns kube-dns; do
        if kc -n kube-system get configmap "${candidate}" >/dev/null 2>&1; then
            CM_NAMESPACE="kube-system"
            CM_NAME="${candidate}"
            break
        fi
    done
fi

if [[ -z "${CM_NAMESPACE}" || -z "${CM_NAME}" ]]; then
    # Fallback: search every ConfigMap that contains a Corefile key.
    found="$(kc get configmap -A -o go-template='{{range .items}}{{if index .data "Corefile"}}{{.metadata.namespace}}{{"\t"}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}' | head -n1 || true)"
    if [[ -n "${found}" ]]; then
        CM_NAMESPACE="${found%%$'\t'*}"
        CM_NAME="${found##*$'\t'}"
    fi
fi

if [[ -z "${CM_NAMESPACE}" || -z "${CM_NAME}" ]]; then
    echo "Could not auto-detect CoreDNS ConfigMap." >&2
    echo "Set CORE_DNS_CM_NAMESPACE and CORE_DNS_CM_NAME explicitly and rerun." >&2
    exit 1
fi

if [[ -z "${DEPLOYMENT_NAME}" ]]; then
    # Common deployment names first.
    for candidate in coredns kube-dns; do
        if kc -n "${CM_NAMESPACE}" get deployment "${candidate}" >/dev/null 2>&1; then
            DEPLOYMENT_NAME="${candidate}"
            break
        fi
    done
fi

if [[ -z "${DEPLOYMENT_NAME}" ]]; then
    # Fallback: first deployment in same namespace with known DNS labels.
    DEPLOYMENT_NAME="$(kc -n "${CM_NAMESPACE}" get deployment -l 'k8s-app in (kube-dns,coredns)' -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
fi

if [[ -z "${DEPLOYMENT_NAME}" ]]; then
    # Last resort: first deployment in the namespace.
    DEPLOYMENT_NAME="$(kc -n "${CM_NAMESPACE}" get deployment -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
fi

if [[ -z "${DEPLOYMENT_NAME}" ]]; then
    echo "Could not auto-detect DNS deployment in namespace ${CM_NAMESPACE}." >&2
    echo "Set CORE_DNS_DEPLOYMENT_NAME explicitly and rerun." >&2
    exit 1
fi

echo "Using ConfigMap ${CM_NAMESPACE}/${CM_NAME} and Deployment ${CM_NAMESPACE}/${DEPLOYMENT_NAME}"

kc -n "${CM_NAMESPACE}" get configmap "${CM_NAME}" -o yaml > "${CM_YAML}"

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

kc apply -f "${PATCHED_CM_YAML}"
kc -n "${CM_NAMESPACE}" rollout restart deployment "${DEPLOYMENT_NAME}"
kc -n "${CM_NAMESPACE}" rollout status deployment "${DEPLOYMENT_NAME}" --timeout=120s

echo "DNS64 is enabled with prefix ${NAT64_PREFIX}."
