# Semantic Memory Activation Runbook

Last updated: 2026-03-26 (America/Toronto)

## Purpose

This runbook turns the staged `v0.4.0` semantic-memory layer into a live one.
It assumes:

- LangGraph already runs with the Mem0-backed provider code present
- `infra-semantic-memory` exists in GitOps but is still suspended
- AdGuard remains test-only on the tower

## What will be enabled

- `Qdrant` in the `semantic-memory` namespace
- `TEI` (`text-embeddings-inference`) in the `semantic-memory` namespace
- LangGraph `SEMANTIC_MEMORY_PROVIDER=mem0`

## 1. Unsuspend the support stack

Edit:

- `/Users/zizo/Personal-Projects/Computers/Prometheus/homelab-gitops/clusters/talos-tower/infrastructure.yaml`

Change:

- `infra-semantic-memory`
  - `suspend: true` -> remove or set `false`

## 2. Wait for support services

```bash
kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig -n semantic-memory get pods,pvc,svc
```

Expected:

- `qdrant` pod `1/1`
- `tei-embeddings` pod `1/1`
- both PVCs `Bound`

## 3. Flip LangGraph to Mem0

Edit:

- `/Users/zizo/Personal-Projects/Computers/Prometheus/homelab-gitops/apps/agents/langgraph/langgraph-configmap.yaml`

Change:

- `SEMANTIC_MEMORY_PROVIDER: none` -> `SEMANTIC_MEMORY_PROVIDER: mem0`

Keep:

- `ARCHIVE_SINK: none`

until the external Obsidian export path exists.

## 4. Reconcile and verify health

```bash
flux reconcile source git flux-system -n flux-system
flux reconcile kustomization infra-semantic-memory -n flux-system
flux reconcile kustomization apps -n flux-system
```

Then:

```bash
kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig -n agents port-forward svc/langgraph 18081:8000
curl http://127.0.0.1:18081/healthz
```

Expected:

- `semantic_memory_provider: "mem0"`
- `archive_sink: "none"`

## 5. Smoke-test semantic write and recall

Create a thread and run:

```bash
curl -s http://127.0.0.1:18081/threads \
  -H 'Content-Type: application/json' \
  -d '{"title":"semantic memory smoke"}'
```

Then send a preference worth remembering:

```bash
THREAD_ID="<thread-id>"

curl -s http://127.0.0.1:18081/threads/${THREAD_ID}/runs \
  -H 'Content-Type: application/json' \
  -d '{
    "message": "For this project, do not make the tower the sole DNS authority.",
    "require_approval": false
  }'
```

Follow with a second thread and ask a related question:

```bash
curl -s http://127.0.0.1:18081/threads \
  -H 'Content-Type: application/json' \
  -d '{"title":"semantic memory recall"}'
```

Then:

```bash
THREAD_ID="<new-thread-id>"

curl -s http://127.0.0.1:18081/threads/${THREAD_ID}/runs \
  -H 'Content-Type: application/json' \
  -d '{
    "message": "What is the current DNS stance for the tower?",
    "require_approval": false
  }'
```

Expected:

- the answer should reflect the stored DNS constraint
- LangGraph logs should not show semantic-memory initialization failures

## 6. If it regresses

1. set `SEMANTIC_MEMORY_PROVIDER` back to `none`
2. reconcile `apps`
3. inspect:
   - `kubectl -n semantic-memory get pods,pvc,svc`
   - `kubectl -n agents logs deploy/langgraph --tail=200`
   - `kubectl -n semantic-memory logs deploy/tei-embeddings --tail=200`
   - `kubectl -n semantic-memory logs deploy/qdrant --tail=200`
