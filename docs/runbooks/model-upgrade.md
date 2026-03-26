# Model Upgrade Runbook

Last updated: 2026-03-26 (America/Toronto)

## Purpose

This runbook exists so model changes are treated as platform changes, not casual
UI tweaks.

## Current model

- `mistralai/Mistral-7B-Instruct-v0.3`

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
