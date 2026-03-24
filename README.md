# Prometheus

![Talos OS](https://img.shields.io/badge/Talos_OS-v1.12.6-orange?style=for-the-badge&logo=kubernetes&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.35.2-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)
![Cilium](https://img.shields.io/badge/Cilium-1.18.0-E8C229?style=for-the-badge&logo=cilium&logoColor=black)
![NVIDIA](https://img.shields.io/badge/RTX_3090-24GB_VRAM-76B900?style=for-the-badge&logo=nvidia&logoColor=white)
![Flux](https://img.shields.io/badge/Flux-planned-lightgrey?style=for-the-badge&logo=flux&logoColor=white)

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
│  │                 5950X TOWER  (Primary Node)                │  │
│  │                                                            │  │
│  │  CPU:   AMD Ryzen 9 5950X  (16C / 32T)                     │  │
│  │  GPU:   NVIDIA GeForce RTX 3090  (24 GB VRAM)              │  │
│  │  Role:  Control Plane + GPU Worker                         │  │
│  │                                                            │  │
│  │  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │  │
│  │  │    Cilium    │    │    NVIDIA    │    │  Local Path  │  │  │
│  │  │   CNI + L2   │    │  GPU Plugin  │    │ Provisioner  │  │  │
│  │  └──────────────┘    └──────────────┘    └──────────────┘  │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Network:       192.168.2.0/24                                   │
│  API VIP:       192.168.2.46                                     │
│  Service Pool:  192.168.2.200-220  (L2 announced)                │
│                                                                  │
│  ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─┐  │
│    FUTURE:  3x NUC Workers                                       │
│  │ Control plane migrates to NUCs — tower becomes GPU-only    │  │
│  │ HA etcd across 3 nodes, Wake-on-LAN for tower              │  │
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
| **GitOps** | Flux | Declarative cluster reconciliation | Scaffolded |
| **Secrets** | SOPS + age | Encrypted secrets in git | Planned |
| **Observability** | Prometheus + Grafana | Metrics, dashboards, alerting | Planned |
| **DNS** | AdGuard Home | Local DNS + ad blocking | Planned |
| **AI -- LLM Serving** | Ollama | OpenAI-compatible local LLM API | Next |
| **AI -- Web UI** | Open WebUI | Web frontend for local models | Next |
| **AI -- High-Throughput** | vLLM | Continuous batching, production model serving | Planned |
| **AI -- Image Gen** | ComfyUI | Node-based Stable Diffusion workflows | Planned |
| **Media** | Arr Stack + Jellyfin | Sonarr, Radarr, Prowlarr, qBittorrent | Migration |
| **Photos** | Immich | Self-hosted photo management with ML | Planned |

---

## Current State

The cluster is live. Single-node control plane, bootstrapped and healthy.

- [x] Talos OS installed on dedicated SSD
- [x] Kubernetes API reachable via VIP (`192.168.2.46:6443`)
- [x] Cilium CNI operational with L2 announcements and LoadBalancer IPAM
- [x] LoadBalancer service tested and responding on allocated IP
- [x] NVIDIA kernel modules loaded (`nvidia`, `nvidia_uvm`, `nvidia_drm`, `nvidia_modeset`)
- [x] GPU test pod ran `nvidia-smi` -- RTX 3090 confirmed and allocatable
- [x] NVIDIA RuntimeClass and device plugin running
- [ ] Router DHCP reservation to pin tower IP
- [ ] Talos UserVolumeConfig storage manifests
- [ ] Flux bootstrap and SOPS/age setup
- [ ] AdGuard Home deployment
- [ ] AI workload deployment (Ollama, Open WebUI, vLLM, ComfyUI)
- [ ] Media stack migration from MIMIR

---

## Roadmap

### Phase 1 -- Foundation *(current)*

Bare-metal Kubernetes on Talos OS with Cilium networking and verified GPU acceleration. Bootstrap infrastructure is documented and reproducible.

### Phase 2 -- AI Inference Platform

Deploy the AI workload stack on the RTX 3090:

- **Ollama** as the daily-driver LLM (13B-22B parameter models)
- **Open WebUI** as the local web frontend
- **vLLM** for high-throughput API serving (scaled to zero when idle)
- **ComfyUI** for image generation workflows (scaled to zero when idle)
- GPU mode-switching via `kubectl scale` -- one GPU consumer at a time (no MIG on 3090)

### Phase 3 -- High Availability + Training

- Introduce 3x NUC workers to form HA control plane (3-node etcd)
- Tower becomes a dedicated GPU worker with no control plane duties
- Wake-on-LAN for tower power management
- Model fine-tuning and distributed training experiments

### Phase 4 -- Full Platform

- Flux GitOps with SOPS-encrypted secrets -- cluster state fully in git
- Prometheus + Grafana observability stack
- AdGuard Home for DNS and ad blocking
- Arr media stack migration from MIMIR
- Immich photo management with GPU-accelerated ML
- CI/CD pipelines for image builds and deployment automation

---

## Project Structure

| Path | Purpose | Notes |
|------|---------|-------|
| `plan-addendum-ai-workloads-gpu-nuc.md` | AI workload strategy and NUC expansion plan | Helm specs, GPU sharing strategy, migration procedures |
| `tower-bootstrap/` | Bootstrap artifacts for the Talos cluster | Rendered manifests, Cilium and NVIDIA setup |
| `tower-bootstrap/README.md` | Bootstrap file inventory | Documents every artifact and its role |
| `homelab-gitops/` | Future Flux GitOps repository scaffold | Directory structure ready, manifests not yet authored |
| `homelab-gitops/README.md` | GitOps scaffold plan | Intended directory layout for Flux reconciliation |

---

## Skills Demonstrated

| Domain | What This Covers |
|--------|-----------------|
| **Bare-Metal Kubernetes** | Bootstrapping K8s from scratch on real hardware, no managed services |
| **Immutable Infrastructure** | Talos OS -- no SSH, no mutation, API-driven node lifecycle |
| **Advanced Networking** | Cilium as kube-proxy replacement, L2 announcements, LoadBalancer IPAM |
| **GPU Scheduling** | NVIDIA device plugin, RuntimeClass, VRAM-aware workload planning |
| **Infrastructure as Code** | Declarative machine configs, rendered manifests, version-pinned components |
| **GitOps** | Flux scaffold, SOPS secrets strategy, cluster-state-as-code |
| **AI/ML Infrastructure** | GPU sharing design, model serving pipelines, inference workload planning |
| **Capacity Planning** | Multi-phase expansion with HA migration path and cost analysis |

---

## Why "Prometheus"

In Greek mythology, Prometheus stole fire from the gods and gave it to humanity -- knowledge and power that was never meant to leave Olympus.

Same idea here. Instead of renting compute from cloud providers and feeding data to corporate APIs, this runs the models locally, on owned hardware, with full control.
