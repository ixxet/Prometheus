# Runtime Checks And Quick Runbook

Last updated: 2026-03-26 (America/Toronto)

## What this is for

This file is the fast path for checking the live cluster without rereading the
full project docs. Commands are grouped by what you are trying to verify.

If the tower has just returned from a Windows session, use the scripted path
first:

```bash
/Users/zizo/Personal-Projects/Computers/Prometheus/scripts/verify-after-talos-return.sh
```

## Current service map

| Service | Namespace | Type | Address | Expected state |
| --- | --- | --- | --- | --- |
| Talos API | node | Talos API | `192.168.2.49:50000` | reachable from the control station |
| Kubernetes API | cluster | VIP | `192.168.2.46:6443` | reachable |
| AdGuard Home | `dns` | `LoadBalancer` | `192.168.2.200` | serving the admin UI and direct-query rewrites; router cutover deferred |
| Open WebUI | `ai` | `LoadBalancer` | `192.168.2.201` | serving `200 OK` |
| vLLM | `ai` | `LoadBalancer` | `192.168.2.205:8000` | serving `/v1/models` |
| Postgres | `agents` | `ClusterIP` | in-cluster only | running |
| LangGraph | `agents` | `ClusterIP` | in-cluster only | serving `/healthz`, thread APIs, Mem0-backed semantic memory, and filesystem archive exports |
| Qdrant | `semantic-memory` | `ClusterIP` | in-cluster only | `readyz` returns healthy |
| TEI embeddings | `semantic-memory` | `ClusterIP` | in-cluster only | `/health` returns healthy |
| Obsidian archive sink | external on MIMIR | NFS-backed filesystem | `/srv/obsidian/prometheus-vault/Agents` | receives Markdown exports from completed LangGraph runs |

## Control station commands

| Goal | Command | Success signal |
| --- | --- | --- |
| Full post-return verification | `/Users/zizo/Personal-Projects/Computers/Prometheus/scripts/verify-after-talos-return.sh` | Talos, Kubernetes, Flux, core pods, LAN endpoints, and LangGraph health all pass |
| Talos health | `talosctl --talosconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/talosconfig -n 192.168.2.49 health` | health checks pass |
| Kubernetes nodes | `kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig get nodes -o wide` | node is `Ready` |
| Flux state | `kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig -n flux-system get kustomizations` | infra entries `True`; `apps` `True` on the current revision |
| GPU allocatable | `kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig describe node talos-p0d-y77 | rg nvidia.com/gpu` | `nvidia.com/gpu: 1` |

## Storage checks

| Goal | Command | Success signal |
| --- | --- | --- |
| PVC inventory | `kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig get pvc -A` | PVCs are `Bound` |
| Local-path volume path | `talosctl --talosconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/talosconfig -n 192.168.2.49 ls /var/mnt/local-path-provisioner` | directory exists |
| Mount usage | `talosctl --talosconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/talosconfig -n 192.168.2.49 df` | OS SSD still has headroom |

## AI namespace checks

| Goal | Command | Success signal |
| --- | --- | --- |
| Pod status | `kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig -n ai get pods -o wide` | `open-webui` and `vllm` both `1/1` |
| Open WebUI logs | `kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig -n ai logs deploy/open-webui --tail=100` | no crash loop |
| vLLM logs | `kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig -n ai logs deploy/vllm --tail=200` | API server reaches steady state and no fatal KV-cache error appears |
| vLLM previous crash | `kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig -n ai logs deploy/vllm --previous --tail=200` | old crash reason is understood before changing manifests |
| vLLM service via port-forward | `kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig -n ai port-forward svc/vllm 18000:8000` then `curl http://127.0.0.1:18000/v1/models` | JSON response once ready |

## Agents namespace checks

| Goal | Command | Success signal |
| --- | --- | --- |
| LangGraph pod status | `kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig -n agents get pods -o wide` | `langgraph` and `postgres` are `1/1` |
| LangGraph logs | `kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig -n agents logs deploy/langgraph --tail=200` | startup completes without DB or model-backend errors |
| LangGraph health | `kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig -n agents port-forward svc/langgraph 18081:8000` then `curl http://127.0.0.1:18081/healthz` | JSON shows `ok: true`, the expected `vLLM` backend, `semantic_memory_provider: mem0`, and `archive_sink: filesystem_markdown` |
| LangGraph thread smoke test | `kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig -n agents port-forward svc/langgraph 18081:8000` then use the commands in `docs/runbooks/langgraph-validation.md` | thread create, run, resume, and fetch all succeed |
| Semantic-memory smoke test | `kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig -n agents port-forward svc/langgraph 18081:8000` and `kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig -n semantic-memory port-forward svc/qdrant 16333:6333` then use `docs/runbooks/semantic-memory-activation.md` | a preference written in one thread is recalled in a fresh thread |
| Archive export smoke test | `kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig -n agents port-forward svc/langgraph 18081:8000` then use `docs/runbooks/archive-export-validation.md` | a completed run writes a Markdown file into MIMIR's `Agents/` vault path |
| First real workflow smoke test | `kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig -n agents port-forward svc/langgraph 18081:8000` then use `docs/runbooks/first-agent-workflow.md` | approval, Postgres state, Mem0 recall, and MIMIR archive export all succeed in one path |

## Semantic-memory namespace checks

| Goal | Command | Success signal |
| --- | --- | --- |
| Support stack status | `kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig -n semantic-memory get pods,svc,pvc -o wide` | `qdrant` and `tei-embeddings` are `1/1`; both PVCs are `Bound` |
| Qdrant health | `kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig -n semantic-memory port-forward svc/qdrant 16333:6333` then `curl http://127.0.0.1:16333/readyz` | `all shards are ready` |
| TEI health | `kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig -n semantic-memory port-forward svc/tei-embeddings 18082:80` then `curl http://127.0.0.1:18082/health` | HTTP `200` |

## DNS checks

| Goal | Command | Success signal |
| --- | --- | --- |
| AdGuard pod | `kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig -n dns get pods,svc,pvc` | pod running, PVC bound, `192.168.2.200` assigned |
| AdGuard admin UI | `curl -I http://192.168.2.200` | `302` to `/login.html` or `200` on `/login.html` |
| AdGuard rewrite checks | `for name in k8s.home.arpa adguard.home.arpa openwebui.home.arpa vllm.home.arpa; do dig +short @192.168.2.200 $name; done` | returns the expected `192.168.2.x` addresses |
| AdGuard real-client check | temporarily point a real client at `192.168.2.200` and use `getent ahostsv4 openwebui.home.arpa`, `curl -I http://openwebui.home.arpa/`, and `curl http://vllm.home.arpa:8000/v1/models` | name resolution and HTTP checks pass without using `@192.168.2.200` direct-query shortcuts |
| AdGuard public DNS check | `dig +short @192.168.2.200 github.com` | returns a public IP |
| Router cutover reminder | manual | only do this after AdGuard rewrites are configured |

## LAN endpoint checks

| Goal | Command | Success signal |
| --- | --- | --- |
| Open WebUI on LAN | `curl -I http://192.168.2.201/` | `HTTP/1.1 200 OK` |
| vLLM on LAN | `curl http://192.168.2.205:8000/v1/models` | JSON response once ready |
| AdGuard on LAN | `curl -I http://192.168.2.200/` | `302` to `/login.html` or `200` after login |

## Remote access note

Recommended remote pattern:

- run Tailscale on the Mac
- add Tailscale to a reachable always-on node at home
- make that node a subnet router for `192.168.2.0/24`
- then use the same `talosctl`, `kubectl`, and `curl` commands remotely

Current validated path:

- MIMIR advertises `192.168.2.0/24` into Tailscale
- the control Mac can reach Talos, Kubernetes, and the service IPs remotely
- this keeps Talos itself untouched while remote ops stay available

## If the AI layer regresses

If `open-webui` is healthy and `vllm` is not, check the `vllm` logs first.
Known failure modes already seen in this repo:

- service-link env injection can collide with `VLLM_PORT`
- single-GPU rolling updates can deadlock unless the deployment uses `Recreate`
- slow WAN links can make model distribution fail long after the container image is present
- the default `32768` token context window can exceed the RTX 3090 KV-cache budget

The practical workflow is:

1. check `kubectl -n ai get pods`
2. check `kubectl -n ai logs deploy/vllm --tail=200`
3. verify `curl http://192.168.2.205:8000/v1/models`
4. only then change manifests

## If the agent layer regresses

1. check `kubectl -n agents get pods`
2. check `kubectl -n agents logs deploy/langgraph --tail=200`
3. verify `curl http://127.0.0.1:18081/healthz` through a port-forward
4. run the smoke test from `docs/runbooks/langgraph-validation.md`
5. if persistence is the concern, delete the LangGraph pod and repeat the final
   `GET /threads/{thread_id}` check after the replacement pod is ready
6. if semantic memory is the concern, verify `OPENAI_API_KEY` exists in the
   ConfigMap, check `kubectl -n semantic-memory get pods`, and rerun the
   semantic-memory smoke test
7. if archive export is the concern, verify `langgraph-archive` is `Bound`,
   confirm the deployment still mounts `/exports/obsidian`, and rerun the
   archive-export smoke test
