# Homelab GitOps

Last updated: 2026-03-25 (America/Toronto)

## Status

This directory is no longer just a skeleton. The first Flux entrypoints and
component manifests are authored and render-valid, but parts of the stack are
intentionally staged behind `suspend: true` until the storage targets and DNS
cutover are explicitly confirmed.

Authored and render-valid now:

- `clusters/talos-tower/infrastructure.yaml`
- `clusters/talos-tower/apps.yaml`
- `infrastructure/cilium/`
- `infrastructure/network/`
- `infrastructure/nvidia/`
- `infrastructure/storage/` for Kubernetes-side local-path provisioning
- `infrastructure/dns/` for AdGuard Home
- `apps/ai/open-webui/`
- `apps/ai/ollama/` as a parked option, not the current activation target

Staged but intentionally not active yet:

- `infra-storage`
- `infra-dns`
- `apps-ai`

## What this repo is intended to become

- The source of truth for infrastructure and app state on the Talos tower.
- The place where Flux reconciles Cilium, DNS, storage, NVIDIA support, and apps.
- The place where the `vLLM + LangGraph + Postgres` application layer will land.
- The place where GPU mode-switching overlays can live later if `ComfyUI` becomes necessary.

## What it is not yet

- It is not ready for immediate Flux bootstrap without review.
- It does not contain `.sops.yaml`, encrypted secrets, or an `age` public key yet.
- It does not yet include vLLM, LangGraph, Postgres, ComfyUI, media, Immich, or Tailscale manifests.
- Talos `UserVolumeConfig` documents exist, but they are intentionally outside Flux because they are Talos machine config, not Kubernetes resources.
- The current non-system SSD and NVMe candidates are in use elsewhere, so storage activation remains paused until a safe target exists.

## Directory inventory

| Path | Intended purpose | Restrictions | What it does not do yet |
| ------------------------------| ---------------------------------------------------------------------------------------| ------------------------------------------------------------------------------------------------------| ---------------------------------------------------------------------------------------------------------------------------|
| `clusters/talos-tower/` | Flux entrypoints that sequence infrastructure first and apps later. | Should stay small and declarative; avoid putting raw app specs directly here. | It does not contain encrypted secret wiring yet.                                                                          |
| `infrastructure/cilium/` | Pinned Cilium `1.18.0` Helm source and release with the Talos-specific values already proven live. | Must stay aligned with the validated bootstrap settings. | It does not define service IP allocations by itself.                                                     |
| `infrastructure/dns/` | AdGuard Home namespace, PVC, deployment, and fixed-IP `LoadBalancer` service. | Intentionally staged behind `suspend: true` until storage and DNS cutover are approved. | It does not create router-side DNS settings or rewrites for you.   |
| `infrastructure/network/` | Cilium `LoadBalancer` IP pool and L2 announcement policy for the LAN. | Must stay aligned with the real LAN range and NIC naming. | It does not install Cilium itself.                                                                                                                 |
| `infrastructure/nvidia/` | Runtime class and pinned NVIDIA device plugin daemonset. | GPU assumptions are tower-specific unless more GPU nodes appear later. | It does not install drivers; Talos already handles that at the OS layer. |
| `infrastructure/storage/` | Kubernetes-side local-path provisioner plus Talos-side storage docs under `storage/talos/`. | High-risk area because it touches non-system disks. | Flux does not apply the Talos `UserVolumeConfig` files. |
| `infrastructure/tailscale/` | Optional remote admin and tailnet access manifests. | Day-2 feature; should not block base cluster bring-up. | No Tailscale manifests exist yet. |
| `apps/ai/ollama/` | Earlier local-LLM path kept in-repo for reference. | Parked after the `vLLM`-first pivot; do not treat it as the default next step. | It is not part of the current activation plan. |
| `apps/ai/open-webui/` | Human-facing web UI for the eventual OpenAI-compatible backend. | Needs storage plus a serving backend, and its current authored manifests still assume Ollama. | It is not yet retargeted to the revised `vLLM`-first plan. |
| `apps/ai/vllm/` | vLLM API workloads and Hugging Face model cache. | Requires GPU, secrets, and controlled model selection. | No manifests exist yet. |
| `apps/agents/langgraph/` | Future LangGraph service for orchestration, retries, and human-in-the-loop resume. | Depends on `Postgres`, model-serving availability, and careful tool design. | No manifests exist yet. |
| `infrastructure/postgres/` | Future durable store for LangGraph checkpoints and app state. | Stateful layer; should not be activated until storage is intentionally solved. | No manifests exist yet. |
| `apps/ai/comfyui/` | ComfyUI image-generation workloads and model/output storage. | Should not share the GPU with vLLM or Ollama at full load. | No manifests exist yet. |
| `apps/media/` | Future Arr stack, Jellyfin, qBittorrent, and Seerr manifests. | Storage paths and service exposure must be designed before deployment. | No manifests exist yet. |
| `apps/immich/` | Future Immich deployment. | Needs storage, DNS, and likely split CPU/GPU concerns later. | No manifests exist yet. |

## Planned file inventory

These are the highest-value files now present or still missing as the repo
transitions from bootstrap record to real GitOps source of truth.

| Planned file | What it should accomplish | Restrictions | What it should not do |
| --- | --- | --- | --- |
| `clusters/talos-tower/infrastructure.yaml` | Reconcile Cilium, network, NVIDIA, staged storage, and staged DNS in the right order. | Storage and DNS are intentionally suspended. | It must not be treated as “safe to unsuspend everything.” |
| `clusters/talos-tower/apps.yaml` | Reconcile application workloads only after infrastructure and storage are ready. | Currently suspended on purpose. | It must not bypass future SOPS secret handling or imply Ollama-first activation. |
| `.sops.yaml` | Define how YAML secrets are encrypted for the repo. | Needs the real `age` public key first. | Does not store the private key. |
| `infrastructure/cilium/helmrelease.yaml` or rendered manifest set | Declare the validated Cilium install in Git. | Must preserve the working Talos values. | Must not drift from the bootstrap-tested settings without review. |
| `infrastructure/network/ip-pool.yaml` | Declare the `192.168.2.200-220` service pool. | LAN range must remain conflict-free. | Does not expose services by itself. |
| `infrastructure/network/l2-policy.yaml` | Announce service IPs on the real LAN NIC. | Interface name must match the live node. | Does not allocate IPs by itself. |
| `infrastructure/nvidia/runtimeclass.yaml` | Preserve the `nvidia` runtime class in Git. | Depends on NVIDIA runtime availability on the node. | Does not advertise GPU resources alone. |
| `infrastructure/nvidia/device-plugin.yaml` | Preserve the pinned NVIDIA device plugin in Git. | Prefer pinned versions and ideally pinned digests. | Does not install drivers. |
| `infrastructure/storage/talos/*.yaml` | Define Talos `UserVolumeConfig` documents for the non-system disks. | Must be applied with Talos tooling after disk confirmation. | They are not Kubernetes manifests and Flux will not apply them. |
| `infrastructure/dns/*.yaml` | Deploy AdGuard Home and DNS service exposure. | Router cutover should happen only after validation. | Must not assume DNS is live before it is tested. |
| `apps/ai/*` | Deploy the first model-serving and UI layer, with `vLLM` now preferred over `Ollama`. | Single RTX 3090 means one heavy GPU workload at a time. | Must not schedule all GPU consumers concurrently by default. |
| `apps/agents/*` | Deploy agent orchestration and memory-adjacent services. | Must stay cleanly separated from model serving. | Should not grow into a second serving stack. |

## Before Flux bootstrap

1. Confirm the non-system disk targets before touching `infrastructure/storage/talos/`.
2. Apply the Talos `UserVolumeConfig` documents intentionally.
3. Unsuspend `infra-storage`, then validate PVC provisioning.
4. Generate `age.key`, record the public key, and create `.sops.yaml`.
5. Add encrypted secret handling before vLLM, LangGraph, Immich, or anything token-bearing lands here.
6. Choose the DNS cutover window, then unsuspend `infra-dns`.
7. Author `vLLM`, `Postgres`, and `LangGraph` before unsuspending application workloads.
8. Keep `Ollama`, `LiteLLM`, `Graphiti`, and `Letta` out of the first activation wave.
