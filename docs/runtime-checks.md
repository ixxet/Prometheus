# Runtime Checks And Quick Runbook

Last updated: 2026-03-25 (America/Toronto)

## What this is for

This file is the fast path for checking the live cluster without rereading the
full project docs. Commands are grouped by what you are trying to verify.

## Current service map

| Service | Namespace | Type | Address | Expected state |
| --- | --- | --- | --- | --- |
| Talos API | node | Talos API | `192.168.2.49:50000` | reachable from the control station |
| Kubernetes API | cluster | VIP | `192.168.2.46:6443` | reachable |
| AdGuard Home | `dns` | `LoadBalancer` | `192.168.2.200` | running, router cutover deferred |
| Open WebUI | `ai` | `LoadBalancer` | `192.168.2.201` | serving `200 OK` |
| vLLM | `ai` | `LoadBalancer` | `192.168.2.205:8000` | should answer `/v1/models` once model load finishes |
| Postgres | `agents` | `ClusterIP` | in-cluster only | running |

## Control station commands

| Goal | Command | Success signal |
| --- | --- | --- |
| Talos health | `talosctl --talosconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/talosconfig -n 192.168.2.49 health` | health checks pass |
| Kubernetes nodes | `kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig get nodes -o wide` | node is `Ready` |
| Flux state | `kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig -n flux-system get kustomizations` | infra entries `True`; `apps` only green when `vllm` is ready |
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
| Pod status | `kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig -n ai get pods -o wide` | `open-webui` running; `vllm` eventually `1/1` |
| Open WebUI logs | `kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig -n ai logs deploy/open-webui --tail=100` | no crash loop |
| vLLM logs | `kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig -n ai logs deploy/vllm --tail=200` | model load progresses without fatal error |
| vLLM service via port-forward | `kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig -n ai port-forward svc/vllm 18000:8000` then `curl http://127.0.0.1:18000/v1/models` | JSON response once ready |

## DNS checks

| Goal | Command | Success signal |
| --- | --- | --- |
| AdGuard pod | `kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig -n dns get pods,svc,pvc` | pod running, PVC bound, `192.168.2.200` assigned |
| AdGuard HTTP | `curl -I http://192.168.2.200` | HTTP response |
| Router cutover reminder | manual | only do this after AdGuard rewrites are configured |

## LAN endpoint checks

| Goal | Command | Success signal |
| --- | --- | --- |
| Open WebUI on LAN | `curl -I http://192.168.2.201/` | `HTTP/1.1 200 OK` |
| vLLM on LAN | `curl http://192.168.2.205:8000/v1/models` | JSON response once ready |
| AdGuard on LAN | `curl -I http://192.168.2.200` | HTTP response |

## Remote access note

Recommended remote pattern:

- run Tailscale on the Mac
- add Tailscale to a reachable always-on node at home
- make that node a subnet router for `192.168.2.0/24`
- then use the same `talosctl`, `kubectl`, and `curl` commands remotely

Until a home subnet router exists, Git pushes still work remotely, but live
validation of Talos, Kubernetes, and `LoadBalancer` services stays LAN-bound.

## Interpreting the current AI hangup

If `open-webui` is healthy and `vllm` is not, check the `vllm` logs first.
Current known failure mode:

- model weights downloading too slowly from Hugging Face over an `~8 Mbps` link
- pod remains `0/1` because readiness waits for `/v1/models`
- this is a data-plane delay, not a container image pull problem
