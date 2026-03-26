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
| AdGuard Home | `dns` | `LoadBalancer` | `192.168.2.200:3000` | first-run setup UI reachable; router cutover deferred |
| Open WebUI | `ai` | `LoadBalancer` | `192.168.2.201` | serving `200 OK` |
| vLLM | `ai` | `LoadBalancer` | `192.168.2.205:8000` | should answer `/v1/models` once startup sizing is correct |
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
| vLLM logs | `kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig -n ai logs deploy/vllm --tail=200` | model load completes and no fatal KV-cache error appears |
| vLLM previous crash | `kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig -n ai logs deploy/vllm --previous --tail=200` | old crash reason is understood before changing manifests |
| vLLM service via port-forward | `kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig -n ai port-forward svc/vllm 18000:8000` then `curl http://127.0.0.1:18000/v1/models` | JSON response once ready |

## DNS checks

| Goal | Command | Success signal |
| --- | --- | --- |
| AdGuard pod | `kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig -n dns get pods,svc,pvc` | pod running, PVC bound, `192.168.2.200` assigned |
| AdGuard setup UI | `curl -I http://192.168.2.200:3000` | `302` to `/install.html` or `200` on `/install.html` |
| Router cutover reminder | manual | only do this after AdGuard rewrites are configured |

## LAN endpoint checks

| Goal | Command | Success signal |
| --- | --- | --- |
| Open WebUI on LAN | `curl -I http://192.168.2.201/` | `HTTP/1.1 200 OK` |
| vLLM on LAN | `curl http://192.168.2.205:8000/v1/models` | JSON response once ready |
| AdGuard on LAN | `curl -I http://192.168.2.200:3000` | `302` to `/install.html` during first launch |

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

## Interpreting the current AI hangup

If `open-webui` is healthy and `vllm` is not, check the `vllm` logs first.
Current known failure mode:

- model weights are already cached on the PVC
- the pod is restarting because the default `32768` token context window is
  larger than the current KV-cache budget on the RTX 3090
- the practical fix is to lower `--max-model-len` or increase GPU memory
  reservation, not to keep waiting on image pulls
