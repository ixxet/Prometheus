# Gemma 4 Migration Handoff

Last updated: 2026-04-10 (America/Toronto)

## Purpose

This document is the clean handoff for the Gemma 4 work on Prometheus.

It answers:

- what model we tried to introduce
- what actually failed
- what we preserved
- what is staged now
- what the current blockers are
- what the next viable paths are

Important correction:

- `vLLM` is **not** generally broken on this cluster
- the stable `vLLM` path is still healthy and serves Mistral
- the specific failed path was:
  - **Gemma 4 `GGUF` served by `vLLM`**

## Executive Summary

| Item | Status | Notes |
|---|---|---|
| Stable backend | Healthy | `vLLM` still serves `mistralai/Mistral-7B-Instruct-v0.3` |
| Gemma 4 in `vLLM` via `GGUF` | Failed | `vLLM` rejected `gemma4` GGUF architecture at runtime |
| Gemma 4 artifacts on disk | Preserved | `Q6_K` GGUF is staged on a dedicated cache PV |
| Gemma 4 alternate backend | Staged | switchable `llama-server` deployment exists at `replicas: 0` |
| WebUI / summarizer / LangGraph | Unchanged | still point at the stable `vLLM` Mistral backend |
| Native Gemma tool-calling on this exact 26B GGUF path | Not available | `llama.cpp` path is for testing, not a clean native `vLLM` Gemma parser path |

## Target Model

| Field | Value |
|---|---|
| Family | Gemma 4 |
| Variant | `26B-A4B-it` |
| Packaging used in the failed `vLLM` attempt | `GGUF` |
| Source repo used for public quantized weights | `bartowski/google_gemma-4-26B-A4B-it-GGUF` |
| File staged | `google_gemma-4-26B-A4B-it-Q6_K.gguf` |
| Tokenizer intended for the original `vLLM` attempt | `google/gemma-4-26B-A4B-it` |
| Target hardware | single `RTX 3090 24 GB` |

## Why We Wanted Gemma 4

| Goal | Reason |
|---|---|
| newer model family | Mistral 7B was treated as a bring-up model, not a long-term preferred model |
| stronger reasoning | Gemma 4 looked like a better fit for future agent and app work |
| better local proof-of-concept story | user wanted a more modern flagship local model than Mistral 7B |

## Original `vLLM` Attempt

The original requested staging contract for the `vLLM` Gemma path was:

| Requested setting | Value |
|---|---|
| model source | `bartowski/google_gemma-4-26B-A4B-it-GGUF` |
| model file | `google_gemma-4-26B-A4B-it-Q6_K.gguf` |
| tokenizer | `google/gemma-4-26B-A4B-it` |
| max context | `16384` |
| KV cache type | `fp8` |
| MoE backend | `marlin` |
| execution mode | `--enforce-eager` |
| GPU memory target | `0.95` |
| tensor parallel | `1` |
| tool calling | `--enable-auto-tool-choice` |
| tool parser | `gemma4` |
| reasoning parser | `gemma4` |

## What We Changed To Try To Make `vLLM` Work

| Change | Why it was done | Outcome |
|---|---|---|
| switched to a public mirror | avoided gated model downloads and token issues | worked |
| used `vllm/vllm-openai:gemma4` runtime | aligned with Gemma 4-specific upstream runtime | runtime pulled |
| added custom `services/vllm-gemma4/` image path | kept `transformers` pinned on the Gemma 4-compatible line | built successfully |
| pinned `transformers==5.5.0` | avoided `transformers` drift/downgrade during runtime setup | worked |
| pre-pulled the Gemma runtime image | reduced cutover delay | worked |
| staged the large GGUF on disk first | avoided full model pull during live switch | worked |
| added cache validation logic | prevented serving from half-downloaded model files | worked |

## What Failed

| Failure point | What happened |
|---|---|
| runtime load inside `vLLM` | `vLLM` started, but the model did not load |
| exact error | `ValueError: GGUF model with architecture gemma4 is not supported yet.` |
| implication | the model was present on disk, but the serving engine still could not use it |

Blunt version:

- the **download succeeded**
- the **image pull succeeded**
- the **`vLLM` engine still rejected the model format**

So the blocker was **format support**, not:

- bad networking
- bad PVCs
- missing image
- missing tokenizer
- broken cluster

## What We Did To Recover Safely

| Recovery action | Reason |
|---|---|
| rolled the live backend back to Mistral | restored the known-good stable path fast |
| re-verified `vllm`, Open WebUI, LangGraph, summarizer | made sure the platform was healthy again |
| kept Gemma work in Git | preserved the migration work instead of losing it |
| staged a separate `llama-server` path | gave Gemma 4 a test path that does support GGUF |
| separated Gemma cache from `vllm` cache | avoided repeated waste and reduced cleanup risk |

## Current Live State

| Component | Current state |
|---|---|
| `vLLM` | active |
| active model | `mistralai/Mistral-7B-Instruct-v0.3` |
| `llama-gemma4` deployment | staged at `0/0` |
| `llama-gemma4` service | exists |
| `llama-gemma4` cache PVC | `Bound` |
| Gemma `Q6_K` GGUF | staged on dedicated PV |
| `llama.cpp` server image | pulled and cached |

Live service references:

| Service | Value |
|---|---|
| stable `vLLM` endpoint | `http://192.168.2.205:8000/v1/models` |
| staged Gemma service | `http://llama-gemma4.ai.svc.cluster.local:8000` |

## Current Blockers

| Blocker | Why it matters |
|---|---|
| `vLLM` does not support `gemma4` `GGUF` on this path | blocks the exact originally requested serving path |
| one GPU only | prevents honest always-on parallel `vLLM + llama-server` GPU serving |
| `llama.cpp` is not a clean native Gemma parser replacement for `vLLM` | means tool-calling behavior is not the same as true `vLLM` Gemma parser support |
| current apps depend on stable `vLLM` | WebUI, summarizer, and LangGraph should not be repointed casually before deliberate testing |

## What We Circumvented Successfully

| Problem | Circumvention | Status |
|---|---|---|
| gated model repos | used a public mirror | solved |
| image pull delay | pre-pulled images | solved |
| `transformers` drift | custom pinned runtime | solved |
| incomplete model downloads | resumable staging and size validation | solved |
| losing staged model artifacts on slow WAN | dedicated cache PV + documented retention rule | solved |

## What We Did **Not** Solve

| Problem | Why still unsolved |
|---|---|
| native Gemma 4 `GGUF` support in `vLLM` | upstream support gap |
| clean always-on dual-backend GPU serving | single `RTX 3090` constraint |
| native Gemma tool-calling on the staged `llama.cpp` `26B` GGUF path | not the same feature surface as `vLLM` Gemma parser support |

## Why `llama-server` Exists Now

| Item | Meaning |
|---|---|
| `llama-gemma4` deployment | switchable Gemma 4 test backend |
| `replicas: 0` | kept inactive so it does not fight the stable `vLLM` backend for the only GPU |
| usage model | scale `vLLM` down, scale `llama-gemma4` up, test Gemma directly, then switch back |

This path is honest for one GPU.

It is **not** an always-on replacement yet.

## Native Gemma Tool-Calling: Current Position

| Question | Current answer |
|---|---|
| Clean native Gemma tool-calling on Prometheus | best fit is still `vLLM` with an officially supported Gemma 4 path |
| Clean native path for the exact `26B-A4B-it GGUF` request | no |
| Testable Gemma 4 path right now | yes, via staged `llama-server` backend |

Practical meaning:

- `llama.cpp` is currently the **test path**
- `vLLM` remains the **stable path**
- a future native Gemma switch depends on either:
  - upstream `vLLM` support for this exact GGUF architecture, or
  - using a different officially supported Gemma 4 path that fits the 3090

## Recommended Next Paths

| Path | Description | Risk |
|---|---|---|
| A. keep Mistral stable and pause | safest for demos and platform stability | low |
| B. test staged Gemma 4 with `llama-server` | good for controlled direct evaluation | medium |
| C. later move to a clean native Gemma `vLLM` path | best long-term architecture if hardware/model fit is real | medium to high depending on model choice |

## Resume Commands

For the switchable `llama-server` test path, use:

- [llama-server-gemma4.md](/Users/zizo/Personal-Projects/Computers/Prometheus/docs/runbooks/llama-server-gemma4.md)

For the stable model workflow and rollback discipline, use:

- [model-upgrade.md](/Users/zizo/Personal-Projects/Computers/Prometheus/docs/runbooks/model-upgrade.md)

## Bottom Line

1. `vLLM` on Prometheus is healthy.
2. The failed path was specifically **Gemma 4 `GGUF` inside `vLLM`**.
3. We preserved the Gemma work instead of discarding it:
   - pinned runtime work
   - staged cache
   - switchable `llama-server` backend
4. The cluster is still on the stable Mistral path until a safer Gemma cutover
   is justified.
