#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT_DIR}/ops/local"
BUNDLE_DIR="${OUT_DIR}/break-glass"

mkdir -p "${BUNDLE_DIR}"
chmod 700 "${OUT_DIR}" "${BUNDLE_DIR}"

copy_if_exists() {
  local src="$1"
  local dest="$2"

  if [[ -f "${src}" ]]; then
    cp "${src}" "${dest}"
    chmod 600 "${dest}" || true
  fi
}

copy_if_exists "${HOME}/.config/sops/age/keys.txt" "${BUNDLE_DIR}/age.keys.txt"
copy_if_exists "${HOME}/.ssh/mimir_ed25519" "${BUNDLE_DIR}/mimir_ed25519"
copy_if_exists "${HOME}/.ssh/mimir_ed25519.pub" "${BUNDLE_DIR}/mimir_ed25519.pub"
copy_if_exists "${ROOT_DIR}/.sops.yaml" "${BUNDLE_DIR}/.sops.yaml"
copy_if_exists "${ROOT_DIR}/../Talos/tower-bootstrap/talosconfig" "${BUNDLE_DIR}/talosconfig"
copy_if_exists "${ROOT_DIR}/../Talos/tower-bootstrap/kubeconfig" "${BUNDLE_DIR}/kubeconfig"

CURRENT_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"
CURRENT_SERVER="$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || true)"
GENERATED_AT="$(date '+%Y-%m-%d %H:%M:%S %Z')"

cat > "${OUT_DIR}/RECOVERY.local.md" <<EOF
# Local Recovery Bundle

Generated: ${GENERATED_AT}

This directory is intentionally local-only and ignored by Git.

## Current operator state

- current kubectl context: \`${CURRENT_CONTEXT}\`
- current kubeconfig server: \`${CURRENT_SERVER}\`
- expected SOPS key path: \`${HOME}/.config/sops/age/keys.txt\`
- expected MIMIR SSH key path: \`${HOME}/.ssh/mimir_ed25519\`

## Bundle files

- \`break-glass/age.keys.txt\`
- \`break-glass/mimir_ed25519\`
- \`break-glass/mimir_ed25519.pub\`
- \`break-glass/.sops.yaml\`
- \`break-glass/talosconfig\`
- \`break-glass/kubeconfig\`

## Restore checklist

1. Restore \`age.keys.txt\` to \`${HOME}/.config/sops/age/keys.txt\`.
2. Restore \`mimir_ed25519\` to \`${HOME}/.ssh/mimir_ed25519\`.
3. Restore \`talosconfig\` and \`kubeconfig\` to the Talos bootstrap directory if needed.
4. Re-export:

\`\`\`bash
export KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig
export SOPS_AGE_KEY_FILE=\$HOME/.config/sops/age/keys.txt
\`\`\`

5. Verify:

\`\`\`bash
kubectl get nodes
sops -d /Users/zizo/Personal-Projects/Computers/Prometheus/homelab-gitops/apps/athena/athena-edge-runtime-secret.yaml >/dev/null && echo ok
\`\`\`
EOF

chmod 600 "${OUT_DIR}/RECOVERY.local.md" || true

echo "Local recovery bundle refreshed at ${OUT_DIR}"
