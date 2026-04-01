# Cluster Access Runbook

## Purpose

Use this runbook before calling a GitOps change "live verified."

## Local Requirements

- `kubectl` installed on the operator machine
- `kustomize` installed locally or available through `kubectl kustomize`
- a valid kubeconfig with a real current context
- `flux` CLI installed for reconciliation checks

## Verification Flow

1. confirm `kubectl config current-context`
2. render manifests with `kustomize build` or `kubectl kustomize`
3. reconcile Flux if needed
4. check `kubectl rollout status`
5. only then call the deploy verified

## 2026-04-01 Growing Pain

- `kubectl config current-context` was unset on the MacBook during ATHENA
  activation. GitOps changes were pushed, but live cluster verification could
  not be completed from the local shell. This is a local environment issue, not
  a repo issue.
