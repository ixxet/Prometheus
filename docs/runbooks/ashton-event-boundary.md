# ASHTON Event Boundary Validation

This runbook covers the bounded live cluster proof for:

- `ATHENA -> NATS -> APOLLO`

It does not widen into a general APOLLO product rollout.

Preflight deployable status checklist: [ASHTON Deployable Check Status (Milestone 1.6)](ashton-deployable-check-status.md)

## Operator defaults

Use the same kubeconfig and local repo paths that were used for the validated
Milestone 1.6 proof:

```bash
export KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig
export PROMETHEUS_REPO=/Users/zizo/Personal-Projects/Computers/Prometheus
export ASHTON_ROOT=/Users/zizo/Personal-Projects/ASHTON
```

If `kubectl config current-context` fails or `flux check` falls back to
`http://localhost:8080`, the shell is missing a usable kubeconfig. Treat that
as an operator-context failure, not as cluster proof, until the explicit Talos
kubeconfig is exported.

## Scope

The live cluster slice is intentionally narrow:

- `athena` publishes identified visit-lifecycle events from the mock adapter
- `nats` carries the live subject bytes
- `apollo` consumes those bytes and closes the matching open visit in Postgres

## Current live images

- `ATHENA`: `ghcr.io/ixxet/athena:0.4.0@sha256:8fcf9b9cff28a3c417771d350cfb9d02ecb865507aa48f7c3ac9cc7d4b7cdc19`
- `APOLLO`: `ghcr.io/ixxet/apollo:sha-bf3119b@sha256:ed3f3681b65a889ee563e8e0917fa3caba17cbceddb26a89393882ee287a3748`
- `NATS`: `docker.io/library/nats:2.11.4-alpine@sha256:b8d6a01568a7837d5186f948a3ebfae1bdf5a602268273b50704655982596b22`

## Render checks

```bash
kustomize build /Users/zizo/Personal-Projects/Computers/Prometheus/homelab-gitops/apps/athena
kubectl kustomize /Users/zizo/Personal-Projects/Computers/Prometheus/homelab-gitops/apps/athena
kustomize build /Users/zizo/Personal-Projects/Computers/Prometheus/homelab-gitops/apps/agents
kubectl kustomize /Users/zizo/Personal-Projects/Computers/Prometheus/homelab-gitops/apps
```

## Known-good validation sequence

This is the exact operator order used for the validated live proof.

```bash
kustomize build "$PROMETHEUS_REPO/homelab-gitops/apps/athena"
kubectl kustomize "$PROMETHEUS_REPO/homelab-gitops/apps/athena"
kustomize build "$PROMETHEUS_REPO/homelab-gitops/apps/agents"
kubectl kustomize "$PROMETHEUS_REPO/homelab-gitops/apps"

flux reconcile source git flux-system -n flux-system
flux reconcile kustomization infra-postgres -n flux-system --with-source
flux reconcile kustomization apps -n flux-system --with-source

kubectl rollout status -n athena deployment/athena --timeout=180s
kubectl rollout status -n agents deployment/nats --timeout=180s
kubectl rollout status -n agents deployment/apollo --timeout=180s

kubectl get deploy,pods,svc -n athena
kubectl get deploy,pods,svc -n agents | rg 'apollo|nats|postgres'
kubectl get deploy -n athena athena -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}'
kubectl get deploy -n agents apollo -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}'
kubectl logs -n athena deployment/athena --tail=100
kubectl logs -n agents deployment/apollo --tail=120
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
curl -i 'http://127.0.0.1:18082/api/v1/presence/count?facility=ashtonbee'

KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl -n agents port-forward svc/apollo 18084:80
curl -i http://127.0.0.1:18084/api/v1/health

KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl -n agents port-forward svc/nats 18222:8222
curl -sS http://127.0.0.1:18222/varz
curl -sS http://127.0.0.1:18222/connz
```

The validated responses were:

- `GET /api/v1/health` on ATHENA returned `200`
- `GET /api/v1/presence/count?facility=ashtonbee` on ATHENA returned `200`
- `GET /api/v1/health` on APOLLO returned `200` with `consumer_enabled=true`
- `NATS /varz` moved during the live departure publish and replay sequence

## Validation fixture

The bounded live proof uses one known claimed tag and one deterministic open
visit fixture:

- student: `tracer2-student-001`
- tag hash: `tag_tracer2_001`
- open visit source event: `mock-in-001`

Seed it only if the row does not exist already:

```bash
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl exec -i -n agents postgres-0 -- env PGPASSWORD='<postgres-password>' psql -U langgraph -d langgraph <<'SQL'
INSERT INTO apollo.users (id, student_id, display_name, email)
VALUES ('11111111-1111-1111-1111-111111111111', 'tracer2-student-001', 'Tracer Two', 'tracer2-student-001@example.com')
ON CONFLICT (student_id) DO NOTHING;

INSERT INTO apollo.claimed_tags (id, user_id, tag_hash, label, is_active)
VALUES ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', 'tag_tracer2_001', 'Tracer 2 Mock Tag', TRUE)
ON CONFLICT (tag_hash) DO NOTHING;

INSERT INTO apollo.visits (id, user_id, facility_key, source_event_id, arrived_at, metadata)
VALUES ('983c2888-282d-416c-92d6-2595a776bb7e', '11111111-1111-1111-1111-111111111111', 'ashtonbee', 'mock-in-001', '2026-04-02T18:14:35.288509Z', '{}'::jsonb)
ON CONFLICT (source_event_id) DO NOTHING;
SQL
```

Optional pre-check:

```bash
kubectl exec -n agents postgres-0 -- \
  psql -U langgraph -d langgraph -c "SELECT u.student_id, v.source_event_id, v.departed_at FROM apollo.visits v JOIN apollo.users u ON u.id=v.user_id WHERE u.student_id='tracer2-student-001';"
```

## Live boundary proof

Capture boundary state, publish one departure, then replay the same event id:

```bash
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl exec -n agents postgres-0 -- \
  psql -U langgraph -d langgraph -c "SELECT v.id, v.source_event_id, v.departure_source_event_id, v.arrived_at, v.departed_at FROM apollo.visits v JOIN apollo.users u ON u.id=v.user_id WHERE u.student_id='tracer2-student-001' ORDER BY v.arrived_at DESC;"

KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl -n agents port-forward svc/nats 18222:8222
curl -sS http://127.0.0.1:18222/varz

KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl exec -n athena deploy/athena -- \
  /usr/local/bin/athena presence publish-identified-departures --format json

KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl logs -n athena deployment/athena --since=5m | rg 'identified presence published|mock-out-001'
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl logs -n agents deployment/apollo --since=5m | rg 'identified departure handled|mock-out-001'

KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl exec -n agents postgres-0 -- \
  psql -U langgraph -d langgraph -c "SELECT v.id, v.source_event_id, v.departure_source_event_id, v.arrived_at, v.departed_at FROM apollo.visits v JOIN apollo.users u ON u.id=v.user_id WHERE u.student_id='tracer2-student-001' ORDER BY v.arrived_at DESC; SELECT count(*) AS workouts FROM apollo.workouts;"

KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl exec -n athena deploy/athena -- \
  /usr/local/bin/athena presence publish-identified-departures --format json
KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl exec -n athena deploy/athena -- \
  /usr/local/bin/athena presence publish-identified-departures --format json

KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl logs -n agents deployment/apollo --since=5m | rg 'identified departure handled|mock-out-001'
curl -sS http://127.0.0.1:18222/varz

KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig kubectl exec -n agents postgres-0 -- \
  psql -U langgraph -d langgraph -c "SELECT v.id, v.source_event_id, v.departure_source_event_id, v.arrived_at, v.departed_at FROM apollo.visits v JOIN apollo.users u ON u.id=v.user_id WHERE u.student_id='tracer2-student-001' ORDER BY v.arrived_at DESC; SELECT count(*) AS workouts FROM apollo.workouts;"
```

Expected evidence:

- ATHENA publishes `mock-out-001` on subject `athena.identified_presence.departed`
- APOLLO logs `identified departure handled event_id=mock-out-001 outcome=closed`
- replay logs `identified departure handled event_id=mock-out-001 outcome=duplicate`
- exactly one visit row exists for `source_event_id=mock-in-001`
- that same row is closed with `departure_source_event_id='mock-out-001'`
- `apollo.workouts` remains `0` for this proof

## Rollback

If this bounded live slice needs to be backed out:

1. Revert the Git commit that changed the ATHENA image pin or added the ATHENA
   identified-exit env in `apps/athena/athena-deployment.yaml`.
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
