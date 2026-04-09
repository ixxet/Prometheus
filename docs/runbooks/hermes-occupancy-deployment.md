# HERMES Occupancy Deployment Runbook

## Purpose

This runbook documents the bounded live deployment shape for the existing
read-only `HERMES` occupancy slice.

The goal is narrow:

- run `HERMES` as an internal-only runner in `agents`
- execute `hermes ask occupancy --facility <id>` in cluster against live ATHENA
- prove repeated live reads and bounded negative behavior

This runbook does **not** claim:

- a public HERMES service
- write authority
- a broader operator assistant surface
- Tracer 17 completion

## Current Deployment Truth

Milestone 1.7 is a deploy-only closeout.

The deployed HERMES shape is:

- `Deployment/hermes`
- `ServiceAccount/hermes`
- `Secret/hermes-ghcr-pull`

The deployment is intentionally internal-only:

- namespace: `agents`
- replicas: `1`
- no `Service`
- no `Ingress`
- no `ServiceMonitor`
- no extra RBAC beyond the service account pull-auth wiring
- live proof path is `kubectl exec`, not a public API

## Image And Runtime Wiring

- image:
  `ghcr.io/ixxet/hermes:sha-b637575@sha256:3c1af71781e49836be2af8e9f9e95ead1ec6e7cc5547507af0d7442e1a1d0d21`
- runtime version observed in logs: `v0.1.1-2-gb637575`
- upstream:
  `http://athena.athena.svc.cluster.local`
- timeout:
  `5s`

The cluster authenticates to GHCR through `imagePullSecrets` on
`ServiceAccount/hermes`. That is deployment wiring only; it does not widen the
runtime surface.

## Render Checks

```bash
kustomize build /Users/zizo/Personal-Projects/Computers/Prometheus/homelab-gitops/apps/agents/hermes
kustomize build /Users/zizo/Personal-Projects/Computers/Prometheus/homelab-gitops/apps/agents
kubectl kustomize /Users/zizo/Personal-Projects/Computers/Prometheus/homelab-gitops/apps
```

## Validated Operator Sequence

```bash
export KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig

kustomize build /Users/zizo/Personal-Projects/Computers/Prometheus/homelab-gitops/apps/agents/hermes
kustomize build /Users/zizo/Personal-Projects/Computers/Prometheus/homelab-gitops/apps/agents
kubectl kustomize /Users/zizo/Personal-Projects/Computers/Prometheus/homelab-gitops/apps

flux reconcile source git flux-system -n flux-system
flux reconcile kustomization apps -n flux-system --with-source

kubectl rollout status -n agents deployment/hermes --timeout=180s
kubectl get deploy,pods -n agents | rg hermes
kubectl describe deployment -n agents hermes
kubectl logs -n agents deployment/hermes --since=5m
```

## Live Occupancy Proof

The validated live proof used repeated in-cluster execs against the dormant
runner:

```bash
kubectl exec -n agents deploy/hermes -- /bin/sh -lc '/usr/local/bin/hermes ask occupancy --facility ashtonbee --format json 2>/proc/1/fd/2'
kubectl exec -n agents deploy/hermes -- /bin/sh -lc '/usr/local/bin/hermes ask occupancy --facility ashtonbee --format json 2>/proc/1/fd/2'
kubectl exec -n agents deploy/hermes -- /bin/sh -lc '/usr/local/bin/hermes ask occupancy --facility ashtonbee --format json 2>/proc/1/fd/2'
kubectl logs -n agents deployment/hermes --since=5m
```

Validated outputs:

- three successful reads for `facility_id=ashtonbee`
- `source_service=athena`
- `current_count=0`
- structured `request-start` and `request-complete` log pairs for each read

## Bounded Negative Proof

Validated negative proof stayed intentionally narrow:

1. deployed runner with blank `--facility`
2. deployed runner with unknown facility id
3. isolated local harness with bad ATHENA base URL
4. isolated local harness with short timeout
5. isolated local harness returning upstream `500`

Observed results:

- blank facility failed with `validation_error`
- unknown facility stayed source-backed and returned `current_count=0`
- bad base URL failed with `upstream_error`
- short timeout failed with `upstream_timeout`
- upstream `500` failed with `upstream_error` and `upstream_status=500`

## Truth Split

Verified local/runtime truth:

- HERMES runtime remains occupancy-only and read-only
- no Go runtime change was required for deployment proof
- image packaging exists for `linux/amd64`

Verified deployed truth:

- HERMES is live in cluster as a bounded internal runner deployment
- no public HERMES ingress or service exists
- live ATHENA-backed occupancy reads succeed repeatedly through the deployed path

Deferred truth:

- any public HERMES surface
- any write-capable operator flow
- any broader assistant behavior
- Tracer 17 reporting or reconciliation

## Rollback

If this bounded live slice needs to be backed out:

1. revert the Git change that added `apps/agents/hermes/`
2. push the revert to `main`
3. reconcile Flux again:

```bash
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig flux reconcile source git flux-system -n flux-system
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig flux reconcile kustomization apps -n flux-system --with-source
```

4. verify the rollback:

```bash
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl get deploy,pods -n agents | rg hermes
```
