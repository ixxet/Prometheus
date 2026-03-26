# First Agent Workflow Runbook

Last updated: 2026-03-26 (America/Toronto)

## Purpose

This runbook defines and validates the first real agent workflow for the
`v0.5.0` milestone. It proves the full runtime path instead of only isolated
smoke checks:

- a request enters LangGraph
- LangGraph persists execution state in Postgres
- a run pauses for approval and resumes cleanly
- `vLLM` serves the model response
- Mem0 records a durable preference
- a later thread recalls that preference
- the completed run exports Markdown to the off-tower MIMIR vault

This workflow is intentionally operator-facing and read-only. It does not
mutate the cluster.

## Workflow shape

Name:

- `approval-gated operator brief`

Intent:

- capture a durable operator preference
- produce a short change-preflight brief
- require explicit approval before model execution
- leave behind both machine state and human-readable output

Standalone diagram source:
[`docs/diagrams/first-agent-workflow.mmd`](../diagrams/first-agent-workflow.mmd)

## Prerequisites

- `kubectl` points at the live cluster:
  - `/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig`
- `langgraph`, `postgres`, `vllm`, `qdrant`, and `tei-embeddings` are healthy
- the external archive sink on MIMIR is healthy

## 1. Port-forward LangGraph locally

```bash
kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig \
  -n agents port-forward svc/langgraph 18081:8000
```

In another terminal:

```bash
curl -s http://127.0.0.1:18081/healthz | jq
```

Expected:

- `ok: true`
- `semantic_memory_provider: "mem0"`
- `archive_sink: "filesystem_markdown"`

## 2. Create the operator-brief thread

```bash
THREAD_JSON=$(curl -s http://127.0.0.1:18081/threads \
  -H 'Content-Type: application/json' \
  -d '{"title":"adguard cutover operator brief"}')

echo "$THREAD_JSON" | jq
THREAD_ID=$(echo "$THREAD_JSON" | jq -r '.thread_id')
```

## 3. Start an approval-gated run

```bash
RUN_JSON=$(curl -s http://127.0.0.1:18081/threads/${THREAD_ID}/runs \
  -H 'Content-Type: application/json' \
  -d '{
    "message":"My preferred terminal emulator is WezTerm. Draft a concise three-bullet preflight checklist for an AdGuard router DNS cutover and keep the wording operator-focused.",
    "require_approval": true
  }')

echo "$RUN_JSON" | jq
```

Expected:

- `status: "waiting_for_approval"`
- `interrupts` contains the approval payload

## 4. Resume the run with approval

```bash
curl -s http://127.0.0.1:18081/threads/${THREAD_ID}/resume \
  -H 'Content-Type: application/json' \
  -d '{"approved": true}' | jq
```

Expected:

- `status: "completed"`
- `response_text` contains the preflight checklist

## 5. Confirm persisted execution state

```bash
curl -s http://127.0.0.1:18081/threads/${THREAD_ID} | jq '{
  thread_id,
  title,
  status,
  checkpoint_count,
  runs: [.runs[] | {
    run_id,
    status,
    require_approval,
    response_text
  }]
}'
```

Expected:

- `status: "idle"`
- `checkpoint_count` is greater than `0`
- the completed run is present with `require_approval: true`

## 6. Prove cross-thread semantic recall

Create a second thread:

```bash
RECALL_THREAD_JSON=$(curl -s http://127.0.0.1:18081/threads \
  -H 'Content-Type: application/json' \
  -d '{"title":"semantic recall check"}')

RECALL_THREAD_ID=$(echo "$RECALL_THREAD_JSON" | jq -r '.thread_id')
```

Ask for the previously stored preference:

```bash
curl -s http://127.0.0.1:18081/threads/${RECALL_THREAD_ID}/runs \
  -H 'Content-Type: application/json' \
  -d '{
    "message":"What terminal emulator do I prefer? Answer in one sentence.",
    "require_approval": false
  }' | jq
```

Expected:

- `status: "completed"`
- `response_text` says the preferred terminal emulator is `WezTerm`

## 7. Verify the archive export on MIMIR

```bash
ssh -i /Users/zizo/.ssh/mimir_ed25519 boi@100.109.171.72 \
  'find /srv/obsidian/prometheus-vault/Agents -maxdepth 1 -type f | sort | tail -n 5'
```

Inspect the newest workflow artifact:

```bash
ssh -i /Users/zizo/.ssh/mimir_ed25519 boi@100.109.171.72 \
  'sed -n "1,120p" /srv/obsidian/prometheus-vault/Agents/<filename>.md'
```

Expected:

- the operator-brief artifact exists
- the Markdown includes:
  - `thread_id`
  - `run_id`
  - `Input`
  - `Response`

## 8. Acceptance

This workflow is considered validated when all of the following are true:

- the approval-gated run completes successfully
- thread state remains queryable with checkpoints in Postgres
- the later thread recalls the stored preference through Mem0
- the run artifact exists off-tower on MIMIR

At that point, the first real agent workflow claim is real even if router DNS
cutover is still pending.
