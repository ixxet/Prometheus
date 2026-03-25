# Homelab GitOps

Last updated: 2026-03-25 (America/Toronto)

## Status

This directory is no longer a skeleton. It now contains the first real GitOps
shape for the Prometheus cluster, but the stateful layers remain intentionally
staged behind `suspend: true` and the repo is still not bootstrapped into Flux.

Authored and render-valid now:

- `clusters/talos-tower/infrastructure.yaml`
- `clusters/talos-tower/apps.yaml`
- `infrastructure/cilium/`
- `infrastructure/network/`
- `infrastructure/nvidia/`
- `infrastructure/storage/` for Kubernetes-side local-path provisioning
- `infrastructure/postgres/` for the first execution store
- `infrastructure/dns/` for AdGuard Home
- `apps/ai/vllm/`
- `apps/ai/open-webui/`
- `apps/agents/langgraph/`
- `apps/ai/ollama/` as parked reference material, not the active path

Staged but intentionally not active yet:

- `infra-storage`
- `infra-postgres`
- `infra-dns`
- `apps`

## What this repo is intended to become

- The source of truth for infrastructure and app state on the Talos tower.
- The place where Flux reconciles Cilium, network policy, DNS, NVIDIA support,
  storage, and the first agent stack.
- The place where `vLLM + Postgres + LangGraph` becomes the stable first-wave AI
  platform.
- The place where future storage tiers and NUC split-out work can be expressed
  cleanly once the base platform proves itself.

## What it is not yet

- It is not ready for immediate Flux bootstrap without review.
- It does not contain `.sops.yaml`, encrypted secrets, or an `age` key yet.
- It does not yet include Mem0, Obsidian export automation, ComfyUI, media,
  Immich, or Tailscale manifests.
- Talos `UserVolumeConfig` documents exist, but they are intentionally outside
  Flux because they are Talos machine config, not Kubernetes resources.
- The first-wave storage model is temporary and SSD-backed; it is designed to
  avoid touching any off-limits non-system disk.

## First activation wave

The first coherent activation path is now:

1. `AdGuard Home`
2. `vLLM`
3. `Open WebUI` pointed directly at the `vLLM` OpenAI-compatible API
4. `Postgres`
5. `LangGraph`

Explicitly out of this first wave:

- `Ollama`
- `LiteLLM`
- `Graphiti/Zep`
- `Letta`

## Directory inventory

| Path | Intended purpose | Restrictions | What it does not do yet |
| ---- | ---------------- | ------------ | ----------------------- |
| `clusters/talos-tower/` | Flux entrypoints that sequence infrastructure first and apps later. | Should stay small and declarative. | It does not contain encrypted secret wiring yet. |
| `infrastructure/cilium/` | Pinned Cilium `1.18.0` Helm source and release with the Talos-specific values already proven live. | Must stay aligned with the validated bootstrap settings. | It does not define service IP allocations by itself. |
| `infrastructure/network/` | Cilium `LoadBalancer` IP pool and L2 announcement policy for the LAN. | Must stay aligned with the real LAN range and NIC naming. | It does not install Cilium itself. |
| `infrastructure/nvidia/` | Runtime class and pinned NVIDIA device plugin daemonset. | GPU assumptions are tower-specific unless more GPU nodes appear later. | It does not install drivers; Talos handles that at the OS layer. |
| `infrastructure/storage/` | Kubernetes-side local-path provisioner plus Talos-side storage docs under `storage/talos/`. | Temporary SSD-only mode inherits the Talos `EPHEMERAL` partition limits. | Flux does not apply the Talos `UserVolumeConfig` files. |
| `infrastructure/postgres/` | Internal Postgres service for checkpoint and application state. | Suspended until small PVC-backed storage is deliberately enabled. | It does not solve semantic memory or archive export by itself. |
| `infrastructure/dns/` | AdGuard Home namespace, PVC, deployment, and fixed-IP `LoadBalancer` service. | Suspended until storage and the DNS cutover window are approved. | It does not update router-side DNS settings for you. |
| `apps/ai/vllm/` | First-wave GPU serving backend with a conservative local cache footprint. | Assumes one heavy GPU workload at a time on the RTX 3090. | It does not yet include Hugging Face secret wiring or larger model tiers. |
| `apps/ai/open-webui/` | Human-facing web UI pointed directly at the vLLM OpenAI-compatible endpoint. | Depends on storage and on vLLM existing as the first backend. | It is not a gateway or orchestrator. |
| `apps/ai/ollama/` | Earlier local-LLM path kept in-repo for reference. | Parked after the vLLM-first pivot; do not treat it as the default next step. | It is not part of the current activation plan. |
| `apps/agents/langgraph/` | Scaffold for the LangGraph runtime layer and its runtime assumptions. | Suspended, requires a built image and runtime secrets before activation. | It does not yet include Redis or LangSmith/LangGraph licensing setup. |
| `apps/media/` | Future Arr stack, Jellyfin, qBittorrent, and Seerr manifests. | Storage paths and service exposure must be designed before deployment. | No manifests exist yet. |
| `apps/immich/` | Future Immich deployment. | Needs storage, DNS, and likely split CPU/GPU concerns later. | No manifests exist yet. |

## Storage stance for the first wave

The first-wave storage model is deliberately conservative:

- `local-path-provisioner` is documented as a Talos `UserVolumeConfig` with
  `volumeType: directory`
- the mount path remains `/var/mnt/local-path-provisioner`
- that means first-wave PVCs live on the Talos system SSD under the `EPHEMERAL`
  partition
- this avoids repartitioning any off-limits non-system disk

What this is good enough for:

- `Open WebUI` data
- small `Postgres` state
- small `vLLM` cache footprint

What it is not good enough for:

- large model libraries
- ComfyUI assets and outputs
- Immich
- bulk media data

Future direction remains unchanged:

- second SSD = fast AI/model-cache tier
- HDD or Unraid = bulk and cold storage

## Planned file inventory

| Planned file | What it should accomplish | Restrictions | What it should not do |
| --- | --- | --- | --- |
| `clusters/talos-tower/infrastructure.yaml` | Reconcile Cilium, network, NVIDIA, staged storage, staged Postgres, and staged DNS in the right order. | Storage, Postgres, and DNS stay intentionally suspended. | It must not imply that everything is safe to unsuspend together. |
| `clusters/talos-tower/apps.yaml` | Reconcile application workloads only after infrastructure and storage are ready. | Suspended on purpose. | It must not bypass future SOPS secret handling. |
| `.sops.yaml` | Define how YAML secrets are encrypted for the repo. | Needs the real `age` public key first. | It does not store the private key. |
| `infrastructure/network/ip-pool.yaml` | Declare the `192.168.2.200-220` service pool. | LAN range must remain conflict-free. | It does not expose services by itself. |
| `infrastructure/network/l2-policy.yaml` | Announce service IPs on the real LAN NIC. | Interface name must match the live node. | It does not allocate IPs by itself. |
| `infrastructure/postgres/postgres-statefulset.yaml` | Preserve the first-wave execution store in Git. | Needs a small but real PVC before activation. | It does not replace semantic memory or human-readable archives. |
| `apps/ai/vllm/*` | Deploy the first GPU serving backend and small on-node cache. | Keep model size conservative while storage stays on the system SSD. | Must not pretend larger storage tiers already exist. |
| `apps/agents/langgraph/*` | Define the future orchestrator shape, runtime configuration, and internal service. | Requires a built image plus runtime secrets before it can run. | It should not grow into a second serving backend. |
| `docs/diagrams/*.mmd` | Preserve diagram sources next to the authored platform docs. | Keep them high-level until the live schema and runtime harden. | They should not lock production schema details prematurely. |

## Before Flux bootstrap

1. Apply the Talos `UserVolumeConfig` directory volume intentionally.
2. Unsuspend `infra-storage`, then validate PVC provisioning.
3. Generate `age.key`, record the public key, and create `.sops.yaml`.
4. Add encrypted secret handling before vLLM, LangGraph, or anything token-bearing is activated.
5. Unsuspend `infra-postgres` only after the storage class is proven.
6. Choose the DNS cutover window, then unsuspend `infra-dns`.
7. Unsuspend `apps` only after the first-wave internal services are ready.
8. Keep `Ollama`, `LiteLLM`, `Graphiti`, and `Letta` out of the first activation wave.
