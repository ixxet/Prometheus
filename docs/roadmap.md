# Prometheus Roadmap From `v0.3.0` To `v1.0.0`

Last updated: 2026-03-31 (America/Toronto)

## Why this document exists

The README should stay readable. This file is the full sequencing document for
the rest of the project: what is locked, what is next, what stays deferred, and
what "done" means for each milestone.

## Locked decisions

- AI platform first, not media first and not template first
- Tower-only longer for storage planning; do not assume NAS or Unraid before the
  next milestones
- MIMIR stays Debian first, then may become a Talos worker later, then HA
  control-plane work deliberately later
- Agent stack is `self-hosted OSS LangGraph + Postgres + self-hosted Mem0 + external Obsidian vault sink`
- `Open WebUI` remains a human chat UI; it is not the orchestrator
- `vLLM` remains the only model backend for the first agent platform
- `Ollama`, `LiteLLM`, `Graphiti/Zep`, and `Letta` stay out of the active path
- Public template extraction waits until the live instance proves itself

## Release map

| Version | Theme | What must be true |
| --- | --- | --- |
| `v0.2.1` | Stable AI serving checkpoint | `vLLM`, Open WebUI, Postgres, AdGuard, Flux, and Tailscale remote ops are working together |
| `v0.3.0` | First agent runtime | LangGraph is live with Postgres-backed execution state, approval/resume, and restart-tested persistence |
| `v0.4.0` | Memory and archive layer | Mem0 plus Obsidian summary/export workflow are live |
| `v0.5.0` | Naming and first real workflow | The first real workflow exists, but AdGuard cutover and stable LAN naming are still environment-gated |
| `v0.6.0` | Observability slice | Prometheus, Grafana, metrics-server, DCGM exporter, provisioned dashboards, and the MIMIR return-check timer are live |
| `v0.7.0` | Proof-of-concept apps | The summarizer app is deployed, monitored, pinned to GHCR by commit-derived tag, and externally testable without exposing raw `vLLM` |
| `v0.8.x+` | Platform expansion | Storage maturity, media/photos, and NUC split still happen deliberately |
| `v0.9.x+` | Stable naming | Router-side DNS handoff resumes once the tower returns to its permanent LAN |
| `v1.0.0` | Complete platform | The system feels complete, operable, and no longer reads like bring-up notes |

## `v0.2.x` Stabilization And Naming

Goal: finish the platform layer so the current checkpoint is operationally clean
before the agent runtime lands.

### Deliverables

- complete AdGuard configuration and keep the operator path documented
- create AdGuard rewrites for:
  - `k8s.home.arpa -> 192.168.2.46`
  - `adguard.home.arpa -> 192.168.2.200`
  - `openwebui.home.arpa -> 192.168.2.201`
  - `vllm.home.arpa -> 192.168.2.205`
- verify Open WebUI from the actual UI path after the `vLLM` recovery, not only
  from raw `curl` tests
- keep remote ops through MIMIR as the supported Tailscale path; do not add
  Talos-side Tailscale yet
- update repo docs anywhere they still imply `vLLM` is blocked or `apps` is red
- reserve `192.168.2.45` on the router and move the tower back from DHCP `.49`
  when there is a safe window

### Acceptance

- [x] `http://openwebui.home.arpa` works from a real LAN client after rewrites are active
- [x] `http://vllm.home.arpa:8000/v1/models` resolves and answers from a real LAN client
- [x] `talosctl` and `kubectl` still work remotely over Tailscale after any IP cleanup path
- [x] Open WebUI is reachable from the actual UI path, not only via raw API checks
- [x] AdGuard remains on `192.168.2.200`
- [x] the first-wave AdGuard rewrites are configured and answer direct queries to `192.168.2.200`
- [x] MIMIR can be pointed directly at AdGuard and resolve the first-wave `home.arpa` names as a real client
- [x] router DNS cutover remains deferred until the tower returns to its permanent LAN

## `v0.3.0` First Agent Runtime

Goal: move from "local model serving" to "actual orchestrated execution state."

Status: complete on 2026-03-26.

### Implementation

- replace the LangGraph placeholder with a real self-hosted OSS runtime
- keep LangGraph internal-only at first:
  - `ClusterIP` service only
  - no public `LoadBalancer`
  - access through port-forward or internal clients during first rollout
- remove assumptions that require paid or hosted features:
  - no LangSmith dependency
  - no LangGraph cloud license requirement
  - no Redis requirement unless a real OSS need appears during implementation
- use Postgres as the only required durable store for `v0.3.0`
- build a small LangGraph service rather than a generic framework dump:
  - `GET /healthz`
  - `POST /threads`
  - `POST /threads/{thread_id}/runs`
  - `POST /threads/{thread_id}/resume`
  - `GET /threads/{thread_id}`
- keep the first workflow narrow and safe:
  - multi-turn runs
  - checkpointed execution
  - human-in-the-loop resume
  - read-only retrieval only if it becomes necessary
  - no arbitrary cluster mutation tools in the first version
- keep Open WebUI pointed directly at `vLLM`; do not force Open WebUI to become
  the LangGraph client yet

### Repo changes

- turn `homelab-gitops/apps/agents/langgraph/` into a runnable service
- replace placeholder runtime secrets with only the secrets actually needed
- update docs so LangGraph no longer implies LangSmith, Redis, or hosted
  LangGraph requirements

### Acceptance

- [x] LangGraph pod is `1/1 Running`
- [x] Postgres-backed thread/run/checkpoint state survives pod restart
- [x] one thread can start, pause, resume, and complete successfully
- [x] no additional durable state store beyond Postgres is required

## `v0.4.0` Memory And Archive Layer

Goal: add long-term memory and human-readable outputs without turning the stack
into overlapping memory products.

Status: complete on 2026-03-26. Mem0 is live in-cluster through LangGraph with
`Qdrant + TEI` backing, cross-thread write/recall has been validated, and the
external Markdown archive sink is now writing into the off-tower MIMIR vault
path used by Obsidian.

### Implementation

- add self-hosted Mem0 as the only semantic-memory system
- keep LangMem documented only as an alternative; do not deploy both
- keep Obsidian outside the cluster
- define the Obsidian path as an external vault sink for Markdown summaries and
  ADR exports on MIMIR
- extend LangGraph with:
  - semantic memory read/write through Mem0
  - summary export to the external vault sink
- keep memory boundaries explicit:
  - execution memory = LangGraph + Postgres
  - semantic memory = Mem0
  - archive = external Obsidian vault

### Acceptance

- [x] a run can write at least one durable semantic-memory record into Mem0
- [x] a run can export a Markdown summary or ADR artifact to the chosen external sink
- [x] the same user preference can be retrieved in a later thread
- [x] no duplicate semantic-memory system is live

## `v0.5.0` DNS Cutover And First Real Workflow

Goal: make the platform pleasant and stable for daily use, not just technically
functional.

Status: in progress on 2026-03-26. The first real workflow has been defined and
rehearsed against the live stack; router DNS cutover and default client naming
are still pending.

### Implementation

- perform a router-side DHCP/DNS handoff to AdGuard after rewrites are validated
- prefer a staged rollout:
  - one manually pointed client first
  - then a secondary router or isolated segment if available
  - main router handoff last
- standardize the first stable service names:
  - `k8s.home.arpa`
  - `adguard.home.arpa`
  - `openwebui.home.arpa`
  - `vllm.home.arpa`
- define the first real agent workflow:
  - chosen workflow: `approval-gated operator brief`
  - request comes in
  - LangGraph runs against `vLLM`
  - Postgres persists execution state
  - Mem0 updates durable facts when appropriate
  - Markdown summary or ADR exports to the external Obsidian sink
- keep the workflow read-mostly and human-supervised
- rehearse and harden the operator runbooks so they become credible in practice:
  - DNS cutover
  - DNS break-glass fallback
  - disaster recovery
  - add-worker / future NUC conversion
  - release/tagging process
  - model upgrade/change process

### Acceptance

- [ ] at least one LAN client and one Tailscale-remote client resolve
  `*.home.arpa` correctly
- [ ] Open WebUI and direct API usage work by name, not just IP
- [x] the first real agent workflow completes end to end and emits both
  execution state and a human-readable export
- [ ] operator runbooks are credible enough that another engineer could repeat
  the cutover and validation

## `v0.7.0` Proof-Of-Concept App Integration

Goal: prove that the private platform can host a real app without blurring the boundary between app ownership and infrastructure ownership.

Status: in progress on 2026-03-31. The summarizer app is live in its own namespace, pinned to a commit-derived GHCR image, monitored in Prometheus, and reachable through a temporary auth-gated Cloudflare quick tunnel.

### Implementation

- keep the summarizer app code and image lifecycle in its own repository
- deploy the app from Prometheus by immutable image reference only
- point the app at `http://vllm.ai.svc.cluster.local:8000/v1`
- keep raw `vllm` private
- monitor the app through Prometheus and Grafana
- expose only the summarizer app through a temporary auth proxy plus quick tunnel

### Acceptance

- [x] the summarizer app runs in its own `summarizer` namespace
- [x] the deployed image is pinned to a commit-derived GHCR tag
- [x] the app can reach private `vllm` internally
- [x] the app exposes `/metrics` and is scraped by Prometheus
- [x] the reviewer-facing path goes through an auth proxy and quick tunnel, not raw `vllm`

## `v0.6.0+` Platform Expansion

Goal: expand from "AI-capable single-node platform" into a broader homelab
platform without losing clarity.

Status: in progress on 2026-03-27. The observability slice is now live in-cluster
with Prometheus, Grafana, metrics-server, DCGM exporter, Git-provisioned
dashboards, the Flux/Cilium/Postgres/`vLLM` scrape surfaces, and the
MIMIR-hosted post-return timer. This first observability pass is now complete
even though the `v0.5.0` DNS cutover work remains deferred by the tower's
temporary LAN placement.

### Implementation order

1. Observability first
   - `kube-prometheus-stack`
   - Grafana dashboards
   - node, Cilium, Flux, Postgres, and GPU visibility
   - expected dashboard gaps are acceptable while the tower still boots Windows
     sometimes; continuity is not the current success criterion
2. Storage maturity second
   - keep the tower-only stance until hardware changes
   - when storage pressure forces it, add a second SSD for fast AI/app data
   - only then plan larger model tiers, ComfyUI assets, or heavier stateful apps
3. Media and photos after storage
   - media stack manifests
   - Immich manifests
   - avoid pretending bulk media fits cleanly on the current SSD-only path
4. Deeper observability later
   - Loki log aggregation
   - Tempo tracing when request paths justify it
5. NUC role split
   - keep MIMIR useful as Debian app tier and utility node first
   - later decide whether to move it into the cluster as a Talos worker
   - only after that revisit deliberate HA control-plane work
6. Public-template extraction after `v0.5.0`
   - keep `Prometheus` as the real instance repo
   - extract a second sanitized public repo from the proven GitOps structure
   - remove personal IPs, hostnames, and machine-specific assumptions there
   - keep Jinja and Ansible out of the live platform path unless they become
     useful for template generation or peripheral bootstrap

### Acceptance

- [x] dashboards cover node, GPU, Flux, and app health
- [x] `kubectl top` works through metrics-server
- [x] expected downtime from Windows sessions is visible but does not corrupt the
  observability stack
- [x] MIMIR has the committed post-return timer assets installed, enabled, and tested once
- [ ] storage pressure is no longer concentrated only on the Talos system SSD before
  heavy apps land
- [ ] media stays deliberate, and Immich remains on MIMIR unless a real GPU or storage reason justifies migration
- [ ] NUC integration is deliberate, not opportunistic
- [ ] public template extraction starts only after the live instance has a proven story

## `v1.0.0` Completion Criteria

Prometheus reaches `v1.0.0` when all of the following are true:

- core platform services are stable by name, not just by IP
- agent runtime, semantic memory, and archive flow are all live
- observability is in place
- recovery and operator runbooks exist and are credible
- storage and app placement are no longer obviously temporary
- the repo reads as a complete environment, not a bring-up journal
- the public reusable template path is defined and no longer competes with the
  private instance repo for identity
