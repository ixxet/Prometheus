# ASHTON Event Boundary Validation

This runbook covers the bounded live cluster proof for:

- `ATHENA -> NATS -> APOLLO`

It does not widen into a general APOLLO product rollout.

## Scope

The live cluster slice is intentionally narrow:

- `athena` publishes identified visit-lifecycle events from the mock adapter
- `nats` carries the live subject bytes
- `apollo` consumes those bytes and persists visit history in Postgres

## Current live images

- `ATHENA`: `ghcr.io/ixxet/athena:0.2.1@sha256:b9aafb3e4ec8e88b1a1929f12ff9c7afe9286e8ab4eeb969a1b022097065cf29`
- `APOLLO`: `ghcr.io/ixxet/apollo:sha-bf3119b@sha256:ed3f3681b65a889ee563e8e0917fa3caba17cbceddb26a89393882ee287a3748`
- `NATS`: `docker.io/library/nats:2.11.4-alpine@sha256:b8d6a01568a7837d5186f948a3ebfae1bdf5a602268273b50704655982596b22`

## Render checks

```bash
kustomize build /Users/zizo/Personal-Projects/Computers/Prometheus/homelab-gitops/apps/athena
kubectl kustomize /Users/zizo/Personal-Projects/Computers/Prometheus/homelab-gitops/apps/athena
kustomize build /Users/zizo/Personal-Projects/Computers/Prometheus/homelab-gitops/apps/agents
kubectl kustomize /Users/zizo/Personal-Projects/Computers/Prometheus/homelab-gitops/apps
```

## Reconcile

```bash
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig flux reconcile source git flux-system -n flux-system
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig flux reconcile kustomization infra-postgres -n flux-system --with-source
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig flux reconcile kustomization apps -n flux-system --with-source
```

## Rollout verification

```bash
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl rollout status -n athena deployment/athena --timeout=180s
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl rollout status -n agents deployment/nats --timeout=180s
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl rollout status -n agents deployment/apollo --timeout=180s
```

## Live inspection

```bash
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl get deploy,pods,svc -n athena
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl get deploy,pods,svc -n agents | rg 'apollo|nats|postgres'
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl get deploy -n athena athena -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}'
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl get deploy -n agents apollo -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}'
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl logs -n athena deployment/athena --tail=100
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl logs -n agents deployment/apollo --tail=100
```

## Service checks

```bash
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl -n athena port-forward svc/athena 18082:80
curl -i http://127.0.0.1:18082/api/v1/health
curl -i 'http://127.0.0.1:18082/api/v1/presence/count?facility_id=ashtonbee'

KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl -n agents port-forward svc/apollo 18084:80
curl -i http://127.0.0.1:18084/api/v1/health

KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl -n agents port-forward svc/nats 18222:8222
curl -sS http://127.0.0.1:18222/varz
curl -sS http://127.0.0.1:18222/connz
```

## Validation fixture

The bounded live proof uses one known claimed tag:

- student: `tracer2-student-001`
- tag hash: `tag_tracer2_001`

Seed it only if the row does not exist already:

```bash
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl exec -i -n agents postgres-0 -- env PGPASSWORD='<postgres-password>' psql -U langgraph -d langgraph <<'SQL'
INSERT INTO apollo.users (id, student_id, display_name, email)
VALUES ('11111111-1111-1111-1111-111111111111', 'tracer2-student-001', 'Tracer Two', 'tracer2-student-001@example.com')
ON CONFLICT (student_id) DO NOTHING;

INSERT INTO apollo.claimed_tags (id, user_id, tag_hash, label, is_active)
VALUES ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', 'tag_tracer2_001', 'Tracer 2 Mock Tag', TRUE)
ON CONFLICT (tag_hash) DO NOTHING;
SQL
```

## Live boundary proof

The ATHENA deployment already publishes one identified arrival on startup.
Replay can be proven explicitly from the live pod:

```bash
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl exec -n athena deploy/athena -- /usr/local/bin/athena presence publish-identified --format json
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl exec -n agents deploy/apollo -- /usr/local/bin/apollo visit list --student-id tracer2-student-001 --format json
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl exec -n agents postgres-0 -- env PGPASSWORD='<postgres-password>' psql -U langgraph -d langgraph -c "SELECT facility_key, source_event_id, departure_source_event_id, arrived_at, departed_at FROM apollo.visits ORDER BY arrived_at DESC;"
```

Expected evidence:

- ATHENA logs `identified arrival published event_id=mock-in-001`
- APOLLO logs `identified presence handled event_id=mock-in-001 outcome=created`
- replay logs `identified presence handled event_id=mock-in-001 outcome=duplicate`
- `apollo.workouts` remains unchanged for this proof

## Rollback

If this bounded live slice needs to be backed out:

1. Revert the Git commit that added `apps/agents/nats/`, `apps/agents/apollo/`, or the ATHENA publish env in `apps/athena/athena-deployment.yaml`.
2. Push the revert to `main`.
3. Reconcile Flux again:

```bash
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig flux reconcile source git flux-system -n flux-system
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig flux reconcile kustomization apps -n flux-system --with-source
```

4. Verify the rollback rollout:

```bash
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl get deploy,pods,svc -n athena
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl get deploy,pods,svc -n agents | rg 'apollo|nats'
```

If the revert removes APOLLO or NATS from the cluster, the Milestone 1 deployed
truth falls back to the narrower ATHENA read-path-only claim.
