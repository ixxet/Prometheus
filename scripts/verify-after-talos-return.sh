#!/usr/bin/env bash

set -euo pipefail

TALOSCONFIG_PATH="${TALOSCONFIG_PATH:-/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/talosconfig}"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig}"
NODE_IP="${NODE_IP:-192.168.2.49}"
OPEN_WEBUI_URL="${OPEN_WEBUI_URL:-http://192.168.2.201/}"
VLLM_MODELS_URL="${VLLM_MODELS_URL:-http://192.168.2.205:8000/v1/models}"
ADGUARD_URL="${ADGUARD_URL:-http://192.168.2.200/}"
LANGGRAPH_LOCAL_URL="${LANGGRAPH_LOCAL_URL:-http://127.0.0.1:18081/healthz}"
WAIT_SECONDS="${WAIT_SECONDS:-600}"
SLEEP_SECONDS="${SLEEP_SECONDS:-10}"

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

require_cmd talosctl
require_cmd kubectl
require_cmd curl
require_cmd grep

export KUBECONFIG="${KUBECONFIG_PATH}"

echo "== Talos node health =="
wait_for "talos health" \
  talosctl --talosconfig "${TALOSCONFIG_PATH}" -n "${NODE_IP}" health
talosctl --talosconfig "${TALOSCONFIG_PATH}" -n "${NODE_IP}" health

echo
echo "== Kubernetes and Flux =="
wait_for "kubernetes api" \
  kubectl get nodes
kubectl get nodes -o wide
kubectl get kustomizations -A

echo
echo "== Core pods =="
kubectl get pods -A | egrep 'adguard|open-webui|vllm|langgraph|qdrant|tei|postgres'

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
echo "== LangGraph health =="
kubectl -n agents port-forward svc/langgraph 18081:8000 >/tmp/prometheus-langgraph-port-forward.log 2>&1 &
PF_PID=$!
trap 'kill ${PF_PID} >/dev/null 2>&1 || true' EXIT

wait_for "langgraph health" \
  curl -fsS "${LANGGRAPH_LOCAL_URL}"
curl -fsS "${LANGGRAPH_LOCAL_URL}"

echo
echo "Post-return verification passed."
