# Plan Addendum: AI Workloads, GPU Strategy & NUC Expansion

> Attach this to the main plan (talos-homelab-plan-v2-FINAL.md).
> This replaces Phase 8 (vLLM only) with a broader AI workload strategy.
>
> Status note (2026-03-24): this document includes earlier planning values and a
> future NUC expansion path. The live cluster state has since diverged in a few
> important places: the active Kubernetes API VIP is `192.168.2.46`, the tower is
> currently on DHCP `192.168.2.49` with `.45` still the intended reservation, and
> MIMIR integration or endpoint cutover is intentionally deferred until the base
> Talos platform, storage, DNS, and GitOps layers are finished.
>
> Status note (2026-03-25): this addendum is now a historical planning document,
> not the current source of truth for the agent stack. The current preferred
> direction is recorded in `docs/agent-memory-architecture.md` and pivots toward
> `vLLM + LangGraph + Postgres + Obsidian`, with `Mem0` as the likely semantic
> memory layer and `Ollama` no longer in the first activation wave.

---

## Cluster Topology (Current + Future)

```
┌──────────────────────────────────────────────────┐
│                   YOUR LAN                        │
│                                                    │
│   ┌─────────────┐     ┌─────────────────────┐    │
│   │  MacBook M1  │     │  5950X Tower         │    │
│   │  (remote     │────▶│  Control Plane +     │    │
│   │   control)   │     │  GPU Worker          │    │
│   │              │     │  • RTX 3090 (24GB)   │    │
│   │  NOT in the  │     │  • Talos OS on 256GB │    │
│   │  cluster     │     │  • VIP: 192.168.2.40 │    │
│   └─────────────┘     │  • IP:  192.168.2.45 │    │
│                        └─────────────────────┘    │
│                              ▲                     │
│                              │ K8s cluster         │
│   ┌─────────────┐           │                     │
│   │  NUC         │───────────┘                    │
│   │  (future     │  Worker node (no GPU)          │
│   │   worker)    │  Runs: Arr stack, DBs, Immich  │
│   └─────────────┘                                 │
│                                                    │
│   ┌─────────────┐  ┌─────────────┐               │
│   │  Phone/iPad  │  │  Other PCs   │  ← consumers │
│   │  (Open WebUI │  │  (VS Code +  │    via LAN   │
│   │   Jellyfin)  │  │   Continue)  │    LoadBalancer│
│   └─────────────┘  └─────────────┘               │
└──────────────────────────────────────────────────┘
```

**Key principle:** The 5950X is the only GPU node. It handles all AI workloads.
The NUC (when added) handles lightweight CPU workloads. Your Mac and other
devices are consumers, not cluster members.

---

## GPU Sharing Strategy: "One at a Time" Mode Switching

The RTX 3090 has 24GB VRAM. It does NOT support MIG (that's A100+ only).
Time-slicing splits performance and adds latency — bad for inference.

**Instead: deploy all AI workloads but only scale one up at a time.**

```
                    ┌──────────────────┐
                    │   RTX 3090       │
                    │   24GB VRAM      │
                    └────────┬─────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
        ┌─────▼─────┐ ┌─────▼─────┐ ┌─────▼─────┐
        │  Ollama    │ │  vLLM     │ │  ComfyUI  │
        │ replicas:1 │ │ replicas:0│ │ replicas:0│
        │  ACTIVE    │ │  sleeping │ │  sleeping │
        └───────────┘ └───────────┘ └───────────┘

  "I want to generate images" →
        ┌───────────┐ ┌───────────┐ ┌───────────┐
        │  Ollama    │ │  vLLM     │ │  ComfyUI  │
        │ replicas:0 │ │ replicas:0│ │ replicas:1│
        │  sleeping  │ │  sleeping │ │  ACTIVE   │
        └───────────┘ └───────────┘ └───────────┘
```

You switch modes with a simple `kubectl scale` command, or we can build
a small script/alias:

```bash
# Mode: Ollama (chat, coding assistants, API)
alias gpu-ollama='kubectl scale deploy -n ai ollama --replicas=1 && \
  kubectl scale deploy -n ai vllm --replicas=0 && \
  kubectl scale deploy -n ai comfyui --replicas=0'

# Mode: vLLM (high-throughput API serving)
alias gpu-vllm='kubectl scale deploy -n ai vllm --replicas=1 && \
  kubectl scale deploy -n ai ollama --replicas=0 && \
  kubectl scale deploy -n ai comfyui --replicas=0'

# Mode: ComfyUI (image generation)
alias gpu-comfyui='kubectl scale deploy -n ai comfyui --replicas=1 && \
  kubectl scale deploy -n ai ollama --replicas=0 && \
  kubectl scale deploy -n ai vllm --replicas=0'

# Mode: All off (free the GPU)
alias gpu-off='kubectl scale deploy -n ai ollama vllm comfyui --replicas=0'
```

Later, this can be wrapped in a small web UI or automated with priority scheduling.

---

## AI Workload Breakdown

### Workload 1: Ollama (Daily Driver)

**What it does:** Runs LLMs locally with an OpenAI-compatible API. Supports
hot-swapping models, has a great CLI, and integrates with everything.

**Your use cases:**
- Coding assistant via Continue (VS Code) or Cody → point at `http://ollama.ai.svc:11434`
- Chat via Open WebUI → ChatGPT-like web interface on your LAN
- API for scripts/apps → standard OpenAI API at the LoadBalancer IP

**Models that fit your 3090 (24GB):**

| Model | Size | VRAM Used | Use Case |
|-------|------|-----------|----------|
| Codestral 22B (Q4) | ~13 GB | ~14 GB | Best coding model for Ollama |
| Deepseek-Coder-V2-Lite 16B | ~9 GB | ~11 GB | Fast coding, good quality |
| Llama 3.1 8B | ~5 GB | ~7 GB | General chat, very fast |
| Mistral 7B Instruct | ~4 GB | ~6 GB | General purpose, fast |
| Qwen2.5-Coder 14B (Q4) | ~8 GB | ~10 GB | Strong coding alternative |
| Llama 3.1 70B (Q3_K_S) | ~20 GB | ~22 GB | Smartest, but tight fit, slower |

**Ollama Helm deployment:**

```yaml
# apps/ai/ollama/helmrelease.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: ollama-helm
  namespace: ai
spec:
  interval: 24h
  url: https://otwld.github.io/ollama-helm/
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: ollama
  namespace: ai
spec:
  interval: 30m
  chart:
    spec:
      chart: ollama
      version: "1.*"              # pin to major
      sourceRef:
        kind: HelmRepository
        name: ollama-helm
  values:
    ollama:
      gpu:
        enabled: true
        type: nvidia
        number: 1
      models:
        pull:
          - codestral:22b-v0.1-q4_K_M
          - llama3.1:8b
    runtimeClassName: nvidia
    resources:
      requests:
        nvidia.com/gpu: "1"
      limits:
        nvidia.com/gpu: "1"
    persistentVolume:
      enabled: true
      size: 100Gi                 # model cache
    service:
      type: LoadBalancer          # reachable from LAN
```

### Workload 2: Open WebUI (Chat Interface)

**What it does:** A self-hosted ChatGPT-like web interface that talks to Ollama.
Runs on CPU only — no GPU needed. Can run on the NUC later.

```yaml
# apps/ai/open-webui/helmrelease.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: open-webui
  namespace: ai
spec:
  interval: 24h
  url: https://helm.openwebui.com/
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: open-webui
  namespace: ai
spec:
  interval: 30m
  chart:
    spec:
      chart: open-webui
      version: "5.*"
      sourceRef:
        kind: HelmRepository
        name: open-webui
  values:
    ollamaUrls:
      - "http://ollama.ai.svc.cluster.local:11434"
    service:
      type: LoadBalancer
    persistence:
      enabled: true
      size: 10Gi
```

### Workload 3: vLLM (High-Throughput API)

**When to use instead of Ollama:** When you want to dedicate the GPU to serving
one model at maximum speed with continuous batching. Good for when multiple
apps/scripts are hitting the API concurrently.

```yaml
# apps/ai/vllm/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vllm
  namespace: ai
spec:
  replicas: 0                     # starts scaled to zero
  selector:
    matchLabels:
      app: vllm
  template:
    metadata:
      labels:
        app: vllm
    spec:
      runtimeClassName: nvidia
      containers:
      - name: vllm
        image: vllm/vllm-openai:v0.7.3      # pinned
        args:
          - "--model"
          - "mistralai/Mistral-7B-Instruct-v0.3"
          - "--dtype"
          - "bfloat16"
          - "--gpu-memory-utilization"
          - "0.85"
          - "--enable-chunked-prefill"
          - "--enable-prefix-caching"
          - "--host"
          - "0.0.0.0"
          - "--port"
          - "8000"
        env:
        - name: HF_TOKEN
          valueFrom:
            secretKeyRef:
              name: hf-token
              key: token
        ports:
        - containerPort: 8000
        resources:
          requests:
            nvidia.com/gpu: "1"
            memory: "16Gi"
            cpu: "4"
          limits:
            nvidia.com/gpu: "1"
            memory: "24Gi"
        volumeMounts:
        - name: cache
          mountPath: /root/.cache/huggingface
        - name: shm
          mountPath: /dev/shm
      volumes:
      - name: cache
        persistentVolumeClaim:
          claimName: vllm-models
      - name: shm
        emptyDir:
          medium: Memory
          sizeLimit: "4Gi"
---
apiVersion: v1
kind: Service
metadata:
  name: vllm
  namespace: ai
spec:
  type: LoadBalancer
  selector:
    app: vllm
  ports:
  - port: 8000
    targetPort: 8000
```

### Workload 4: ComfyUI (Image Generation)

**What it does:** Node-based UI for Stable Diffusion / SDXL / Flux image generation.
Needs the GPU exclusively when running.

```yaml
# apps/ai/comfyui/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: comfyui
  namespace: ai
spec:
  replicas: 0                     # starts scaled to zero
  selector:
    matchLabels:
      app: comfyui
  template:
    metadata:
      labels:
        app: comfyui
    spec:
      runtimeClassName: nvidia
      containers:
      - name: comfyui
        image: ghcr.io/ai-dock/comfyui:v1.3.42-cuda-12.1.1   # pin to specific tag
        ports:
        - containerPort: 8188
        resources:
          requests:
            nvidia.com/gpu: "1"
            memory: "16Gi"
          limits:
            nvidia.com/gpu: "1"
            memory: "24Gi"
        volumeMounts:
        - name: models
          mountPath: /opt/ComfyUI/models
        - name: output
          mountPath: /opt/ComfyUI/output
      volumes:
      - name: models
        persistentVolumeClaim:
          claimName: comfyui-models   # SD/SDXL/Flux checkpoints
      - name: output
        persistentVolumeClaim:
          claimName: comfyui-output
---
apiVersion: v1
kind: Service
metadata:
  name: comfyui
  namespace: ai
spec:
  type: LoadBalancer
  selector:
    app: comfyui
  ports:
  - port: 8188
    targetPort: 8188
```

---

## Coding Assistant Setup (Continue for VS Code)

Once Ollama is running with a coding model:

1. Install the **Continue** extension in VS Code
2. Configure it to point at your tower's Ollama service:

```json
// ~/.continue/config.json
{
  "models": [
    {
      "title": "Codestral (Tower)",
      "provider": "ollama",
      "model": "codestral:22b-v0.1-q4_K_M",
      "apiBase": "http://192.168.2.20x:11434"
    }
  ],
  "tabAutocompleteModel": {
    "title": "Codestral Autocomplete",
    "provider": "ollama",
    "model": "codestral:22b-v0.1-q4_K_M",
    "apiBase": "http://192.168.2.20x:11434"
  }
}
```

Replace `192.168.2.20x` with whatever LoadBalancer IP Cilium assigns to the Ollama service.

---

## NUC Expansion Plan

When you're ready to add the NUC:

### What Changes

- The NUC boots the same Talos ISO (or a simpler schematic without NVIDIA extensions)
- You apply `worker.yaml` (not `controlplane.yaml`) to it
- The NUC joins the existing cluster as a worker node
- You use node labels + affinity rules to control what runs where:

```bash
# Label the tower as the GPU node
kubectl label node talos-tower gpu=nvidia workload=ai

# Label the NUC as a CPU-only worker
kubectl label node talos-nuc workload=media
```

### What Moves to the NUC

Once the NUC joins, you can move CPU-only workloads off the tower:

| Workload | Node | Why |
|----------|------|-----|
| Ollama / vLLM / ComfyUI | Tower (5950X) | Needs GPU |
| Open WebUI | NUC | CPU only, web frontend |
| Sonarr / Radarr / Prowlarr | NUC | CPU only, light |
| qBittorrent | NUC | CPU only, I/O bound |
| Jellyfin (transcoding) | Tower | Can use GPU for hardware transcode |
| Immich (ML) | Tower | Uses GPU for face detection |
| Immich (web/DB) | NUC | CPU only |

### NUC Worker Config

```bash
# Generate a worker-specific patch
cat > nuc-patch.yaml << 'EOF'
machine:
  network:
    hostname: talos-nuc
  install:
    disk: /dev/sda              # whatever the NUC's disk is
    image: factory.talos.dev/installer/<BASIC_SCHEMATIC>:v1.12.6  # no NVIDIA needed
cluster:
  network:
    cni:
      name: none
  proxy:
    disabled: true
EOF

talosctl apply-config --insecure \
  --nodes <NUC_IP> \
  --file worker.yaml \
  --config-patch @nuc-patch.yaml
```

The NUC will automatically join the cluster and Cilium will extend to it.

---

## Updated Repo Structure

```
homelab-gitops/
├── .sops.yaml
├── clusters/
│   └── talos-tower/
│       ├── infrastructure.yaml
│       └── apps.yaml
├── infrastructure/
│   ├── cilium/
│   │   └── helmrelease.yaml
│   ├── nvidia/
│   │   ├── runtimeclass.yaml
│   │   └── device-plugin.yaml
│   ├── storage/
│   │   └── local-path-provisioner.yaml
│   └── service-exposure/
│       ├── ip-pool.yaml
│       └── l2-policy.yaml
└── apps/
    ├── ai/                          # ← NEW: unified AI namespace
    │   ├── namespace.yaml
    │   ├── ollama/
    │   │   └── helmrelease.yaml
    │   ├── open-webui/
    │   │   └── helmrelease.yaml
    │   ├── vllm/
    │   │   ├── deployment.yaml
    │   │   ├── model-pvc.yaml
    │   │   └── hf-secret.yaml      # SOPS encrypted
    │   └── comfyui/
    │       ├── deployment.yaml
    │       └── model-pvcs.yaml
    ├── arr-stack/
    │   ├── namespace.yaml
    │   ├── sonarr/helmrelease.yaml
    │   ├── radarr/helmrelease.yaml
    │   ├── prowlarr/helmrelease.yaml
    │   ├── qbittorrent/helmrelease.yaml
    │   └── jellyfin/helmrelease.yaml
    └── immich/
        ├── namespace.yaml
        └── helmrelease.yaml
```

---

## Summary: What to Deploy First

**Day 1 (immediately after Phases 1-7 of the main plan):**
1. Ollama + Open WebUI — your daily driver for chat and coding
2. Install Continue in VS Code, point at Ollama

**Day 2 (when you want to experiment):**
3. ComfyUI for image generation (scale Ollama to 0 first)

**Day 3+ (when you have a specific high-throughput need):**
4. vLLM for dedicated model serving

**When NUC arrives:**
5. Join as worker, migrate CPU workloads off the tower

---

## Future Plans: HA Control Plane + Sleeping GPU Tower

This section describes the end-state architecture where NUCs run the cluster
brain 24/7 and the 5950X tower only wakes up for GPU work.

### The Vision

```
PHASE 1 (TODAY)                        PHASE 2 (FUTURE)

┌──────────────┐                       ┌──────────────┐
│  5950X Tower │                       │  NUC-1       │◄─┐
│  CP + Worker │                       │  CP + Worker │  │
│  VIP: .40    │                       │  VIP: .40 ◄──│──│── VIP floats between
│  IP:  .45    │                       │  IP:  .41    │  │   all 3 control planes
│  GPU: 3090   │                       ├──────────────┤  │
│  Always on   │                       │  NUC-2       │◄─┤
└──────────────┘                       │  CP + Worker │  │
                                       │  IP:  .42    │  │
                                       ├──────────────┤  │
                                       │  NUC-3       │◄─┘
                                       │  CP + Worker │
                                       │  IP:  .43    │
                                       └──────┬───────┘
                                              │
                                              │ schedules GPU
                                              │ work via WoL
                                              ▼
                                       ┌──────────────┐
                                       │  5950X Tower │
                                       │  Worker ONLY │
                                       │  IP:  .45    │
                                       │  GPU: 3090   │
                                       │  Sleeps when │
                                       │  not needed  │
                                       └──────────────┘

Phase 1: Tower does everything. Single point of failure, but
         Flux + GitHub means rebuild takes ~30 min.

Phase 2: NUCs run the brain (etcd, API, scheduler) 24/7.
         Tower is a GPU worker that sleeps and wakes on demand.
         If any one NUC dies, the other two keep the cluster alive.
         If the tower dies, non-GPU workloads keep running.
```

### What You Must Do TODAY to Guarantee Easy Migration Later

These are non-negotiable. Miss any of these and the future migration
becomes a painful rebuild instead of a smooth expansion.

**1. Back up your cluster secrets (CRITICAL)**

When you run `talosctl gen config`, it generates a `secrets.yaml` file (or
embeds the secrets in `controlplane.yaml`). These contain:

- Cluster CA certificate + key
- etcd CA certificate + key
- Kubernetes SA key
- Bootstrap token
- Aggregation CA

When you add new control plane nodes later, they MUST use the same secrets.
If you lose them, you cannot expand the control plane — full rebuild required.

```bash
# After running gen config, immediately back up:
cp ~/talos-cluster/controlplane.yaml ~/talos-cluster/BACKUP-controlplane.yaml
cp ~/talos-cluster/talosconfig ~/talos-cluster/BACKUP-talosconfig

# If you generated a separate secrets file:
cp ~/talos-cluster/secrets.yaml ~/talos-cluster/BACKUP-secrets.yaml

# Store these somewhere SAFE and OFFLINE:
# - USB drive in a drawer
# - Password manager (1Password, Bitwarden)
# - Encrypted cloud backup
# DO NOT put these in Git, even encrypted — they are your cluster root keys
```

**2. Use the VIP as your API endpoint (already in the plan)**

We already set `gen config` to use `https://192.168.2.40:6443` as the
endpoint. This is the single most important future-proofing decision.
Every kubeconfig, every certificate, every Flux connection points at
`192.168.2.40`. When NUCs take over the control plane, the VIP moves
to them and nothing breaks. Do NOT change this to `192.168.2.45` later.

**3. Reserve IPs for future NUCs NOW**

Go into your router and reserve IPs today, even if you don't have the
NUCs yet. This prevents your router from handing these IPs to random
devices and causing conflicts on migration day.

```
192.168.2.40  →  VIP (floating, no MAC reservation needed)
192.168.2.41  →  Future NUC-1
192.168.2.42  →  Future NUC-2
192.168.2.43  →  Future NUC-3
192.168.2.45  →  5950X Tower (already reserved)
```

**4. Keep your Talos version + schematic documented**

When the NUCs join, they need a compatible Talos version. Document what
you're running today:

```bash
# Run this after install and save the output
talosctl version --nodes 192.168.2.45
talosctl get extensions --nodes 192.168.2.45

# Save to a file in your gitops repo (non-secret info, safe for Git)
echo "Talos version: v1.12.6" > cluster-info.txt
echo "Schematic ID: <your-schematic-id>" >> cluster-info.txt
echo "NVIDIA extensions: yes (production drivers)" >> cluster-info.txt
echo "NUC schematic: needs separate, no NVIDIA" >> cluster-info.txt
```

**5. Use node labels from day one**

Even though you only have one node today, label it now. This means your
Flux manifests already have the correct affinity rules, and when the NUC
joins, workloads automatically migrate without editing any YAML.

```bash
# Run after the cluster is up
kubectl label node talos-tower \
  node-role.kubernetes.io/gpu-worker="" \
  gpu=nvidia \
  topology.kubernetes.io/zone=tower
```

Then in your GPU workload manifests, always include:

```yaml
spec:
  template:
    spec:
      nodeSelector:
        gpu: nvidia
```

When the NUC joins and doesn't have the `gpu: nvidia` label, GPU workloads
stay on the tower automatically. CPU workloads without a nodeSelector can
float to whichever node has capacity.

### The Migration Procedure (When You Have 3 NUCs)

This is the step-by-step for the actual cutover. Save it for later.

**Estimated time:** 2-3 hours for a careful migration.

**Step 1: Prepare NUC boot media**

Create a Talos ISO for the NUCs (no NVIDIA extensions needed):

```yaml
# nuc-schematic.yaml
customization:
  systemExtensions:
    officialExtensions:
      - siderolabs/intel-ucode    # or amd-ucode depending on NUC CPU
```

Submit to Image Factory, download the ISO, flash to USB drives.

**Step 2: Boot all 3 NUCs into Talos maintenance mode**

Each NUC gets its own IP (192.168.2.41, .42, .43).

**Step 3: Join NUCs as control plane nodes**

You need the original cluster secrets. This is why Step 1 of
"What You Must Do TODAY" matters:

```bash
# Generate configs for the new control plane nodes using existing secrets
talosctl gen config my-cluster https://192.168.2.40:6443 \
  --output-dir ./nuc-configs \
  --with-secrets ~/talos-cluster/secrets.yaml \
  --with-docs=false \
  --with-examples=false
```

Create patches for each NUC:

```bash
# nuc1-patch.yaml
cat > nuc1-patch.yaml << 'EOF'
machine:
  network:
    hostname: talos-nuc1
    interfaces:
      - interface: enp1s0        # NUC interface name
        vip:
          ip: 192.168.2.40      # same VIP — all CP nodes share it
  install:
    disk: /dev/sda
    image: factory.talos.dev/installer/<NUC_SCHEMATIC_ID>:v1.12.6
  kubelet:
    extraMounts:
      - destination: /var/mnt/local-path-provisioner
        type: bind
        source: /var/mnt/local-path-provisioner
        options: [bind, rshared, rw]
cluster:
  network:
    cni:
      name: none
  proxy:
    disabled: true
  allowSchedulingOnControlPlanes: true
EOF
```

Apply to each NUC:

```bash
talosctl apply-config --insecure --nodes 192.168.2.41 \
  --file nuc-configs/controlplane.yaml --config-patch @nuc1-patch.yaml

talosctl apply-config --insecure --nodes 192.168.2.42 \
  --file nuc-configs/controlplane.yaml --config-patch @nuc2-patch.yaml

talosctl apply-config --insecure --nodes 192.168.2.43 \
  --file nuc-configs/controlplane.yaml --config-patch @nuc3-patch.yaml
```

Each NUC installs Talos, reboots, and joins the existing etcd cluster.
Talos handles etcd membership expansion automatically.

**Step 4: Verify etcd quorum (4 members: tower + 3 NUCs)**

```bash
talosctl etcd members --nodes 192.168.2.45
```

You should see 4 members. The VIP may have already moved to a NUC.

**Step 5: Demote the tower from control plane to worker**

This is the key step. You need to:

1. Remove the tower from etcd
2. Re-apply its config as a worker (not control plane)

```bash
# Remove the tower from etcd membership
talosctl etcd remove-member <tower-etcd-member-id> --nodes 192.168.2.41

# Generate a worker config with the same cluster secrets
# Then apply it to the tower with a reset
talosctl apply-config --nodes 192.168.2.45 \
  --file nuc-configs/worker.yaml \
  --config-patch @tower-worker-patch.yaml \
  --mode reboot
```

The tower reboots and comes back as a pure worker node.
The VIP now floats between the 3 NUCs only.

**Step 6: Verify the final state**

```bash
# Check etcd — should show 3 members (NUCs only)
talosctl etcd members --nodes 192.168.2.41

# Check nodes — tower should show as worker
kubectl get nodes
# NAME          STATUS   ROLES           AGE
# talos-nuc1    Ready    control-plane   10m
# talos-nuc2    Ready    control-plane   10m
# talos-nuc3    Ready    control-plane   10m
# talos-tower   Ready    <none>          30d    ← worker now

# GPU should still be available
kubectl describe node talos-tower | grep nvidia.com/gpu
```

**Step 7: Set up Wake-on-LAN for the tower**

Enable WoL in the tower's BIOS (usually under Power Management or
Network Boot). Then from any NUC or machine on the LAN:

```bash
# Install etherwake or wakeonlan
# Replace with the tower's MAC address
etherwake -i enp1s0 AA:BB:CC:DD:EE:FF

# Or use a Kubernetes CronJob that wakes the tower on a schedule
```

When the tower powers off and you want GPU work:

1. Send WoL packet → tower boots
2. Talos starts automatically → node joins cluster
3. Pending GPU pods get scheduled → work happens
4. When done: `kubectl cordon talos-tower && kubectl drain talos-tower`
5. `talosctl shutdown --nodes 192.168.2.45` → tower sleeps

### What Breaks During Migration (Honest Assessment)

| Risk | Severity | Mitigation |
|------|----------|------------|
| Lost cluster secrets | FATAL — full rebuild | Back them up TODAY (see above) |
| etcd corruption during member changes | HIGH — cluster down | Take an etcd snapshot before starting |
| VIP doesn't float to NUCs | MEDIUM — API unreachable | Verify VIP config in all NUC patches |
| GPU pods scheduled before tower is ready | LOW — pods pending | Talos auto-readies; pods wait naturally |
| Talos version mismatch between tower and NUCs | LOW — join fails | Document your version today |
| Cilium doesn't extend to new nodes | LOW — networking broken | Cilium DaemonSet auto-deploys to new nodes |

### Pre-Migration Checklist (Run Before Starting)

```bash
# 1. Verify you have the secrets
ls -la ~/talos-cluster/secrets.yaml  # or controlplane.yaml
# If missing: STOP. You cannot proceed.

# 2. Take an etcd snapshot
talosctl etcd snapshot ~/talos-cluster/etcd-backup-$(date +%Y%m%d).db \
  --nodes 192.168.2.45

# 3. Back up all Flux state (should already be in Git, but verify)
flux get all -A

# 4. Verify your Git repo is up to date
cd ~/homelab-gitops && git status

# 5. Document current state
talosctl version --nodes 192.168.2.45
talosctl get extensions --nodes 192.168.2.45
kubectl get nodes -o wide
```

### Cost Estimate for the HA Upgrade

For reference, here's what 3 NUCs would cost (as of 2026):

| Option | Approx Cost | Notes |
|--------|-------------|-------|
| 3x Intel NUC 13 Pro (i5, 16GB, 256GB) | ~$900-1200 | Solid, quiet, low power |
| 3x Beelink Mini S12 Pro (N100, 16GB) | ~$450-600 | Budget, surprisingly capable |
| 3x Lenovo ThinkCentre Tiny (used) | ~$300-450 | Great value, enterprise reliable |

The N100-based minis are honestly fine for control plane + light workloads.
etcd doesn't need much CPU — it needs fast storage and reliable networking.

---

## The Complete Timeline

```
NOW         → Phase 1: Single 5950X control plane + GPU worker
              Back up secrets, reserve IPs, label nodes

WEEKS 1-4   → Get comfortable: Ollama, Open WebUI, Arr stack
              Everything managed by Flux

MONTH 2-3   → Add first NUC as WORKER (not control plane)
              Move Arr stack + DBs to the NUC
              Tower focuses on GPU workloads

MONTH 4-6+  → Buy 2 more NUCs, promote all 3 to control plane
              Demote tower to worker-only
              Enable Wake-on-LAN
              Tower sleeps until GPU needed
              Full HA — any single machine can die without downtime
```

---

## Execution Status Update (2026-03-24)

This section supersedes older example values in this file where they referenced
VIP `192.168.2.40` and tower IP `192.168.2.45` as the live state.

### Live state right now

- Talos was installed only to the confirmed internal SSD:
  - Model: `LITEONIT LCS-256L9S-11`
  - Serial: `TW03YYV3550854BP0700`
- The Ventoy USB was not used as the install target.
- The Kubernetes API VIP is `192.168.2.46`.
- The tower is currently running on DHCP address `192.168.2.49`.
- The desired long-term reservation is still `192.168.2.45`, but that reservation was not active when the node booted.
- Cilium `1.18.0` is installed and the node is healthy.
- `LoadBalancer` IPAM and L2 announcements are active for `192.168.2.200-192.168.2.220`.
- NVIDIA support is active and the GPU is schedulable as `nvidia.com/gpu=1`.

### What has been accomplished

1. Disk-safe install path
- Verified the internal 256 GB SSD and the 256 GB Ventoy USB separately.
- Initial selector mismatch failed safely before any write occurred.
- Successful install used the confirmed internal SSD only.

2. Talos bring-up
- Generated Talos config against the API VIP.
- Applied the patched control-plane config.
- Bootstrapped the cluster successfully.
- Retrieved working `talosconfig` and `kubeconfig`.

3. Networking
- Installed pinned Cilium `1.18.0`.
- Verified the node transitions to `Ready`.
- Applied `CiliumLoadBalancerIPPool` and `CiliumL2AnnouncementPolicy`.
- Verified a disposable `LoadBalancer` service answered on `192.168.2.220` from the Mac.

4. GPU enablement
- Verified NVIDIA kernel modules on the node.
- Created `RuntimeClass` `nvidia`.
- Installed the pinned NVIDIA device plugin `v0.17.0`.
- Verified `nvidia.com/gpu: 1` on the node.
- Ran a GPU test pod that successfully returned `nvidia-smi` for the RTX 3090.

### What is left

1. Node addressing and DNS
- Fix the router reservation so the tower reliably returns to `192.168.2.45`.
- Deploy AdGuard Home.
- Create `home.arpa` records and rewrites:
  - `k8s.home.arpa -> 192.168.2.46`
  - `adguard.home.arpa -> 192.168.2.200`
  - `openwebui.home.arpa -> 192.168.2.201`
  - `jellyfin.home.arpa -> 192.168.2.202`
  - `immich.home.arpa -> 192.168.2.203`
  - `ollama.home.arpa -> 192.168.2.204`
  - `vllm.home.arpa -> 192.168.2.205`
  - `sonarr.home.arpa -> 192.168.2.206`
  - `radarr.home.arpa -> 192.168.2.207`
  - `prowlarr.home.arpa -> 192.168.2.208`
  - `qbittorrent.home.arpa -> 192.168.2.209`
  - `seerr.home.arpa -> 192.168.2.210`

2. Storage
- Author Talos `UserVolumeConfig` manifests for:
  - `local-path-provisioner`
  - `fast-ai`
  - `media-bulk`
- Validate mounts and PVC provisioning on the non-system disks.

3. GitOps
- Author the actual manifests in `homelab-gitops/`.
- Create `.sops.yaml`.
- Generate and back up `age.key`.
- Bootstrap Flux once the repo contains the required entrypoint manifests.

4. Applications
- Deploy AdGuard Home first.
- Deploy `Ollama` and `Open WebUI`.
- Then deploy `vLLM`.
- Then deploy `ComfyUI`.
- After that, deploy Immich and the media stack.

5. NUC expansion
- Keep the NUC off-cluster for day 1.
- Join it later as a worker or storage-adjacent node, not as a control plane node.

### Problems already overcome

| Issue | What happened | Outcome |
| --- | --- | --- |
| Wrong-disk risk | The target and USB were both 256 GB devices. | Resolved by identifying the internal SSD by real hardware identity, not by size alone. |
| Unsafe selector attempt | The first disk selector did not match and Talos refused the config. | Safe failure; nothing was written until the selector was corrected. |
| Windows booted after install | BIOS still preferred Windows. | Resolved by selecting the SSD boot entry directly. |
| Secure Boot blocked Talos | Talos on the SSD would not boot with Secure Boot on. | Resolved by disabling Secure Boot in BIOS. |
| DHCP drift | The node came up on `.49` instead of `.45`. | Cluster works, but router reservation still needs to be fixed. |
| No default CNI | The node stayed `NotReady` until Cilium came up. | Expected and resolved by installing Cilium promptly. |
| Slow NVIDIA image pull | The device plugin spent time pulling from `nvcr.io`. | Resolved automatically; the pod became healthy. |

### Problems to expect next

| Risk | Why it matters | Mitigation |
| --- | --- | --- |
| Tower IP keeps drifting | Docs and Talos endpoint operations become inconsistent. | Enforce the `.45` reservation and update boot-time networking if needed. |
| AdGuard cutover too early | LAN clients could lose local DNS during rollout. | Validate AdGuard first, then change the router DNS setting. |
| Storage manifest mistakes | A bad `UserVolumeConfig` target could affect the wrong disk. | Map every non-system disk by model, serial, and role before writing storage YAML. |
| GPU overcommit | Ollama, vLLM, and ComfyUI can fight for the same 24 GB VRAM. | Keep mode-switching explicit and default heavy GPU apps to scale `0`. |
| Secret loss | Future expansion and recovery depend on current Talos and SOPS material. | Back up `talosconfig`, generated configs, and later `age.key` securely. |

### Notes from the GPU validation

- The GPU test pod reached `Succeeded`.
- `nvidia-smi` reported:
  - Driver version: `570.211.01`
  - CUDA version: `12.8`
  - GPU: `NVIDIA GeForce RTX 3090`
- The log ended with `ERROR: init 250 result=11` after successful output. Treat that as a teardown artifact unless it starts affecting real workloads.
