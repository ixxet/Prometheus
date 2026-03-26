# Prometheus LangGraph Runtime

This is the first self-hosted OSS LangGraph service for Prometheus.

Design goals for `v0.3.0`:

- Postgres is the only durable store
- no Redis
- no LangSmith dependency
- no hosted LangGraph license requirement
- small, explicit HTTP surface instead of a generic framework dump

## Endpoints

- `GET /healthz`
- `POST /threads`
- `GET /threads/{thread_id}`
- `POST /threads/{thread_id}/runs`
- `POST /threads/{thread_id}/resume`

## Workflow shape

- multi-turn execution through a stable `thread_id`
- LangGraph persistence through `langgraph-checkpoint-postgres`
- optional human approval interrupt before model execution
- direct model calls to the in-cluster `vLLM` OpenAI-compatible endpoint

## Local development

```bash
cd /Users/zizo/Personal-Projects/Computers/Prometheus/services/langgraph
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```
