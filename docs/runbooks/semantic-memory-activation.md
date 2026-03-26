# Semantic Memory Activation Runbook

Last updated: 2026-03-26 (America/Toronto)

## Purpose

This runbook records how the semantic-memory half of `v0.4.0` was activated.
It assumes:

- LangGraph already runs with the Mem0-backed provider code present
- AdGuard remains test-only on the tower

Current live state on 2026-03-26:

- `infra-semantic-memory` is already unsuspended and healthy
- `Qdrant` and `TEI` are both `1/1 Running`
- LangGraph already reports `semantic_memory_provider: mem0`
- cross-thread write and recall have already been validated once
- the archive half of `v0.4.0` is now documented separately in
  `docs/runbooks/archive-export-validation.md`

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
- ensure `OPENAI_API_KEY: local-not-required` is present for the local TEI-compatible embedder path

Archive export is now its own validated path. Do not change the archive sink
here without updating the dedicated archive runbook.

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
- `archive_sink: "filesystem_markdown"` is acceptable once the archive path is live
- `OPENAI_API_KEY` must be present in the runtime environment, even though TEI is local

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
- Qdrant should expose the `prometheus-memory` collection after the first write

## 6. If it regresses

1. set `SEMANTIC_MEMORY_PROVIDER` back to `none`
2. reconcile `apps`
3. inspect:
   - `kubectl -n semantic-memory get pods,pvc,svc`
   - `kubectl -n agents logs deploy/langgraph --tail=200`
   - `kubectl -n semantic-memory logs deploy/tei-embeddings --tail=200`
   - `kubectl -n semantic-memory logs deploy/qdrant --tail=200`
4. if the runtime is crashing before startup completes, confirm whether:
   - the latest ConfigMap changes actually reached the live object
   - a pod-template change was needed to reroll after `envFrom` updates
   - Flux is stuck behind an older failing revision and the live objects need to
     be converged to the already-committed repo state
