# Disaster Recovery Runbook

Last updated: 2026-03-26 (America/Toronto)

## Purpose

This is the first recovery checklist for the current single-node platform. It is
not complete yet, but it gives the operator a starting path under pressure.

## Current limits

- single control-plane node
- first-wave state still lives on the Talos system SSD
- no dedicated backup pipeline yet for Postgres or app PVCs
- recovery is currently centered on repo truth plus bootstrap artifacts, with
  the live Talos admin configs kept outside the repo

## Core artifacts to preserve

- this repo
- `tower-bootstrap/` in this repo as the historical bootstrap record
- Talos config and kubeconfig under `/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/`
- SOPS age private key outside the repo
- router DNS settings when AdGuard cutover happens later

## Recovery priorities

1. Regain access to Talos
2. Regain access to Kubernetes API
3. Re-establish Flux reconciliation
4. Re-establish DNS and AI-serving endpoints
5. Recover higher-level agent services later

## Minimal recovery sequence

1. Validate node reachability with `talosctl ... health`
2. Validate API reachability with `kubectl ... get nodes`
3. Check Flux kustomization health
4. Check PVC binding and pod state in:
   - `dns`
   - `ai`
   - `agents`
5. If manifests drifted from runtime, reconcile the affected Kustomization
6. If the node itself is lost, rebuild from Talos bootstrap artifacts and let Flux
   reconcile the cluster state back in

## Known weak points today

- no automated restore drill has been performed yet
- no externalized backup flow for first-wave PVCs exists yet
- the platform is still single-node, so hardware loss is still a hard event
