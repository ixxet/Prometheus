#!/usr/bin/env bash

set -euo pipefail

TALOSCTL_BIN="${TALOSCTL_BIN:-talosctl}"
KUBECTL_BIN="${KUBECTL_BIN:-kubectl}"
TALOSCONFIG_PATH="${TALOSCONFIG_PATH:-/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/talosconfig}"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig}"
NODE_IP="${NODE_IP:-192.168.2.49}"
TALOS_API_PORT="${TALOS_API_PORT:-50000}"
TALOS_HEALTH_MODE="${TALOS_HEALTH_MODE:-auto}"
OPEN_WEBUI_URL="${OPEN_WEBUI_URL:-http://192.168.2.201/}"
VLLM_MODELS_URL="${VLLM_MODELS_URL:-http://192.168.2.205:8000/v1/models}"
ADGUARD_URL="${ADGUARD_URL:-http://192.168.2.200/}"
GRAFANA_URL="${GRAFANA_URL:-http://192.168.2.202/login}"
SUMMARIZER_URL="${SUMMARIZER_URL:-http://192.168.2.203/api/health}"
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
PORT_FORWARD_LOG="${PORT_FORWARD_LOG:-${TMPDIR:-/tmp}/prometheus-langgraph-port-forward.log}"
ATHENA_PORT_FORWARD_LOG="${ATHENA_PORT_FORWARD_LOG:-${TMPDIR:-/tmp}/prometheus-athena-port-forward.log}"
APOLLO_PORT_FORWARD_LOG="${APOLLO_PORT_FORWARD_LOG:-${TMPDIR:-/tmp}/prometheus-apollo-port-forward.log}"
NATS_PORT_FORWARD_LOG="${NATS_PORT_FORWARD_LOG:-${TMPDIR:-/tmp}/prometheus-nats-port-forward.log}"
CORE_POD_PATTERN="${CORE_POD_PATTERN:-adguard|open-webui|vllm|langgraph|qdrant|tei|postgres|grafana|prometheus|metrics-server|dcgm-exporter|summarizer|athena|apollo|nats}"
WAIT_SECONDS="${WAIT_SECONDS:-600}"
SLEEP_SECONDS="${SLEEP_SECONDS:-10}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

talosctl_usable() {
  if [[ "${TALOS_HEALTH_MODE}" == "tcp" ]]; then
    return 1
  fi

  if ! command -v "${TALOSCTL_BIN}" >/dev/null 2>&1; then
    return 1
  fi

  "${TALOSCTL_BIN}" version --client >/dev/null 2>&1
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

require_cmd "${KUBECTL_BIN}"
require_cmd curl
require_cmd grep

export KUBECONFIG="${KUBECONFIG_PATH}"

if talosctl_usable; then
  echo "== Talos node health =="
  wait_for "talos health" \
    "${TALOSCTL_BIN}" --talosconfig "${TALOSCONFIG_PATH}" -n "${NODE_IP}" health
  "${TALOSCTL_BIN}" --talosconfig "${TALOSCONFIG_PATH}" -n "${NODE_IP}" health
else
  require_cmd python3
  echo "== Talos API reachability =="
  echo "talosctl is unavailable or unusable on this host; falling back to a TCP probe of ${NODE_IP}:${TALOS_API_PORT}"
  wait_for "talos api tcp ${TALOS_API_PORT}" \
    python3 - "${NODE_IP}" "${TALOS_API_PORT}" <<'PY'
import socket
import sys

host = sys.argv[1]
port = int(sys.argv[2])
sock = socket.create_connection((host, port), timeout=5)
sock.close()
PY
  python3 - "${NODE_IP}" "${TALOS_API_PORT}" <<'PY'
import socket
import sys

host = sys.argv[1]
port = int(sys.argv[2])
sock = socket.create_connection((host, port), timeout=5)
sock.close()
print(f"ok: Talos API reachable on {host}:{port}")
PY
fi

echo
echo "== Kubernetes and Flux =="
wait_for "kubernetes api" \
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
echo "== LAN endpoints =="
wait_for "open-webui http 200" \
  bash -lc "curl -fsSI '${OPEN_WEBUI_URL}' | grep -q '200'"
curl -fsSI "${OPEN_WEBUI_URL}" | sed -n '1,5p'

wait_for "vllm models endpoint" \
  curl -fsS "${VLLM_MODELS_URL}"
curl -fsS "${VLLM_MODELS_URL}"

wait_for "adguard http listener" \
  curl -fsSI "${ADGUARD_URL}"
curl -fsSI "${ADGUARD_URL}" | sed -n '1,5p'

echo
wait_for "grafana http listener" \
  curl -fsSI "${GRAFANA_URL}"
curl -fsSI "${GRAFANA_URL}" | sed -n '1,5p'

echo
wait_for "summarizer http health" \
  curl -fsS "${SUMMARIZER_URL}"
curl -fsS "${SUMMARIZER_URL}"

echo
echo "== LangGraph health =="
PF_PID="$(start_port_forward "${PORT_FORWARD_LOG}" -n "${LANGGRAPH_NAMESPACE}" port-forward "svc/${LANGGRAPH_SERVICE}" "${LANGGRAPH_LOCAL_PORT}:${LANGGRAPH_REMOTE_PORT}")"
ATHENA_PF_PID="$(start_port_forward "${ATHENA_PORT_FORWARD_LOG}" -n "${ATHENA_NAMESPACE}" port-forward "svc/${ATHENA_SERVICE}" "${ATHENA_LOCAL_PORT}:${ATHENA_REMOTE_PORT}")"
APOLLO_PF_PID="$(start_port_forward "${APOLLO_PORT_FORWARD_LOG}" -n "${APOLLO_NAMESPACE}" port-forward "svc/${APOLLO_SERVICE}" "${APOLLO_LOCAL_PORT}:${APOLLO_REMOTE_PORT}")"
NATS_PF_PID="$(start_port_forward "${NATS_PORT_FORWARD_LOG}" -n "${NATS_NAMESPACE}" port-forward "svc/${NATS_SERVICE}" "${NATS_LOCAL_PORT}:${NATS_REMOTE_PORT}")"
trap 'kill ${PF_PID} ${ATHENA_PF_PID} ${APOLLO_PF_PID} ${NATS_PF_PID} >/dev/null 2>&1 || true' EXIT

wait_for "langgraph health" \
  curl -fsS "${LANGGRAPH_LOCAL_URL}"
curl -fsS "${LANGGRAPH_LOCAL_URL}"

echo
echo "== ATHENA / APOLLO / NATS health =="
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
echo "Post-return verification passed."
