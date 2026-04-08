# ASHTON Deployable Check Status (Milestone 1.6 Historical Snapshot)

This runbook records the pre-hardening deployable check that supported the
ASHTON Milestone 1.6 boundary:

- `ATHENA -> NATS -> APOLLO` live departure-close proof

This file is historical validation for Milestone 1.6. It is not the current
ATHENA edge-ingress deployment ledger. For the later bounded `athena v0.4.1`
edge deployment truth, use
`homelab-gitops/docs/runbooks/athena-edge-deployment.md`.

Use this checklist before starting hardening execution. If any blocking gate is
red, do not claim deployment truth.

This file is a point-in-time preflight snapshot. Rerun the reusable command
block at the bottom before claiming current deployability.

## Gate Checklist

| Gate | What must be true | Status now | Blocking? | Evidence |
| --- | --- | --- | --- | --- |
| Prometheus GitOps repo state | repo on `main`, no local drift for release run | PASS | No | clean on the recorded revision; see snapshot below |
| Cluster reachability | kube context reachable and node ready | PASS | No | single control-plane node `Ready` |
| Flux source | `flux-system` source reconciles to expected revision | PASS | No | reconciled to one known recorded revision; see snapshot below |
| Flux infra chain | infra kustomizations healthy (`infra-cilium`, `infra-network`, `infra-storage`, `infra-postgres`, `infra-dns`, `infra-observability`, `infra-nvidia`) | PASS | No | all `READY=True` after reconcile |
| Flux apps | `apps` kustomization healthy at same revision | PASS | No | `apps READY=True` at the same recorded revision |
| Core workloads | `athena`, `apollo`, `nats` deployments available | PASS | No | rollout status successful for all three |
| Service wiring | ATHENA has `ATHENA_NATS_URL`; APOLLO has `APOLLO_NATS_URL`; APOLLO secret refs resolve | PASS | No | deploy envs + secret key refs verified |
| Runtime health | ATHENA and APOLLO health endpoints return `200` | PASS | No | `/api/v1/health` checks succeeded |
| Runtime boundary pre-signal | ATHENA occupancy endpoint returns expected shape and count | PASS | No | `current_count=9` for `ashtonbee` |
| NATS monitor | NATS monitor reachable; connection count nonzero | PASS | No | `/varz` + `/connz` reachable; `num_connections=2` |
| Milestone 1.6 truth scope | no accidental widening into non-goals | PASS | No | no HERMES/gateway/APOLLO product widening in this preflight |

## Current Snapshot

Snapshot time (UTC): `2026-04-03T22:59:16Z`

### Git/Revision Truth

- Prometheus repo: clean, `main`, `70c92a6b919371183e403eb208a5119b685974de`
- Flux revision in cluster: `main@sha1:70c92a6b`

### Flux Health

- `apps`: `READY=True`
- `infra-cilium`: `READY=True`
- `infra-network`: `READY=True`
- `infra-storage`: `READY=True`
- `infra-postgres`: `READY=True`
- `infra-dns`: `READY=True`
- `infra-observability`: `READY=True`
- `infra-nvidia`: `READY=True`
- `infra-semantic-memory`: `READY=True`

### Workload State

- Namespace `athena`:
  - `deployment/athena` available (`1/1`)
  - `pod/athena-767dc9597-mxvgr` running
- Namespace `agents`:
  - `deployment/apollo` available (`1/1`)
  - `deployment/nats` available (`1/1`)
  - `pod/apollo-6cd6d457-tbrsx` running
  - `pod/nats-55bfc5dfbd-8xbgt` running

### Runtime Wiring Proof

- ATHENA deployment image is digest-pinned:
  - `ghcr.io/ixxet/athena:0.4.0@sha256:8fcf9b9cff28a3c417771d350cfb9d02ecb865507aa48f7c3ac9cc7d4b7cdc19`
- APOLLO deployment image is digest-pinned:
  - `ghcr.io/ixxet/apollo:sha-bf3119b@sha256:ed3f3681b65a889ee563e8e0917fa3caba17cbceddb26a89393882ee287a3748`
- ATHENA env includes:
  - `ATHENA_ADAPTER=mock`
  - `ATHENA_NATS_URL=nats://nats.agents.svc.cluster.local:4222`
  - `ATHENA_MOCK_IDENTIFIED_EXIT_TAG_HASHES=tag_tracer2_001`
- APOLLO env includes:
  - `APOLLO_NATS_URL=nats://nats.agents.svc.cluster.local:4222`
  - `APOLLO_DATABASE_URL` from secret key `database-url` in secret `apollo-runtime`
  - `APOLLO_SESSION_COOKIE_SECRET` from secret key `session-cookie-secret` in secret `apollo-runtime`

### Runtime Endpoint Proof

- ATHENA:
  - `/api/v1/health` -> `200 {"service":"athena","status":"ok","adapter":"mock"}`
  - `/api/v1/presence/count?facility=ashtonbee` -> `200 ... "current_count":9 ...`
- APOLLO:
  - `/api/v1/health` -> `200 {"service":"apollo","status":"ok","consumer_enabled":true}`
- NATS monitor:
  - `/varz` reachable (`connections=2`, `in_msgs=1`, `out_msgs=0`)
  - `/connz?subs=0` reachable (`num_connections=2`)

## Things To Be Wary Of

These are not blockers for starting Milestone 1.6 hardening, but they are
operational risks to watch while proving live departure-close:

1. Flux status can look stale until explicit reconcile runs are performed.
   - Run reconcile sequence first, then trust readiness.
2. Pod restarts were observed on both ATHENA and APOLLO.
   - Keep watch on restart counters during live publish/consume tests.
3. ATHENA in cluster is still `mock` adapter right now.
   - Milestone 1.6 claim must stay about departure-close boundary, not
     source-backed ingress deployment.
4. NATS counters are low pre-test (`in_msgs=1`, `out_msgs=0`).
   - Expect counters and logs to move during live departure test; if they do
     not move, boundary proof is failing.
5. Secret values are not visible by design in deployment env dumps.
   - Validate secret key refs and runtime behavior, not raw secret output.
6. Health endpoints can be green while boundary behavior still fails.
   - Always pair health checks with publish/log/database evidence.
7. A healthy cluster can still look dead from the wrong shell.
   - If `kubectl` has no current context, `flux` and `kubectl` can fall back to
     `localhost:8080`.
   - Export the explicit Talos kubeconfig before trusting any preflight
     failure.

## Go / No-Go Rule

Go for Milestone 1.6 hardening execution only if:

- Flux and apps are `READY=True` at one known revision
- ATHENA/APOLLO/NATS workloads are available
- ATHENA/APOLLO health endpoints are reachable
- NATS monitor is reachable
- wiring for NATS and APOLLO runtime secrets is verified

No-go if any of the above is false.

## Reusable Command Block

```bash
# Operator context
export KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig
kubectl config current-context
kubectl cluster-info
flux check

# Repo truth
git -C /Users/zizo/Personal-Projects/Computers/Prometheus status --short
git -C /Users/zizo/Personal-Projects/Computers/Prometheus branch --show-current
git -C /Users/zizo/Personal-Projects/Computers/Prometheus rev-parse HEAD

# Cluster and Flux truth
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl get nodes -o wide
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig flux reconcile source git flux-system -n flux-system
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig flux reconcile kustomization infra-cilium -n flux-system --with-source
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig flux reconcile kustomization infra-network -n flux-system --with-source
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig flux reconcile kustomization infra-storage -n flux-system --with-source
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig flux reconcile kustomization infra-postgres -n flux-system --with-source
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig flux reconcile kustomization infra-dns -n flux-system --with-source
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig flux reconcile kustomization infra-observability -n flux-system --with-source
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig flux reconcile kustomization infra-nvidia -n flux-system --with-source
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig flux reconcile kustomization apps -n flux-system --with-source
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig flux get kustomizations -A

# Workload state
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl get deploy,pods,svc -n athena
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl get deploy,pods,svc -n agents
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl rollout status -n athena deployment/athena --timeout=180s
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl rollout status -n agents deployment/apollo --timeout=180s
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl rollout status -n agents deployment/nats --timeout=180s

# Runtime wiring
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl get deploy -n athena athena -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}'
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl get deploy -n agents apollo -o yaml | rg 'APOLLO_DATABASE_URL|APOLLO_SESSION_COOKIE_SECRET|secretKeyRef|name: apollo-runtime'

# Runtime health
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl -n athena port-forward svc/athena 18082:80
curl -i http://127.0.0.1:18082/api/v1/health
curl -i 'http://127.0.0.1:18082/api/v1/presence/count?facility=ashtonbee'

KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl -n agents port-forward svc/apollo 18084:80
curl -i http://127.0.0.1:18084/api/v1/health

KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl -n agents port-forward svc/nats 18222:8222
curl -sS http://127.0.0.1:18222/varz
curl -sS 'http://127.0.0.1:18222/connz?subs=0'
```
