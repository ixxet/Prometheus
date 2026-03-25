# Prometheus

![Talos OS](https://img.shields.io/badge/Talos_OS-v1.12.6-orange?style=for-the-badge&logo=kubernetes&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.35.2-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)
![Cilium](https://img.shields.io/badge/Cilium-1.18.0-E8C229?style=for-the-badge&logo=cilium&logoColor=black)
![NVIDIA](https://img.shields.io/badge/RTX_3090-24GB_VRAM-76B900?style=for-the-badge&logo=nvidia&logoColor=white)
![Flux](https://img.shields.io/badge/Flux-authored_in_repo-lightgrey?style=for-the-badge&logo=flux&logoColor=white)

> Bare-metal Kubernetes on owned hardware. Self-hosted AI inference, media automation, and full infrastructure sovereignty.

---

## Origin

This started as **MIMIR** -- a Debian box running k3s with the Arr media stack (Sonarr, Radarr, Prowlarr, qBittorrent, Jellyfin). It worked, but it was fragile. Mutable OS, manual SSH sessions, no GPU integration, config drift everywhere.

I needed something better:

- An immutable OS with no SSH and no drift
- GPU-native AI workloads -- local LLMs, image generation, model serving
- Real infrastructure patterns -- GitOps, declarative networking, secrets management
- Full ownership over compute and data

So I rebuilt from scratch on **Talos OS** -- a minimal, immutable Kubernetes operating system. No shell, no package manager, just an API and a signed image.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                        PROMETHEUS CLUSTER                        │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │                5950X TOWER (Primary Node)                  │  │
│  │                                                            │  │
│  │  CPU:  AMD Ryzen 9 5950X (16C/32T)                         │  │
│  │  GPU:  NVIDIA GeForce RTX 3090 (24GB VRAM)                 │  │
│  │  Role: Control Plane + GPU Worker                          │  │
│  │                                                            │  │
│  │  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │  │
│  │  │    Cilium    │    │    NVIDIA    │    │     Flux     │  │  │
│  │  │   CNI + L2   │    │  GPU Plugin  │    │    Staged    │  │  │
│  │  └──────────────┘    └──────────────┘    └──────────────┘  │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Network:      192.168.2.0/24                                    │
│  API VIP:      192.168.2.46                                      │
│  Service Pool: 192.168.2.200-220 (L2 announced)                  │
│                                                                  │
│  ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─┐  │
│  │ FUTURE: NUC expansion path                                 │  │
│  │ App-tier first, then HA control-plane work when justified  │  │
│  │ Tower stays primary until the platform proves itself       │  │
│  └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─┘  │
└──────────────────────────────────────────────────────────────────┘
```

---

## Tech Stack

| Layer | Technology | Version / Detail | Status |
|-------|-----------|-----------------|--------|
| **Infrastructure OS** | Talos OS | v1.12.6 -- immutable, API-driven, no SSH | Live |
| **Orchestration** | Kubernetes | v1.35.2 | Live |
| **CNI / Networking** | Cilium | 1.18.0 -- kube-proxy replacement, L2 LoadBalancer, IPAM | Live |
| **GPU Runtime** | NVIDIA Device Plugin | v0.17.0 -- RTX 3090, 24 GB VRAM | Live |
| **GitOps** | Flux | Authored entrypoints and staged `Kustomization` graph | Authored, not live |
| **Secrets** | SOPS + age | Encrypted secrets in git | Planned |
| **Observability** | Prometheus + Grafana | Metrics, dashboards, alerting | Planned |
| **DNS** | AdGuard Home | Local DNS + ad blocking | Authored, suspended |
| **AI -- Serving Backend** | vLLM | OpenAI-compatible high-throughput model serving | Next |
| **AI -- Web UI** | Open WebUI | Web frontend for local models | Authored, suspended |
| **AI -- Agent Runtime** | LangGraph | Stateful orchestration, retries, HITL resume, checkpoints | Planned next |
| **AI -- State Store** | Postgres | Checkpoints plus long-term application store | Planned next |
| **AI -- Semantic Memory** | Mem0 | Durable facts, preferences, and project conventions | Optional next layer |
| **AI -- Archive Sink** | Obsidian | Human-readable summaries, ADRs, and project logs | Planned |
| **AI -- Local LLM Runtime** | Ollama | Easy local model management | Authored, parked |
| **AI -- Image Gen** | ComfyUI | Node-based Stable Diffusion workflows | Planned |
| **Media** | Arr Stack + Jellyfin | Sonarr, Radarr, Prowlarr, qBittorrent | Migration |
| **Photos** | Immich | Self-hosted photo management with ML | Planned |

---

## Current State

The base cluster is live. The next GitOps layer is authored in the repo, render-
validated, and intentionally not active yet.

### Already real in the live cluster

- [x] Talos OS installed on the dedicated `LITEONIT LCS-256L9S-11` SSD only
- [x] Single-node Kubernetes control plane is healthy
- [x] Tower is currently booted on DHCP `192.168.2.49`
- [x] Kubernetes API is reachable via VIP `192.168.2.46:6443`
- [x] Cilium is live with kube-proxy replacement, L2 announcements, and `LoadBalancer` IPAM
- [x] A disposable `LoadBalancer` service was tested successfully on the LAN
- [x] NVIDIA kernel modules are loaded on Talos
- [x] `RuntimeClass` `nvidia` and the pinned device plugin are running
- [x] A disposable GPU test pod ran `nvidia-smi` and confirmed an RTX 3090 is allocatable

### Real in the repo, but not yet live

- [x] Flux entrypoints under `homelab-gitops/clusters/talos-tower/`
- [x] GitOps definitions for Cilium, network policy, and NVIDIA support
- [x] Kubernetes-side local-path provisioner manifests
- [x] Talos-side `UserVolumeConfig` documents for non-system disks
- [x] AdGuard Home manifests with a fixed `LoadBalancer` IP plan
- [x] Open WebUI manifests with staged Flux `Kustomization` objects
- [x] Ollama manifests, now intentionally parked after the vLLM-first pivot
- [x] All of the above render cleanly with `kubectl kustomize`
- [ ] Flux is not bootstrapped against `homelab-gitops` yet

### Not yet authored or activated

- [ ] `.sops.yaml` and the `age` key material
- [ ] vLLM manifests
- [ ] LangGraph manifests
- [ ] Postgres manifests
- [ ] Obsidian summary/export workflow
- [ ] Semantic memory integration (`Mem0` likely, `LangMem` alternative)
- [ ] ComfyUI manifests
- [ ] Media stack manifests
- [ ] Immich manifests
- [ ] Runbooks for disaster recovery, add-worker, DNS cutover, and GPU mode switching

### Deferred on purpose

- [ ] Router DHCP reservation to move the node from `.49` back to `.45`
- [ ] MIMIR integration, migration, or endpoint cutover
- [ ] LiteLLM until there is more than one serving backend or a real cloud-fallback need
- [ ] Graphiti/Zep temporal graph memory until point-in-time relationship queries are a real requirement
- [ ] Letta because LangGraph is the chosen orchestrator

### Paused for safety

- [ ] No Talos `UserVolumeConfig` has been applied yet
- [ ] Live disk review showed the current non-system SSD and NVMe targets are in use elsewhere
- [ ] The 256 GB Talos SSD has about `8.11 GB` used on `/var`, so the system can host early app/runtime state while storage remains unresolved

---

## Roadmap

### Phase 1 -- Foundation *(current)*

Bare-metal Kubernetes on Talos OS with Cilium networking and verified GPU acceleration. Bootstrap infrastructure is documented and reproducible, and the first GitOps layer is now authored in-repo.

### Phase 2 -- AI Agent Platform

Deploy the smallest coherent local agent stack on the RTX 3090:

- **AdGuard Home** first, so LAN DNS exists before app sprawl starts
- **Open WebUI** as the human UI, pointed at an OpenAI-compatible backend
- **vLLM** as the first and only model-serving backend
- **LangGraph** as the orchestrator for tool loops, retries, and human-in-the-loop resume
- **Postgres** as the production store for LangGraph checkpoints and long-term application state
- **Obsidian** as a human-readable summary sink, not the primary machine memory system
- **Mem0** as the likely semantic memory layer for durable facts and preferences

Explicit non-goals for this phase:

- No Ollama in the first activation wave
- No LiteLLM until there are multiple backends or cloud fallback
- No Graphiti/Zep temporal graph memory yet
- No Letta; LangGraph is the orchestrator

### Phase 3 -- High Availability + Training

- Keep the NUC on Debian in the near term and use it as a low-level app/CPU host if needed
- HA control-plane work remains the long-term direction after the single-node platform proves stable under load
- Later move the NUC into the cluster only when that buys real operational clarity
- Decide later whether the tower should remain primary or move to GPU-only duties
- Wake-on-LAN remains a later optimization, not part of the base rollout
- Model fine-tuning and distributed training experiments

### Phase 4 -- Full Platform

- Flux GitOps with SOPS-encrypted secrets -- cluster state fully in git
- Prometheus + Grafana observability stack
- AdGuard Home fully cut over as the LAN DNS authority
- Arr media stack migration from MIMIR, if that still makes sense after the Talos platform settles
- Immich photo management with GPU-accelerated ML
- Second SSD for fast AI/model-cache storage
- HDD or Unraid as bulk/cold storage
- CI/CD pipelines for image builds and deployment automation

---

## Project Structure

| Path | Purpose | Notes |
|------|---------|-------|
| `plan-addendum-ai-workloads-gpu-nuc.md` | AI workload strategy and NUC expansion plan | Helm specs, GPU sharing strategy, migration procedures |
| `docs/agent-memory-architecture.md` | Revised AI and memory architecture | Records the `vLLM + LangGraph + Postgres + Obsidian` pivot and compares `Mem0` vs `LangMem` |
| `tower-bootstrap/` | Bootstrap artifacts for the Talos cluster | Rendered manifests, Cilium and NVIDIA setup |
| `tower-bootstrap/README.md` | Bootstrap file inventory | Documents every artifact and its role |
| `homelab-gitops/` | Authored GitOps tree for the next cluster state | Render-valid, but Flux is not bootstrapped and some layers are suspended |
| `homelab-gitops/README.md` | GitOps stage inventory | Documents what is authored, what is suspended, and what remains missing |

---

## What this covers

This isn't a tutorial or a template -- it's a working cluster, and building it meant solving real problems:

- Bootstrapping Kubernetes on bare metal without a managed service handling the hard parts
- Running Talos OS, where there's no SSH and no shell -- everything goes through the API or not at all
- Replacing kube-proxy entirely with Cilium and getting L2 announcements working so services show up on the LAN
- Getting NVIDIA drivers loaded inside an immutable OS using Talos extensions, then wiring up the device plugin and RuntimeClass
- Choosing where agent state, semantic memory, and human-readable archives should actually live
- Designing a migration path from bootstrap artifacts to GitOps-managed state without tearing everything down

---

## Why "Prometheus"

In Greek mythology, Prometheus stole fire from the gods and gave it to humanity -- knowledge and power that was never meant to leave Olympus.

Same idea here. Instead of renting compute from cloud providers and feeding data to corporate APIs, this runs the models locally, on owned hardware, with full control.

<!-- repository metadata refresh: 2026-03-24 -->
