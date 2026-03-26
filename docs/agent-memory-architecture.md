# Agent And Memory Architecture

Last updated: 2026-03-26 (America/Toronto)

## Why this document exists

The repo originally leaned toward a broader local AI stack with `Ollama`,
`Open WebUI`, `vLLM`, and later `ComfyUI`. That was useful for exploration,
but it was too wide for the first serious platform iteration on a single RTX
3090.

The current direction is narrower and easier to operate:

- one orchestrator
- one serving backend
- one semantic memory system
- one archive sink
- clean interfaces between each layer

## Current pivot

The current preferred stack is:

- `vLLM` as the only model-serving backend
- `LangGraph` as the self-hosted OSS orchestrator
- `Postgres` as the durable execution store
- `Obsidian` as the external human-readable archive sink
- `Mem0` as the likely semantic memory layer

The following are explicitly not part of the first activation wave:

- `Ollama`
- `LiteLLM`
- `Graphiti / Zep`
- `Letta`

## Where the project paused before this pivot

Before the architecture pivot, the project stopped at the storage safety gate.

What was already real:

- Talos installed on the dedicated `256 GB` SSD
- Kubernetes control plane healthy
- Cilium, L2 announcements, and `LoadBalancer` IPAM live
- NVIDIA runtime and device plugin live
- GPU scheduling validated on the RTX 3090

What had been authored but not activated:

- Flux entrypoints
- staged GitOps manifests for Cilium, network, NVIDIA, storage, DNS, and AI

What blocked the next step:

- the current non-system SSD and NVMe targets are in use elsewhere
- no safe local app-storage disk is available yet
- no Talos `UserVolumeConfig` was applied

What remains true right now:

- the Talos system SSD still has significant headroom for early app/runtime use
- the cluster can proceed with small-footprint services before dedicated app
  storage is solved

## AI stack

Standalone Mermaid source:
[`docs/diagrams/ai-stack.mmd`](diagrams/ai-stack.mmd)

```mermaid
flowchart LR
  ui["Open WebUI\nhuman chat interface"] --> vllm["vLLM\nOpenAI-compatible inference API"]
  langgraph["LangGraph\norchestration runtime"] --> vllm
  langgraph --> pg["Postgres\nthreads, runs, checkpoints"]
  langgraph -. later semantic layer .-> mem0["Mem0\npreferences and durable facts"]
  langgraph -. curated export .-> obs["Obsidian Vault\nsummaries, ADRs, logs"]
```

## Request and data flow

Standalone Mermaid source:
[`docs/diagrams/request-data-flow.mmd`](diagrams/request-data-flow.mmd)

```mermaid
flowchart LR
  user["User request"] --> ui["Open WebUI or future agent client"]
  ui --> langgraph["LangGraph run"]
  langgraph --> checkpoint["Execution memory\nPostgres checkpoints"]
  langgraph --> vllm["vLLM inference call"]
  langgraph -. optional later .-> semantic["Semantic memory\nMem0 or LangMem"]
  langgraph -. summary export .-> archive["Obsidian markdown archive"]
  vllm --> reply["Model output"]
  checkpoint --> reply
  reply --> user
```

## Live pod and service interaction

Standalone Mermaid source:
[`docs/diagrams/pod-interactions.mmd`](diagrams/pod-interactions.mmd)

```mermaid
flowchart LR
  client["LAN client or browser"] --> owui_svc["Open WebUI Service
192.168.2.201"]
  owui_svc --> owui_pod["open-webui pod"]
  owui_pod --> vllm_svc["vLLM Service
192.168.2.205"]
  vllm_svc --> vllm_pod["vLLM pod"]
  vllm_pod --> hf["Hugging Face model download"]
  vllm_pod --> gpu["RTX 3090"]
  langgraph["LangGraph pod
later"] --> pg["Postgres service"]
  langgraph --> vllm_svc
  langgraph -. later semantic layer .-> mem0["Mem0
later"]
  langgraph -. later archive export .-> obs["Obsidian
later"]
```

Right now, `Open WebUI`, `vLLM`, and Postgres are all live. The next AI milestone
is not another model server. It is a real self-hosted `LangGraph` runtime that
uses Postgres for durable execution state without dragging in Redis, LangSmith,
or hosted LangGraph licensing for the first usable version.

## The three memory layers

### 1. Execution memory

Purpose:

- current thread state
- retries
- human-in-the-loop resume
- checkpoint history

This belongs to:

- `LangGraph` persistence
- backed by `Postgres`

This is the authoritative machine state for workflow execution.

### 2. Semantic memory

Purpose:

- user preferences
- durable facts
- project conventions
- stable policies

This belongs to:

- `Mem0` or `LangMem`

This is not about replaying every message. It is about extracting the durable
facts that should survive across sessions.

### 3. Human-readable archive

Purpose:

- summaries
- ADRs
- project logs
- curated knowledge

This belongs to:

- `Obsidian`

Obsidian is for humans first. It should hold readable artifacts the agent can
reference later, but it should not be the primary machine memory store.

## High-level memory ERD

Standalone Mermaid source:
[`docs/diagrams/high-level-memory-erd.mmd`](diagrams/high-level-memory-erd.mmd)

This is intentionally high-level. It shows the bounded concepts without locking
in a production schema too early.

```mermaid
erDiagram
  THREAD ||--o{ RUN : contains
  RUN ||--o{ CHECKPOINT : emits
  THREAD ||--o{ SEMANTIC_MEMORY : informs
  THREAD ||--o{ SUMMARY_RECORD : produces
  RUN }o--o{ SEMANTIC_MEMORY : extracts_or_updates
  SUMMARY_RECORD }o--|| THREAD : summarizes

  THREAD {
    string thread_id
    string owner
    string status
  }
  RUN {
    string run_id
    string thread_id
    string orchestrator
    datetime started_at
  }
  CHECKPOINT {
    string checkpoint_id
    string run_id
    string state_hash
    datetime persisted_at
  }
  SEMANTIC_MEMORY {
    string memory_id
    string subject
    string memory_type
    datetime updated_at
  }
  SUMMARY_RECORD {
    string summary_id
    string thread_id
    string sink
    datetime exported_at
  }
```

## Mem0 vs LangMem

### Recommendation

If the project stays centered on `LangGraph`, either choice is defensible.
Right now, `Mem0` is the more likely pick for this repo because it is a clearer
standalone semantic-memory layer.

### Mem0

Strengths:

- purpose-built for extracting and updating durable memories
- good fit for preferences, project rules, and stable user facts
- cleaner if semantic memory should stay somewhat decoupled from the LangGraph runtime

Tradeoffs:

- another service and integration surface
- less native to the LangGraph ecosystem than LangMem

Use Mem0 if:

- you want one dedicated semantic-memory system
- you expect that memory layer to survive even if the agent runtime evolves

### LangMem

Strengths:

- native fit with LangGraph / LangChain conventions
- coherent if the whole stack stays in one ecosystem
- lower conceptual impedance if LangGraph remains the long-term orchestrator

Tradeoffs:

- more coupled to the LangGraph/LangChain stack
- less attractive if semantic memory should remain reusable outside that ecosystem

Use LangMem if:

- you are committed to LangGraph as the long-term agent runtime
- you value native integration over independence

### Practical decision

For this repo:

- `Mem0` is the likely first choice
- `LangMem` remains the main alternative, not a second layer to run alongside it

Do not run both first. Pick one semantic memory system.

## What temporal relationship memory means

Temporal relationship memory is not just "remembering facts." It is remembering
how relationships change over time.

Example:

- January: "The NUC is an external Debian box."
- March: "The NUC is still external, but planned as a future app host."
- Later: "The NUC joined the cluster as a worker."

A temporal graph memory system can answer questions like:

- what did the homelab topology look like in January?
- when did the NUC stop being external-only?
- which storage strategy was in effect before Unraid existed?

That is different from ordinary semantic memory, which would just try to store
the latest stable facts.

This is why `Graphiti` / `Zep` is interesting. It is designed for changing
relationships, historical context, and point-in-time queries. It is also a more
complex system than this repo needs right now.

## Explicit not-now decisions

### LiteLLM

Not now.

Reason:

- `vLLM` already exposes an OpenAI-compatible API
- there is only one serving backend today
- there is no immediate cloud fallback requirement

Add LiteLLM later if:

- there are multiple serving backends
- a stable gateway becomes useful
- cloud fallback is introduced

### Graphiti / Zep

Not now.

Reason:

- temporal relationship memory is interesting but not yet required
- it would add another stateful subsystem before the core platform is stable

Add later if:

- historical topology or policy queries become a real need
- semantic memory alone stops being enough

### Letta

Not now.

Reason:

- `LangGraph` is the chosen orchestrator
- Letta is closer to an alternative agent platform than a small add-on

## Revised rollout order

1. Apply the temporary SSD-backed Talos directory volume for `local-path-provisioner`.
2. Activate `AdGuard Home`.
3. Deploy `vLLM` as the first backend.
4. Keep `Open WebUI`, but point it directly at `vLLM`.
5. Deploy `Postgres`.
6. Deploy `LangGraph`.
7. Add Obsidian summary/export workflow.
8. Add `Mem0` as the semantic memory layer.
9. Revisit `LiteLLM`, `Graphiti`, or `Letta` only if the single-backend,
   single-memory approach stops being sufficient.
