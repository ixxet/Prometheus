# Model Upgrade Runbook

Last updated: 2026-04-06 (America/Toronto)

## Purpose

This runbook exists so model changes are treated as platform changes, not casual
UI tweaks.

## Current model

- `mistralai/Mistral-7B-Instruct-v0.3`

## Gemma 4 staging notes

- The current upstream Gemma 4 recipe expects the dedicated
  `vllm/vllm-openai:gemma4` runtime image and `transformers==5.5.0`.
- The repo now includes a custom `services/vllm-gemma4/` image path so that
  `transformers` stays pinned on the Gemma 4-compatible line.
- `vLLM` documents `GGUF` as experimental and potentially incompatible with
  other features. Treat a `GGUF` Gemma rollout as a higher-risk change than a
  normal model swap.
- If the target GGUF repo is private or gated, the `ai` namespace also needs a
  real `hf-token` secret before rollout.
- The attempted `bartowski/google_gemma-4-26B-A4B-it-GGUF` `Q6_K` rollout did
  finish staging on disk, but the live server still failed with
  `ValueError: GGUF model with architecture gemma4 is not supported yet.`
- Do not delete the known-good model cache until the replacement model is
  serving and verified through `vLLM`, Open WebUI, LangGraph, and the
  summarizer.
- The current fallback for Gemma 4 GGUF is a switchable `llama-server` test
  backend, not a second always-on GPU backend. On this one-node, one-GPU
  cluster, the test path has to scale `vLLM` down first.
- Staged model artifacts should also be treated as deliberate work, not
  disposable scratch space. If a large test model took hours to fetch, keep it
  unless space pressure or an explicit operator decision says otherwise.

## Why model upgrades need discipline

- model size affects disk cache usage
- context length affects KV-cache pressure on the RTX 3090
- startup time on a slow WAN link can dwarf the container image pull
- Open WebUI usefulness can change dramatically even when the platform stays healthy

## Upgrade checklist

1. Confirm there is enough SSD headroom for the new cache footprint.
2. Confirm the model is realistic for a 24 GB RTX 3090.
3. Decide whether `--max-model-len` must change before rollout.
4. Update the `vLLM` manifest and document the reason in the README.
5. Watch:
   - image pull
   - model download
   - engine initialization
   - `/v1/models`
6. Verify Open WebUI against the new backend.
7. Update `docs/growing-pains.md` if the change exposed a new failure mode.

## Rollback

1. Revert the model change in Git.
2. Reconcile the `apps` layer.
3. Confirm `/v1/models` serves the previous known-good model again.
