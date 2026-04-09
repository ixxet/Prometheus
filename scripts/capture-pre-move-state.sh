#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TALOSCTL_BIN="${TALOSCTL_BIN:-talosctl}"
KUBECTL_BIN="${KUBECTL_BIN:-kubectl}"
TALOSCONFIG_PATH="${TALOSCONFIG_PATH:-/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/talosconfig}"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig}"
NODE_IP="${NODE_IP:-192.168.2.49}"
OUTPUT_BASE="${OUTPUT_BASE:-${REPO_ROOT}/ops/state-snapshots}"
SNAPSHOT_ID="${SNAPSHOT_ID:-$(date +%Y%m%dT%H%M%S%z)}"
OUTDIR="${OUTDIR:-${OUTPUT_BASE}/${SNAPSHOT_ID}}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

capture_cmd() {
  local file="$1"
  shift
  {
    printf '$'
    printf ' %q' "$@"
    printf '\n'
  } >"${OUTDIR}/${file}"

  if ! "$@" >>"${OUTDIR}/${file}" 2>&1; then
    printf '\ncommand failed while capturing %s\n' "${file}" >>"${OUTDIR}/${file}"
  fi
}

capture_shell() {
  local file="$1"
  shift
  local cmd="$*"
  printf '$ %s\n' "${cmd}" >"${OUTDIR}/${file}"
  if ! bash -lc "${cmd}" >>"${OUTDIR}/${file}" 2>&1; then
    printf '\ncommand failed while capturing %s\n' "${file}" >>"${OUTDIR}/${file}"
  fi
}

require_cmd "${TALOSCTL_BIN}"
require_cmd "${KUBECTL_BIN}"
require_cmd date

mkdir -p "${OUTDIR}"
export KUBECONFIG="${KUBECONFIG_PATH}"

cat >"${OUTDIR}/README.txt" <<EOF
Prometheus pre-move state snapshot

Created: $(date)
Node IP at capture time: ${NODE_IP}
Talos config: ${TALOSCONFIG_PATH}
Kubeconfig: ${KUBECONFIG_PATH}

This snapshot captures the pre-move runtime state before the tower leaves its
current network. It is a local operator record, not a GitOps source of truth.

Important:
- the old 192.168.2.x service IPs may not work after relocation
- current Cloudflare quick tunnel URLs may change after a restart
- MIMIR subnet-route based management only applies while Prometheus is on the
  original LAN
EOF

capture_cmd "talos-version.txt" "${TALOSCTL_BIN}" version --client
capture_cmd "kubectl-version.txt" "${KUBECTL_BIN}" version --client
capture_cmd "talos-health.txt" "${TALOSCTL_BIN}" --talosconfig "${TALOSCONFIG_PATH}" -n "${NODE_IP}" health
capture_cmd "talos-image-ls.txt" "${TALOSCTL_BIN}" --talosconfig "${TALOSCONFIG_PATH}" -n "${NODE_IP}" image ls
capture_cmd "talos-service-state.txt" "${TALOSCTL_BIN}" --talosconfig "${TALOSCONFIG_PATH}" -n "${NODE_IP}" service
capture_cmd "kubectl-nodes.txt" "${KUBECTL_BIN}" get nodes -o wide
capture_cmd "kubectl-kustomizations.txt" "${KUBECTL_BIN}" get kustomizations -A
capture_cmd "kubectl-pods.txt" "${KUBECTL_BIN}" get pods -A -o wide
capture_cmd "kubectl-services.txt" "${KUBECTL_BIN}" get svc -A -o wide
capture_cmd "kubectl-workloads.txt" "${KUBECTL_BIN}" get deploy,statefulset,daemonset -A -o wide
capture_cmd "kubectl-storage.txt" "${KUBECTL_BIN}" get pvc,pv -A
capture_cmd "kubectl-endpoints.txt" "${KUBECTL_BIN}" get endpoints,endpointslices -A
capture_cmd "kubectl-ingress.txt" "${KUBECTL_BIN}" get ingress -A
capture_cmd "kubectl-top-nodes.txt" "${KUBECTL_BIN}" top nodes
capture_cmd "kubectl-top-pods.txt" "${KUBECTL_BIN}" top pods -A

capture_shell "summarizer-tunnel-url.txt" \
  "${KUBECTL_BIN} -n summarizer logs deployment/summarizer-tunnel --tail=200 | rg -o 'https://[-a-z0-9]+\\.trycloudflare\\.com' | tail -n1"

capture_cmd "deployment-vllm.yaml" "${KUBECTL_BIN}" -n ai get deployment vllm -o yaml
capture_cmd "deployment-open-webui.yaml" "${KUBECTL_BIN}" -n ai get deployment open-webui -o yaml
capture_cmd "deployment-summarizer.yaml" "${KUBECTL_BIN}" -n summarizer get deployment summarizer -o yaml
capture_cmd "deployment-summarizer-proxy.yaml" "${KUBECTL_BIN}" -n summarizer get deployment summarizer-proxy -o yaml
capture_cmd "deployment-summarizer-tunnel.yaml" "${KUBECTL_BIN}" -n summarizer get deployment summarizer-tunnel -o yaml
capture_cmd "deployment-athena.yaml" "${KUBECTL_BIN}" -n athena get deployment athena -o yaml
capture_cmd "deployment-apollo.yaml" "${KUBECTL_BIN}" -n agents get deployment apollo -o yaml
capture_cmd "deployment-langgraph.yaml" "${KUBECTL_BIN}" -n agents get deployment langgraph -o yaml

echo "Pre-move snapshot written to ${OUTDIR}"
