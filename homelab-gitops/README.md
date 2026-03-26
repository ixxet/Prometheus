# Homelab GitOps

Last updated: 2026-03-26 (America/Toronto)

## Status

This directory is no longer a skeleton. It now drives the live cluster via Flux.
The first stateful services are healthy, `vLLM` is serving successfully, and the
LangGraph runtime is now live. The next meaningful steps are naming cleanup,
router cutover preparation, and the memory/archive layers.

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

Live now:

- `infra-storage`
- `infra-postgres`
- `infra-dns`
- `apps`

## What this repo is intended to become

- The source of truth for infrastructure and app state on the Talos tower.
- The place where Flux reconciles Cilium, network policy, DNS, NVIDIA support,
  storage, and the first agent stack.
- The place where `vLLM + Postgres + LangGraph` is already the stable first-wave
  AI platform.
- The place where future storage tiers and NUC split-out work can be expressed
  cleanly once the base platform proves itself.

## What it is not yet

- Flux is already bootstrapped against this repo.
- `.sops.yaml` exists and encrypted secrets are wired into the cluster.
- It does not yet include Mem0, Obsidian export automation, ComfyUI, media,
  Immich, or Tailscale manifests.
- Talos `UserVolumeConfig` documents exist, but they are intentionally outside
  Flux because they are Talos machine config, not Kubernetes resources.
- The first-wave storage model is temporary and SSD-backed; it is designed to
  avoid touching any off-limits non-system disk.

## First activation wave

The first coherent activation path is now:

1. `Postgres`
2. `AdGuard Home`
3. `vLLM`
4. `Open WebUI`
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
| `infrastructure/postgres/` | Internal Postgres service for checkpoint and application state. | Running on small SSD-backed PVC storage for now. | It does not solve semantic memory or archive export by itself. |
| `infrastructure/dns/` | AdGuard Home namespace, PVC, deployment, and fixed-IP `LoadBalancer` service. | Running, but router cutover is still intentionally deferred. | It does not update router-side DNS settings for you. |
| `apps/ai/vllm/` | First-wave GPU serving backend with a conservative local cache footprint. | Assumes one heavy GPU workload at a time on the RTX 3090. | It does not yet include Hugging Face secret wiring or larger model tiers. |
| `apps/ai/open-webui/` | Human-facing web UI pointed directly at the vLLM OpenAI-compatible endpoint. | Depends on storage and on vLLM existing as the first backend. | It is not a gateway or orchestrator. |
| `apps/ai/ollama/` | Earlier local-LLM path kept in-repo for reference. | Parked after the vLLM-first pivot; do not treat it as the default next step. | It is not part of the current activation plan. |
| `apps/agents/langgraph/` | GitOps layer for the LangGraph runtime. | Uses the existing Postgres secret, explicit no-op seam providers for `v0.4.0`, and an immutable image tag. | It is live now; the next work is memory/archive integration, not a second runtime. |
| `apps/media/` | Future Arr stack, Jellyfin, qBittorrent, and Seerr manifests. | Storage paths and service exposure must be designed before deployment. | No manifests exist yet. |
| `apps/immich/` | Future Immich deployment. | Needs storage, DNS, and likely split CPU/GPU concerns later. | No manifests exist yet. |

## Live runtime note

As of 2026-03-26:

- `Postgres` is running
- `AdGuard Home` is running
- `Open WebUI` is serving successfully on `192.168.2.201`
- `vLLM` is serving successfully on `192.168.2.205:8000`
- the `vLLM` cache PVC is populated on the system SSD
- `LangGraph` is running internally in the `agents` namespace
- LangGraph thread, approval/resume, and restart persistence checks have passed
- LangGraph now exposes no-op semantic-memory and archive seams in `/healthz`
- the `apps` `Kustomization` is healthy again
- AdGuard completed first-run setup and now serves the admin UI on `192.168.2.200`
- AdGuard answers the first-wave `home.arpa` rewrites directly on `192.168.2.200`

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
| `clusters/talos-tower/infrastructure.yaml` | Reconcile Cilium, network, NVIDIA, storage, Postgres, and DNS in the right order. | Must remain aligned with the live dependency graph. | It must not imply that later app layers are already healthy. |
| `clusters/talos-tower/apps.yaml` | Reconcile application workloads after infrastructure is ready. | The next runtime jump is LangGraph, not another model server. | It must not bypass future SOPS secret handling. |
| `.sops.yaml` | Define how YAML secrets are encrypted for the repo. | Needs the real `age` public key first. | It does not store the private key. |
| `infrastructure/network/ip-pool.yaml` | Declare the `192.168.2.200-220` service pool. | LAN range must remain conflict-free. | It does not expose services by itself. |
| `infrastructure/network/l2-policy.yaml` | Announce service IPs on the real LAN NIC. | Interface name must match the live node. | It does not allocate IPs by itself. |
| `infrastructure/postgres/postgres-statefulset.yaml` | Preserve the first-wave execution store in Git. | Needs a small but real PVC before activation. | It does not replace semantic memory or human-readable archives. |
| `apps/ai/vllm/*` | Deploy the first GPU serving backend and small on-node cache. | Keep model size conservative while storage stays on the system SSD. | Must not pretend larger storage tiers already exist. |
| `apps/agents/langgraph/*` | Define and operate the current internal orchestrator service. | Must stay Postgres-backed and OSS-only for the `v0.3.x` line. | It should not grow into a second serving backend. |
| `docs/diagrams/*.mmd` | Preserve diagram sources next to the authored platform docs. | Keep them high-level until the live schema and runtime harden. | They should not lock production schema details prematurely. |

## Next activation steps

1. Point a test client directly at AdGuard and prove `openwebui.home.arpa` and `vllm.home.arpa` resolve by name.
2. Keep using the validated Tailscale subnet-router path through MIMIR for remote ops.
3. Preserve the `v0.3.0` LangGraph validation path in docs and runbooks as the baseline smoke test.
4. Move next into Mem0 and external Obsidian summary/export work without expanding the serving layer.
5. Keep `Ollama`, `LiteLLM`, `Graphiti`, and `Letta` out of the first activation wave.
