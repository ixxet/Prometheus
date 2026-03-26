# Archive Export Validation Runbook

Last updated: 2026-03-26 (America/Toronto)

## Purpose

This runbook proves the `v0.4.0` archive claim end to end:

- LangGraph completes a run
- the run exports a Markdown artifact
- the artifact lands off-tower on MIMIR
- the artifact stays out of the Git repo

## External sink shape

- Host: MIMIR
- LAN IP: `192.168.2.40`
- Export root: `/srv/obsidian/prometheus-vault`
- LangGraph export directory inside that root: `Agents/`
- Repo responsibility:
  - the NFS-backed PV/PVC
  - LangGraph archive-sink config
  - documentation
- Repo does **not** store:
  - exported Markdown artifacts
  - the Obsidian vault contents themselves

## 1. Verify the runtime and mount are healthy

```bash
kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig -n agents get pods,pvc
kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig get pv langgraph-archive-pv
kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig -n agents port-forward svc/langgraph 18081:8000
```

In another terminal:

```bash
curl http://127.0.0.1:18081/healthz
```

Expected:

- `semantic_memory_provider: "mem0"`
- `archive_sink: "filesystem_markdown"`
- `langgraph-archive` PVC is `Bound`

## 2. Create a thread

```bash
curl -s http://127.0.0.1:18081/threads \
  -H 'Content-Type: application/json' \
  -d '{"title":"obsidian archive smoke"}'
```

Save the returned `thread_id`.

## 3. Run a completion that should be archived

```bash
THREAD_ID="<thread-id>"

curl -s http://127.0.0.1:18081/threads/${THREAD_ID}/runs \
  -H 'Content-Type: application/json' \
  -d '{
    "message": "Summarize in two sentences why Prometheus keeps the archive sink off-tower on MIMIR.",
    "require_approval": false
  }'
```

Expected:

- `status: "completed"`
- `response_text` is present

## 4. Verify the exported Markdown on MIMIR

```bash
ssh -i /Users/zizo/.ssh/mimir_ed25519 boi@100.109.171.72 \
  'find /srv/obsidian/prometheus-vault/Agents -maxdepth 1 -type f | sort | tail -n 5'
```

Then inspect the newest file:

```bash
ssh -i /Users/zizo/.ssh/mimir_ed25519 boi@100.109.171.72 \
  'sed -n "1,120p" /srv/obsidian/prometheus-vault/Agents/<filename>.md'
```

Expected:

- the file exists under `Agents/`
- the Markdown includes:
  - `thread_id`
  - `run_id`
  - `Input`
  - `Response`

## 5. If it regresses

1. check LangGraph health:

```bash
curl http://127.0.0.1:18081/healthz
```

2. verify the PVC and deployment mount:

```bash
kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig -n agents get pvc langgraph-archive
kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig -n agents get deploy langgraph -o yaml | rg -n 'archive-export|ARCHIVE_'
```

3. inspect the LangGraph logs:

```bash
kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig -n agents logs deploy/langgraph --tail=200
```

4. verify the MIMIR export still exists:

```bash
ssh -i /Users/zizo/.ssh/mimir_ed25519 boi@100.109.171.72 \
  'find /srv/obsidian/prometheus-vault -maxdepth 2 -type d | sort'
```

5. if the mount is suspect, confirm the NFSv4.1 path still matches the export
   layout:
  - PV path should be `/prometheus-vault`
  - MIMIR pseudo-root export should be `/srv/obsidian`
  - MIMIR sub-export should be `/srv/obsidian/prometheus-vault`
