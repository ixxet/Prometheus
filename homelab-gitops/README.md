# Homelab GitOps Scaffold

Last updated: 2026-03-24 (America/Toronto)

## Status

This directory is only a scaffold right now. The directory layout exists, but the
manifests, Flux `Kustomization` objects, Helm releases, and encrypted secrets have
not been authored yet. Do not bootstrap Flux against this path until the required
files actually exist.

## What this repo is intended to become

- The source of truth for infrastructure and app state on the Talos tower.
- The place where Flux reconciles Cilium, DNS, storage, NVIDIA support, and apps.
- The place where GPU mode-switching overlays will live for `ai-llm` and `ai-image`.

## What it is not yet

- It is not a working Flux repo.
- It does not contain `.sops.yaml`, encrypted secrets, or an `age` public key yet.
- It does not contain cluster entrypoint manifests under `clusters/talos-tower/`.
- It does not yet model the live bootstrap state that exists in `tower-bootstrap/`.

## Directory inventory

| Path | Intended purpose | Restrictions | What it does not do yet |
| --- | --- | --- | --- |
| `clusters/talos-tower/` | Entry point for Flux `Kustomization` objects that stitch infrastructure and apps together for the tower cluster. | Should stay small and declarative; avoid putting raw app specs directly here. | No YAML exists yet, so Flux cannot reconcile from it. |
| `infrastructure/cilium/` | Final home for the pinned Cilium install definition. | Must match the Talos-specific bootstrap settings already proven live. | Does not yet mirror `tower-bootstrap/cilium-1.18.0.yaml`. |
| `infrastructure/dns/` | AdGuard Home namespace, service, storage, and DNS policy manifests. | Router DNS should not be pointed here until health is proven. | No AdGuard manifests exist yet. |
| `infrastructure/network/` | Network-level policies such as `LoadBalancer` IP pools and L2 announcements. | Must stay aligned with the actual LAN and NIC naming. | No reusable network manifests exist here yet. |
| `infrastructure/nvidia/` | Runtime class, device plugin, and later GPU-related policy/labels. | GPU assumptions are tower-specific unless more GPU nodes appear later. | It does not yet contain the validated manifests from bootstrap. |
| `infrastructure/storage/` | Talos `UserVolumeConfig`, storage classes, and local-path or other provisioner manifests. | High-risk area because it touches non-system disks. | No storage manifests exist yet. |
| `infrastructure/tailscale/` | Optional remote admin and tailnet access manifests. | Day-2 feature; should not block base cluster bring-up. | No Tailscale manifests exist yet. |
| `apps/ai/ollama/` | Ollama deployment and storage for daily LLM use. | Must respect single-GPU scheduling and model sizing for the RTX 3090. | No manifests exist yet. |
| `apps/ai/open-webui/` | Open WebUI frontend for Ollama and vLLM. | Depends on AI backends and service exposure. | No manifests exist yet. |
| `apps/ai/vllm/` | vLLM API workloads and Hugging Face model cache. | Requires GPU, secrets, and controlled model selection. | No manifests exist yet. |
| `apps/ai/comfyui/` | ComfyUI image-generation workloads and model/output storage. | Should not share the GPU with vLLM or Ollama at full load. | No manifests exist yet. |
| `apps/media/` | Future Arr stack, Jellyfin, qBittorrent, and Seerr manifests. | Storage paths and service exposure must be designed before deployment. | No manifests exist yet. |
| `apps/immich/` | Future Immich deployment. | Needs storage, DNS, and likely split CPU/GPU concerns later. | No manifests exist yet. |

## Planned file inventory

These are the first files that should be created here, because they turn the
empty scaffold into a usable GitOps repo.

| Planned file | What it should accomplish | Restrictions | What it should not do |
| --- | --- | --- | --- |
| `clusters/talos-tower/infrastructure.yaml` | Reconcile the infrastructure layer first. | Must declare dependencies cleanly. | Must not embed large raw manifests inline. |
| `clusters/talos-tower/apps.yaml` | Reconcile application workloads only after infrastructure is healthy. | Should depend on the infrastructure kustomization. | Must not bypass SOPS for secrets. |
| `.sops.yaml` | Define how YAML secrets are encrypted for the repo. | Needs the real `age` public key first. | Does not store the private key. |
| `infrastructure/cilium/helmrelease.yaml` or rendered manifest set | Declare the validated Cilium install in Git. | Must preserve the working Talos values. | Must not drift from the bootstrap-tested settings without review. |
| `infrastructure/network/ip-pool.yaml` | Declare the `192.168.2.200-220` service pool. | LAN range must remain conflict-free. | Does not expose services by itself. |
| `infrastructure/network/l2-policy.yaml` | Announce service IPs on the real LAN NIC. | Interface name must match the live node. | Does not allocate IPs by itself. |
| `infrastructure/nvidia/runtimeclass.yaml` | Preserve the `nvidia` runtime class in Git. | Depends on NVIDIA runtime availability on the node. | Does not advertise GPU resources alone. |
| `infrastructure/nvidia/device-plugin.yaml` | Preserve the pinned NVIDIA device plugin in Git. | Prefer pinned versions and ideally pinned digests. | Does not install drivers. |
| `infrastructure/storage/*.yaml` | Create Talos-native volumes and default storage classes. | Must be written only after each non-system disk is mapped deliberately. | Must not target the Talos system disk. |
| `infrastructure/dns/*.yaml` | Deploy AdGuard Home and DNS service exposure. | Router cutover should happen only after validation. | Must not assume DNS is live before it is tested. |
| `apps/ai/*` | Deploy AI apps with explicit GPU mode-switching expectations. | Single RTX 3090 means one heavy GPU workload at a time. | Must not schedule all GPU consumers concurrently by default. |

## Before Flux bootstrap

1. Create the missing manifests listed above.
2. Generate `age.key` and record the public key.
3. Create `.sops.yaml`.
4. Encrypt any secret-bearing YAML.
5. Verify the cluster endpoint and live node IP handling.
6. Then bootstrap Flux against this directory.
