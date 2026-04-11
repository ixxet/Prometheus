# ATHENA Edge Deployment Runbook

## Purpose

This runbook documents the bounded live deployment shape for
`athena v0.7.0` edge-driven occupancy with Postgres-backed observation and
session truth.

The goal is narrow:

- run ATHENA in explicit edge-projection mode
- accept browser-reachable HTTPS edge taps
- update in-memory occupancy
- persist append-only edge observations and derived sessions in Postgres
- expose bounded internal history and analytics reads from that durable store
- publish identified presence events on NATS

This runbook does **not** claim:

- broad multi-facility rollout
- named-tunnel production exposure
- public dashboards or wider operator product surfaces
- prediction or AI occupancy summary
- booking or scheduling runtime
- HERMES/admin/operator override workflows beyond the separate bounded internal
  occupancy runner

## Recorded Closeout Context

This document records the bounded ATHENA edge closeout and should be used
together with the current manifests before claiming fresh live truth.

- runtime release line closed here: `athena v0.7.0`
- runtime release revision: `415e2a87748ba6a2f23f2885188304831fe49c31`
- deploy repo head at closeout: `bc91e2e86e8f7179050e55db6dadb6cb0c4e76fa`
- current manifest still points `apps/athena/athena-deployment.yaml` at
  `ghcr.io/ixxet/athena:v0.7.0@sha256:a0cd23779a5dd83bc2261cb33738adc8b25eed8031463c1e01528cc8426cada3`

## Deployed Resources

The ATHENA app slice currently includes:

- `Deployment/athena`
- `Service/athena`
- `ServiceAccount/athena`
- `Secret/athena-edge-runtime`
- `Secret/athena-ghcr-pull`
- `ConfigMap/athena-migrate-v0-7-0-r1`
- `Job/athena-migrate-v0-7-0-r1`
- `Deployment/athena-edge-proxy`
- `Service/athena-edge-proxy`
- `ConfigMap/athena-edge-proxy-nginx`
- `Deployment/athena-edge-tunnel`

## Runtime Shape

ATHENA runs with:

- image `ghcr.io/ixxet/athena:v0.7.0@sha256:a0cd23779a5dd83bc2261cb33738adc8b25eed8031463c1e01528cc8426cada3`
- `ATHENA_EDGE_OCCUPANCY_PROJECTION=true`
- `ATHENA_NATS_URL`
- secret-backed `ATHENA_EDGE_POSTGRES_DSN`
- secret-backed:
  - `ATHENA_EDGE_HASH_SALT`
  - `ATHENA_EDGE_TOKENS`

Schema application is explicit and reproducible:

- `Job/athena-migrate-v0-7-0-r1` runs `postgres:16-alpine`
- it mounts `001_initial.up.sql` and `002_edge_observation_storage.up.sql`
- it records applied versions in `athena.schema_migrations`
- reruns are idempotent because already-applied versions are skipped

The cluster authenticates to GHCR through `imagePullSecrets` on the `athena`
ServiceAccount. That means cluster pull auth is separate from laptop publish
auth and does not depend on anonymous registry pulls.

## Narrow External Surface

The browser-facing path is intentionally reduced to:

- `POST /api/v1/edge/tap`
- `GET /api/v1/health`

This is enforced by the ATHENA edge proxy in front of the internal ATHENA
service. `presence/count` and `/metrics` remain internal verification surfaces.

Current exposure mechanism:

- Cloudflare quick tunnel from `athena-edge-tunnel`

This is acceptable for bounded proof, not a final production exposure design.

## Proof Checklist

### Preflight

1. `kustomize build apps/athena`
2. verify Flux source revision includes the intended deploy commit
3. confirm `apps` Kustomization is ready at `main@sha1:bc91e2e8`
4. confirm `Deployment/athena` is on the `v0.7.0` digest
5. confirm `ServiceAccount/athena` references `athena-ghcr-pull`
6. confirm `Job/athena-migrate-v0-7-0-r1` completed successfully

### Live proof

1. confirm tunnel logs show a reachable `trycloudflare.com` URL
2. `GET /api/v1/health` through the tunnel returns `adapter=edge-projection`
3. internal `GET /api/v1/health` returns `adapter=edge-projection`
4. `POST /api/v1/edge/tap` accepted `pass in` and returned
   `athena.identified_presence.arrived` with `published=true`
5. internal `GET /api/v1/presence/count?facility=morningside&zone=weight-room`
   increments to `1`
6. repeated `in` stays observation-only and does not increment occupancy
7. explicit `fail` stays observation-only and does not change occupancy
8. accepted `out` decrements occupancy to `0` and returns
   `athena.identified_presence.departed` with `published=true`
9. repeated `out` stays observation-only and does not decrement again
10. external `/metrics` and `/api/v1/presence/count` stay `404` through the
    proxy while `/api/v1/health` and `/api/v1/edge/tap` remain reachable
11. internal `/api/v1/presence/history` and `/api/v1/presence/analytics`
    return Postgres-backed results for the same window
12. direct Postgres inspection shows:
    - `athena.schema_migrations` contains `001_initial.up.sql` and
      `002_edge_observation_storage.up.sql`
    - `athena.edge_observations` contains both observed and committed rows for
      duplicate and fail cases
    - `athena.edge_sessions` contains one closed session for the accepted
      `in/out` pair
13. `kubectl rollout restart deployment/athena` rebuilds from Postgres-backed
    replay before serving and both internal count and `/metrics` return `0`

## Current Closeout Truth

Bounded deployment truth that is now real:

- browser-reachable HTTPS ATHENA edge ingress
- live in-memory occupancy projection in cluster
- live Prometheus occupancy gauge updates
- direct identified publish success from accepted pass taps
- Postgres-backed append-only edge observations in the shared `agents` Postgres
  service
- Postgres-backed derived session facts with explicit closed-session proof
- bounded internal ATHENA history and analytics reads sourced from real durable
  storage
- deterministic duplicate, fail, and replay handling
- restart replay from committed Postgres-backed truth

Truth still deferred:

- occupancy snapshot persistence
- broader ingress rollout
- named-tunnel or domain-managed exposure
- any public HERMES or gateway deployment slice
- dashboards, prediction, or AI occupancy summary
- booking or scheduling runtime
