# ATHENA Edge Deployment Runbook

## Purpose

This runbook documents the bounded live deployment shape for
`athena v0.4.1` edge-driven occupancy.

The goal is narrow:

- run ATHENA in explicit edge-projection mode
- accept browser-reachable HTTPS edge taps
- update in-memory occupancy
- publish identified presence events on NATS

This runbook does **not** claim:

- append-only ATHENA persistence
- broad multi-facility rollout
- named-tunnel production exposure
- HERMES/admin/operator override workflows

## Recorded Closeout Context

This document records the bounded ATHENA edge closeout and should be used
together with the current manifests before claiming fresh live truth.

- release line closed here: `Prometheus v0.0.3`
- recorded release revision: `9afd7cb720f134f9c671c8a74f32af4fd36c088c`
- current repo head at audit time: `cdf4e004db20aa4166fd08087ce85845124da0f9`
- current manifest still points `apps/athena/athena-deployment.yaml` at
  `athena v0.4.1`

## Deployed Resources

The ATHENA app slice currently includes:

- `Deployment/athena`
- `Service/athena`
- `ServiceAccount/athena`
- `Secret/athena-edge-runtime`
- `Secret/athena-ghcr-pull`
- `Deployment/athena-edge-proxy`
- `Service/athena-edge-proxy`
- `ConfigMap/athena-edge-proxy-nginx`
- `Deployment/athena-edge-tunnel`

## Runtime Shape

ATHENA runs with:

- image `ghcr.io/ixxet/athena:v0.4.1@sha256:87685d3ad4e86bd9593ad39326c7ecb1210b631e6056f3c54f618322b5fddb6f`
- `ATHENA_EDGE_OCCUPANCY_PROJECTION=true`
- `ATHENA_NATS_URL`
- secret-backed:
  - `ATHENA_EDGE_HASH_SALT`
  - `ATHENA_EDGE_TOKENS`

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
2. verify Flux source revision includes the intended ATHENA deployment commit
3. confirm `apps` Kustomization is ready
4. confirm `Deployment/athena` is on the `v0.4.1` digest
5. confirm `ServiceAccount/athena` references `athena-ghcr-pull`

### Live proof

1. confirm tunnel logs show a reachable `trycloudflare.com` URL
2. `GET /api/v1/health` through the tunnel returns `adapter=edge-projection`
3. `POST /api/v1/edge/tap` accepted `pass in`
4. internal `GET /api/v1/presence/count` increments
5. internal `GET /metrics` reflects the same count
6. direct NATS subscription observes `athena.identified_presence.arrived`
7. repeated `in` stays observation-only
8. accepted `out` decrements occupancy and publishes `departed`
9. repeated `out` stays observation-only
10. explicit `fail` stays observation-only
11. stale pass event stays observation-only
12. `athena edge replay-touchnet` against the live HTTPS ingress updates a
    separate zone and publishes again

## Current Closeout Truth

Bounded deployment truth that is now real:

- browser-reachable HTTPS ATHENA edge ingress
- live in-memory occupancy projection in cluster
- live Prometheus occupancy gauge updates
- direct NATS subject movement from accepted pass taps
- deterministic duplicate, fail, and stale handling
- live replay through the same ingress route

Truth still deferred:

- append-only edge observation persistence
- occupancy snapshot persistence
- broader ingress rollout
- named-tunnel or domain-managed exposure
- any HERMES or gateway deployment slice
