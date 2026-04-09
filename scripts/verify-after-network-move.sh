#!/usr/bin/env bash

set -euo pipefail

TALOSCTL_BIN="${TALOSCTL_BIN:-talosctl}"
KUBECTL_BIN="${KUBECTL_BIN:-kubectl}"
TALOSCONFIG_PATH="${TALOSCONFIG_PATH:-/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/talosconfig}"
NODE_IP="${NODE_IP:-${1:-}}"
TMP_KUBECONFIG="${TMP_KUBECONFIG:-${TMPDIR:-/tmp}/prometheus-relocated-kubeconfig-$$}"
WAIT_SECONDS="${WAIT_SECONDS:-600}"
SLEEP_SECONDS="${SLEEP_SECONDS:-10}"

OPEN_WEBUI_NAMESPACE="${OPEN_WEBUI_NAMESPACE:-ai}"
OPEN_WEBUI_SERVICE="${OPEN_WEBUI_SERVICE:-open-webui}"
OPEN_WEBUI_LOCAL_PORT="${OPEN_WEBUI_LOCAL_PORT:-18085}"
OPEN_WEBUI_REMOTE_PORT="${OPEN_WEBUI_REMOTE_PORT:-80}"
OPEN_WEBUI_LOCAL_URL="${OPEN_WEBUI_LOCAL_URL:-http://127.0.0.1:${OPEN_WEBUI_LOCAL_PORT}/}"

VLLM_NAMESPACE="${VLLM_NAMESPACE:-ai}"
VLLM_SERVICE="${VLLM_SERVICE:-vllm}"
VLLM_LOCAL_PORT="${VLLM_LOCAL_PORT:-18086}"
VLLM_REMOTE_PORT="${VLLM_REMOTE_PORT:-8000}"
VLLM_LOCAL_URL="${VLLM_LOCAL_URL:-http://127.0.0.1:${VLLM_LOCAL_PORT}/v1/models}"

SUMMARIZER_NAMESPACE="${SUMMARIZER_NAMESPACE:-summarizer}"
SUMMARIZER_SERVICE="${SUMMARIZER_SERVICE:-summarizer}"
SUMMARIZER_LOCAL_PORT="${SUMMARIZER_LOCAL_PORT:-18087}"
SUMMARIZER_REMOTE_PORT="${SUMMARIZER_REMOTE_PORT:-80}"
SUMMARIZER_LOCAL_URL="${SUMMARIZER_LOCAL_URL:-http://127.0.0.1:${SUMMARIZER_LOCAL_PORT}/api/health}"

ADGUARD_NAMESPACE="${ADGUARD_NAMESPACE:-dns}"
ADGUARD_SERVICE="${ADGUARD_SERVICE:-adguard-home}"
ADGUARD_LOCAL_PORT="${ADGUARD_LOCAL_PORT:-18088}"
ADGUARD_REMOTE_PORT="${ADGUARD_REMOTE_PORT:-80}"
ADGUARD_LOCAL_URL="${ADGUARD_LOCAL_URL:-http://127.0.0.1:${ADGUARD_LOCAL_PORT}/}"

GRAFANA_NAMESPACE="${GRAFANA_NAMESPACE:-observability}"
GRAFANA_SERVICE="${GRAFANA_SERVICE:-kube-prometheus-stack-grafana}"
GRAFANA_LOCAL_PORT="${GRAFANA_LOCAL_PORT:-18082}"
GRAFANA_REMOTE_PORT="${GRAFANA_REMOTE_PORT:-80}"
GRAFANA_LOCAL_URL="${GRAFANA_LOCAL_URL:-http://127.0.0.1:${GRAFANA_LOCAL_PORT}/login}"

LANGGRAPH_NAMESPACE="${LANGGRAPH_NAMESPACE:-agents}"
LANGGRAPH_SERVICE="${LANGGRAPH_SERVICE:-langgraph}"
LANGGRAPH_LOCAL_PORT="${LANGGRAPH_LOCAL_PORT:-18081}"
LANGGRAPH_REMOTE_PORT="${LANGGRAPH_REMOTE_PORT:-8000}"
LANGGRAPH_LOCAL_URL="${LANGGRAPH_LOCAL_URL:-http://127.0.0.1:${LANGGRAPH_LOCAL_PORT}/healthz}"

ATHENA_NAMESPACE="${ATHENA_NAMESPACE:-athena}"
ATHENA_SERVICE="${ATHENA_SERVICE:-athena}"
ATHENA_LOCAL_PORT="${ATHENA_LOCAL_PORT:-18083}"
ATHENA_REMOTE_PORT="${ATHENA_REMOTE_PORT:-80}"
ATHENA_LOCAL_URL="${ATHENA_LOCAL_URL:-http://127.0.0.1:${ATHENA_LOCAL_PORT}/api/v1/health}"

APOLLO_NAMESPACE="${APOLLO_NAMESPACE:-agents}"
APOLLO_SERVICE="${APOLLO_SERVICE:-apollo}"
APOLLO_LOCAL_PORT="${APOLLO_LOCAL_PORT:-18084}"
APOLLO_REMOTE_PORT="${APOLLO_REMOTE_PORT:-80}"
APOLLO_LOCAL_URL="${APOLLO_LOCAL_URL:-http://127.0.0.1:${APOLLO_LOCAL_PORT}/api/v1/health}"

NATS_NAMESPACE="${NATS_NAMESPACE:-agents}"
NATS_SERVICE="${NATS_SERVICE:-nats}"
NATS_LOCAL_PORT="${NATS_LOCAL_PORT:-18222}"
NATS_REMOTE_PORT="${NATS_REMOTE_PORT:-8222}"
NATS_LOCAL_URL="${NATS_LOCAL_URL:-http://127.0.0.1:${NATS_LOCAL_PORT}/varz}"

CORE_POD_PATTERN="${CORE_POD_PATTERN:-adguard|open-webui|vllm|langgraph|qdrant|tei|postgres|grafana|prometheus|metrics-server|dcgm-exporter|summarizer|athena|apollo|nats}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

wait_for() {
  local label="$1"
  shift
  local deadline=$((SECONDS + WAIT_SECONDS))

  while true; do
    if "$@" >/dev/null 2>&1; then
      echo "ok: ${label}"
      return 0
    fi

    if (( SECONDS >= deadline )); then
      echo "timeout waiting for ${label}" >&2
      return 1
    fi

    sleep "${SLEEP_SECONDS}"
  done
}

start_port_forward() {
  local log_file="$1"
  shift
  "${KUBECTL_BIN}" "$@" >"${log_file}" 2>&1 &
  echo $!
}

if [[ -z "${NODE_IP}" ]]; then
  echo "usage: NODE_IP=<new-node-ip> $(basename "$0")" >&2
  echo "or: $(basename "$0") <new-node-ip>" >&2
  exit 1
fi

require_cmd "${TALOSCTL_BIN}"
require_cmd "${KUBECTL_BIN}"
require_cmd curl
require_cmd grep

cleanup() {
  rm -f "${TMP_KUBECONFIG}" >/dev/null 2>&1 || true
  kill "${PF_OPEN_WEBUI:-}" "${PF_VLLM:-}" "${PF_SUMMARIZER:-}" "${PF_ADGUARD:-}" "${PF_GRAFANA:-}" \
       "${PF_LANGGRAPH:-}" "${PF_ATHENA:-}" "${PF_APOLLO:-}" "${PF_NATS:-}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "== Talos direct health on relocated node =="
wait_for "talos health on ${NODE_IP}" \
  "${TALOSCTL_BIN}" --talosconfig "${TALOSCONFIG_PATH}" -e "${NODE_IP}" -n "${NODE_IP}" health
"${TALOSCTL_BIN}" --talosconfig "${TALOSCONFIG_PATH}" -e "${NODE_IP}" -n "${NODE_IP}" health

echo
echo "== Build temporary kubeconfig from relocated node =="
"${TALOSCTL_BIN}" --talosconfig "${TALOSCONFIG_PATH}" -e "${NODE_IP}" -n "${NODE_IP}" \
  kubeconfig "${TMP_KUBECONFIG}" --force --merge=false
export KUBECONFIG="${TMP_KUBECONFIG}"

echo
echo "== Kubernetes and Flux =="
wait_for "kubernetes api on relocated node" \
  "${KUBECTL_BIN}" get nodes
"${KUBECTL_BIN}" get nodes -o wide
"${KUBECTL_BIN}" get kustomizations -A

echo
echo "== Metrics API =="
wait_for "metrics api" \
  "${KUBECTL_BIN}" top nodes
"${KUBECTL_BIN}" top nodes

echo
echo "== Core pods =="
"${KUBECTL_BIN}" get pods -A | egrep "${CORE_POD_PATTERN}"

echo
echo "== Service checks through port-forward =="
PF_OPEN_WEBUI="$(start_port_forward "${TMPDIR:-/tmp}/prometheus-relocated-open-webui.log" -n "${OPEN_WEBUI_NAMESPACE}" port-forward "svc/${OPEN_WEBUI_SERVICE}" "${OPEN_WEBUI_LOCAL_PORT}:${OPEN_WEBUI_REMOTE_PORT}")"
PF_VLLM="$(start_port_forward "${TMPDIR:-/tmp}/prometheus-relocated-vllm.log" -n "${VLLM_NAMESPACE}" port-forward "svc/${VLLM_SERVICE}" "${VLLM_LOCAL_PORT}:${VLLM_REMOTE_PORT}")"
PF_SUMMARIZER="$(start_port_forward "${TMPDIR:-/tmp}/prometheus-relocated-summarizer.log" -n "${SUMMARIZER_NAMESPACE}" port-forward "svc/${SUMMARIZER_SERVICE}" "${SUMMARIZER_LOCAL_PORT}:${SUMMARIZER_REMOTE_PORT}")"
PF_ADGUARD="$(start_port_forward "${TMPDIR:-/tmp}/prometheus-relocated-adguard.log" -n "${ADGUARD_NAMESPACE}" port-forward "svc/${ADGUARD_SERVICE}" "${ADGUARD_LOCAL_PORT}:${ADGUARD_REMOTE_PORT}")"
PF_GRAFANA="$(start_port_forward "${TMPDIR:-/tmp}/prometheus-relocated-grafana.log" -n "${GRAFANA_NAMESPACE}" port-forward "svc/${GRAFANA_SERVICE}" "${GRAFANA_LOCAL_PORT}:${GRAFANA_REMOTE_PORT}")"
PF_LANGGRAPH="$(start_port_forward "${TMPDIR:-/tmp}/prometheus-relocated-langgraph.log" -n "${LANGGRAPH_NAMESPACE}" port-forward "svc/${LANGGRAPH_SERVICE}" "${LANGGRAPH_LOCAL_PORT}:${LANGGRAPH_REMOTE_PORT}")"
PF_ATHENA="$(start_port_forward "${TMPDIR:-/tmp}/prometheus-relocated-athena.log" -n "${ATHENA_NAMESPACE}" port-forward "svc/${ATHENA_SERVICE}" "${ATHENA_LOCAL_PORT}:${ATHENA_REMOTE_PORT}")"
PF_APOLLO="$(start_port_forward "${TMPDIR:-/tmp}/prometheus-relocated-apollo.log" -n "${APOLLO_NAMESPACE}" port-forward "svc/${APOLLO_SERVICE}" "${APOLLO_LOCAL_PORT}:${APOLLO_REMOTE_PORT}")"
PF_NATS="$(start_port_forward "${TMPDIR:-/tmp}/prometheus-relocated-nats.log" -n "${NATS_NAMESPACE}" port-forward "svc/${NATS_SERVICE}" "${NATS_LOCAL_PORT}:${NATS_REMOTE_PORT}")"

wait_for "open-webui http 200" \
  bash -lc "curl -fsSI '${OPEN_WEBUI_LOCAL_URL}' | grep -q '200'"
curl -fsSI "${OPEN_WEBUI_LOCAL_URL}" | sed -n '1,5p'

echo
wait_for "vllm models endpoint" \
  curl -fsS "${VLLM_LOCAL_URL}"
curl -fsS "${VLLM_LOCAL_URL}"

echo
wait_for "summarizer health" \
  curl -fsS "${SUMMARIZER_LOCAL_URL}"
curl -fsS "${SUMMARIZER_LOCAL_URL}"

echo
wait_for "adguard http listener" \
  curl -fsSI "${ADGUARD_LOCAL_URL}"
curl -fsSI "${ADGUARD_LOCAL_URL}" | sed -n '1,5p'

echo
wait_for "grafana http listener" \
  curl -fsSI "${GRAFANA_LOCAL_URL}"
curl -fsSI "${GRAFANA_LOCAL_URL}" | sed -n '1,5p'

echo
wait_for "langgraph health" \
  curl -fsS "${LANGGRAPH_LOCAL_URL}"
curl -fsS "${LANGGRAPH_LOCAL_URL}"

echo
wait_for "athena health" \
  curl -fsS "${ATHENA_LOCAL_URL}"
curl -fsS "${ATHENA_LOCAL_URL}"

echo
wait_for "apollo health" \
  curl -fsS "${APOLLO_LOCAL_URL}"
curl -fsS "${APOLLO_LOCAL_URL}"

echo
wait_for "nats varz" \
  curl -fsS "${NATS_LOCAL_URL}"
curl -fsS "${NATS_LOCAL_URL}" | sed -n '1,12p'

echo
echo "Relocation verification passed."
