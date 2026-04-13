# Operator State Recovery

Last updated: 2026-04-13 (America/Toronto)

## Purpose

Keep the operator path recoverable even if this Mac loses shell defaults, the
tower moves, or a future session forgets where the important files live.

This runbook documents:

- what `kubectl` uses locally
- what `sops` needs locally
- where the recovery files live
- how to rebuild a local operator workstation cleanly

## Current operator truth

| Item | Current value |
| --- | --- |
| Home-base subnet | `192.168.50.0/24` |
| MIMIR tailnet IP | `100.109.171.72` |
| MIMIR LAN IP | `192.168.50.171` |
| Prometheus node IP | `192.168.50.197` |
| Active kubeconfig server | `https://192.168.50.197:6443` |
| Tailscale subnet router | `MIMIR` |
| Current advertised route on MIMIR | `192.168.50.0/24` |

## kubectl: what it is using

`kubectl` is now wired through:

- `/Users/zizo/.kube/config`

That path currently points at:

- `/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig`

Important nuance:

- the active local kubeconfig has been rewritten to the current reachable node IP
- Talos still generates fresh kubeconfigs with the old API endpoint baked in
- that means "active kubeconfig works" and "newly generated kubeconfigs are correct"
  are currently different statements

## SOPS: what it is and what it needs

SOPS is the tool that keeps secret manifests encrypted in Git.

Practical model:

- encrypted YAML in the repo is the source of truth
- the age public recipient in `.sops.yaml` is the lock
- the age private key on the workstation is the unlock key
- Flux holds a matching private key in-cluster so it can decrypt during reconcile

Local workstation requirement:

- `SOPS_AGE_KEY_FILE=$HOME/.config/sops/age/keys.txt`

Current local key path:

- `/Users/zizo/.config/sops/age/keys.txt`

## Why "reconstruct from live cluster truth" is only an emergency path

It works, but it is not the normal recipe.

Why:

- the cluster is the deployed result
- Git is supposed to remain the intended source of truth

Danger if reconstruction becomes normal:

- live drift can get copied back into Git as if it were intentional
- secrets that are not currently deployed cannot be reconstructed that way
- comments, structure, and original author intent are lost

Using reconstruction once in a controlled recovery is survivable. Repeating it
casually is how drift becomes the source of truth.

## Local-only recovery bundle

Use:

```bash
/Users/zizo/Personal-Projects/Computers/Prometheus/scripts/refresh-local-recovery-bundle.sh
```

This writes a local-only bundle under:

- `ops/local/`

That directory is intentionally ignored by Git.

The bundle includes copies of:

- active kubeconfig
- Talos config
- age private key for SOPS
- MIMIR SSH keypair
- `.sops.yaml`

## Rebuild a fresh workstation quickly

1. Restore the bundle files.
2. Put the age key back at `~/.config/sops/age/keys.txt`.
3. Put the MIMIR SSH key back at `~/.ssh/mimir_ed25519`.
4. Restore the kubeconfig and Talos config to their normal paths.
5. Make sure the shell exports exist:

```bash
export KUBECONFIG=/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig
export SOPS_AGE_KEY_FILE=$HOME/.config/sops/age/keys.txt
```

6. Verify:

```bash
kubectl get nodes
sops -d /Users/zizo/Personal-Projects/Computers/Prometheus/homelab-gitops/apps/athena/athena-edge-runtime-secret.yaml >/dev/null && echo ok
```

## Current visible LAN identities from MIMIR

These are the hosts positively observed from MIMIR on `192.168.50.0/24` during
the 2026-04-13 check:

| IP | Identity |
| --- | --- |
| `192.168.50.1` | router / gateway |
| `192.168.50.171` | `MIMIR` |
| `192.168.50.197` | `Prometheus` Talos node |
| `192.168.50.40` | unknown live host |
| `192.168.50.97` | unknown live host |
| `192.168.50.160` | unknown live host |
| `192.168.50.233` | unknown live host |
