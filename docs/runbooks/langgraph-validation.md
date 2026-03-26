# LangGraph Validation Runbook

Last updated: 2026-03-26 (America/Toronto)

## Purpose

This is the acceptance path for the `v0.3.0` LangGraph milestone. It proves:

- the service is up
- the service can create threads
- a run can pause for approval and resume
- Postgres-backed state survives a pod restart

## Prerequisites

- `kubectl` points at the live cluster with:
  - `/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig`
- `vLLM` is already healthy in the `ai` namespace
- `postgres` and `langgraph` are healthy in the `agents` namespace

## 1. Health check

```bash
kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig -n agents port-forward svc/langgraph 18081:8000
```

In another terminal:

```bash
curl http://127.0.0.1:18081/healthz
```

Expected:

- `ok: true`
- `database: ok`
- `model_backend` points at the in-cluster `vLLM` service
- `semantic_memory_provider` is `none`
- `archive_sink` is `none`

## 2. Create a thread

```bash
curl -s http://127.0.0.1:18081/threads \
  -H 'Content-Type: application/json' \
  -d '{"title":"cluster smoke"}'
```

Save the returned `thread_id`.

## 3. Start a run that requires approval

```bash
THREAD_ID="<thread-id>"

curl -s http://127.0.0.1:18081/threads/${THREAD_ID}/runs \
  -H 'Content-Type: application/json' \
  -d '{
    "message": "Say hello from the live cluster in six words.",
    "require_approval": true
  }'
```

Expected:

- `status` is `waiting_for_approval`
- `interrupts` contains the pending approval payload

Save the returned `run_id`.

## 4. Resume the run

```bash
curl -s http://127.0.0.1:18081/threads/${THREAD_ID}/resume \
  -H 'Content-Type: application/json' \
  -d '{"approved": true}'
```

Expected:

- `status` is `completed`
- `response_text` contains a model response

## 5. Fetch the thread state

```bash
curl -s http://127.0.0.1:18081/threads/${THREAD_ID}
```

Expected:

- run history is present
- `checkpoint_count` is greater than zero
- latest state includes both the human message and the model response

## 6. Prove persistence across a pod restart

Delete the current pod:

```bash
kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig -n agents delete pod -l app.kubernetes.io/name=langgraph
```

Wait for the replacement pod:

```bash
kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig -n agents wait --for=condition=ready pod -l app.kubernetes.io/name=langgraph --timeout=180s
```

Then fetch the same thread again:

```bash
curl -s http://127.0.0.1:18081/threads/${THREAD_ID}
```

Expected:

- the same `thread_id` still exists
- prior `runs` are still present
- `checkpoint_count` is unchanged or greater

If this passes, the `v0.3.0` durability claim is real.
