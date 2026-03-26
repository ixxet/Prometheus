# Growing Pains

Last updated: 2026-03-25 (America/Toronto)

## Why this file exists

This repo is meant to show real platform work, not just the final polished
shape. The failures here matter because they explain why the current design
looks the way it does.

## Current lessons learned

### 1. `vLLM_PORT` was broken by Kubernetes service-link env injection

What happened:

- Kubernetes created legacy service environment variables for the `vllm`
  `Service`
- one of those variables was `VLLM_PORT=tcp://10.x.x.x:8000`
- `vLLM` also reads `VLLM_PORT`, but expects an integer port value

Effect:

- `vLLM` crashed immediately during startup

Fix:

- disabled Kubernetes service-link env injection for the `vllm` pod with
  `enableServiceLinks: false`

Lesson:

- old Kubernetes service env injection is still capable of colliding with
  application-specific environment variables
- modern DNS-based service discovery is safer and cleaner here

### 2. Single-GPU rollout behavior caused a deadlock

What happened:

- the old broken `vllm` pod still held the only GPU
- the new fixed `vllm` pod could not schedule because the node has one RTX 3090

Effect:

- rollout stalled even though the manifest fix itself was correct

Fix:

- changed the deployment strategy to `Recreate`
- explicitly recycled the deployment so the old pod terminated before the new
  one requested the GPU

Lesson:

- single-GPU workloads are not normal rolling-update workloads
- rollout strategy must match the hardware reality

### 3. `vLLM` readiness was lying

What happened:

- Kubernetes considered the pod ready as soon as the container process stayed up
- but `vLLM` was still downloading and loading model weights

Effect:

- the pod looked healthy before the API was actually serving

Fix:

- added a readiness probe against `/v1/models`

Lesson:

- for inference systems, process-alive is not the same thing as service-ready

### 4. Slow internet changed the failure mode from image pull to model load

What happened:

- container images eventually pulled successfully
- model weights from Hugging Face then became the real bottleneck
- the accelerated Hugging Face transfer path timed out repeatedly on the current
  WAN link

Effect:

- `vLLM` moved from image delay to repeated model-download failure

Fix:

- disabled accelerated transfer/Xet path
- accepted slower but simpler downloads
- added better runtime visibility in docs and runbooks

Lesson:

- image-pull success does not mean AI stack success
- model distribution strategy matters as much as container delivery

### 5. `vLLM` fit on the 3090, but the default context window did not

What happened:

- the Mistral 7B weights finished downloading into the cache PVC
- `vLLM` then loaded the model successfully on the RTX 3090
- startup still crashed because the default model max sequence length was
  `32768`, while the available KV cache on the current `gpu_memory_utilization`
  setting could only hold about `25248` tokens

Effect:

- the pod restart loop looked like a download problem at first glance
- the real failure was engine initialization after the model was already on disk

Fix:

- capped `vLLM` with `--max-model-len 24576`
- kept the more conservative GPU memory setting instead of pushing the card
  harder immediately

Lesson:

- model download completion and model startup are separate checkpoints
- VRAM budgeting has to account for both weights and KV cache, not just one or
  the other

### 6. Flux health and live-state recovery can drift briefly

What happened:

- repo fixes were committed correctly
- the cluster sometimes remained on an older applied revision while health checks
  and dependency state caught up

Effect:

- the repo and the runtime could disagree for a short time during recovery

Fix:

- reconciled the affected layer explicitly
- in one case, applied the exact repo-rendered `vllm` manifests directly to
  converge the live deployment with the committed state

Lesson:

- GitOps is the source of truth, but operational recovery still requires reading
  the live object state carefully

### 7. Talos storage discipline forced the right decision

What happened:

- the easy-looking non-system disks were already in use elsewhere
- the cluster could have claimed them, but that would have been destructive

Effect:

- storage planning had to pause

Fix:

- kept first-wave persistent state on the Talos SSD only
- moved to a directory-backed `UserVolumeConfig` for local-path

Lesson:

- "available to Linux" is not the same thing as "safe to take"

## Current open pain points

- `vLLM` still needs one more clean restart after the KV-cache sizing fix before
  it can be considered stable
- router DNS is not yet cut over to AdGuard
- remote access works now through MIMIR advertising `192.168.2.0/24` into
  Tailscale, but it is still a dependency outside the cluster itself
- the node is still on DHCP `.49`, not the planned reserved `.45`

## Why keep this visible

Because this is where the engineering judgment lives:

- what failed
- why it failed
- what assumption was wrong
- how the fix changed the design

That matters more than pretending the build was linear.

## Hurdles We've Cleared

These are the wins worth keeping visible because they show what the platform can
already do on modest, real-world home hardware.

- Installed Talos only to the intended `256 GB` SSD without touching the other
  in-use tower disks.
- Brought up a single-node Talos control plane on bare metal with Cilium,
  `LoadBalancer` IPs, and L2 announcements on a normal home LAN.
- Loaded NVIDIA support into Talos, exposed the RTX 3090 through the device
  plugin, and validated GPU scheduling on the live node.
- Kept first-wave persistent state on the Talos system SSD when every non-system
  disk had to remain off-limits.
- Recovered `vLLM` from multiple real startup issues: service-link env
  collisions, single-GPU rollout deadlock, slow-link model distribution, and
  KV-cache sizing on a 24 GB consumer GPU.
- Got `Open WebUI`, `vLLM`, and Postgres running together on the same cluster
  with the model served locally as an OpenAI-compatible API.
- Established remote operations safely through Tailscale by using MIMIR as a
  subnet router instead of modifying the Talos node itself.
