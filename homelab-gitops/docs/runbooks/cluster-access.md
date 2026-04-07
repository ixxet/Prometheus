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

## 2026-04-06 Growing Pains

- GHCR laptop publish auth and Kubernetes image pull auth were separate truths.
  A package-capable local token was enough to push `ghcr.io/ixxet/athena`, but
  the cluster still could not pull until `imagePullSecrets` were wired through
  the workload ServiceAccount.

- Local SOPS decryption is not available on this machine. That means encrypted
  Secret manifests can be rendered and committed here, but `kubectl diff` over
  encrypted payloads is not a truthful local validation step. In this repo, the
  honest preflight is:
  `kustomize build` locally plus Flux decryption in cluster.

- Flux dependency readiness can block unrelated-looking rollouts. During the
  ATHENA edge deployment pass, `apps` stayed pending until `infra-storage` and
  then `infra-postgres` were reconciled again, even though the ATHENA manifests
  themselves were already correct.
