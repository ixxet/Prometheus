# Llama-Server Gemma 4 Test Backend

Last updated: 2026-04-06 (America/Toronto)

## Purpose

This runbook stages a `llama-server` Gemma 4 backend beside the stable `vLLM`
path without pretending both GPU backends can run at the same time on one RTX
3090.

## Why this backend exists

- `vLLM` is still the stable production backend in this repo
- the attempted Gemma 4 GGUF path in `vLLM` failed because `gemma4` GGUF is not
  supported there yet
- `llama.cpp` does officially support Gemma 4 GGUF and exposes an
  OpenAI-compatible `llama-server`

The staged backend uses the official Hugging Face `llama.cpp` example model:

- `ggml-org/gemma-4-26b-a4b-it-GGUF:Q4_K_M`

## Important constraint

This deployment is intentionally kept at `replicas: 0`.

Reason:

- the cluster has one RTX 3090
- Kubernetes allocates GPUs as whole devices
- `vLLM` and `llama-server` cannot honestly run in parallel on this node
  without uncontrolled contention

So this backend is switchable, not concurrent.

## Staged service

- Deployment: `ai/llama-gemma4`
- Service: `http://llama-gemma4.ai.svc.cluster.local:8000`
- Runtime image:
  - `ghcr.io/ggml-org/llama.cpp:server-cuda@sha256:ea34541236b965382cf3a80736ade74afb97fcd8c1950b68fcf9c9c3f17aaf49`

## Switch from `vLLM` to `llama-server` temporarily

For a one-off experiment, suspend the `apps` Kustomization first so Flux does
not immediately revert the manual scale changes:

```bash
flux --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig \
  -n flux-system suspend kustomization apps
```

Scale down `vLLM` and scale up `llama-server`:

```bash
kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig \
  -n ai scale deployment/vllm --replicas=0

kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig \
  -n ai scale deployment/llama-gemma4 --replicas=1
```

Watch the rollout:

```bash
kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig \
  -n ai rollout status deployment/llama-gemma4 --timeout=30m
```

## Verification

Port-forward the service and verify the OpenAI-compatible endpoint:

```bash
kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig \
  -n ai port-forward svc/llama-gemma4 18086:8000
```

Then from another terminal:

```bash
curl http://127.0.0.1:18086/v1/models
```

The first activation will take the longest because the GGUF needs to download
into the dedicated static cache PV at
`/var/mnt/local-path-provisioner/llama-gemma4-cache` on the Talos node.

## Return to the stable backend

Scale `llama-server` back down and `vLLM` back up:

```bash
kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig \
  -n ai scale deployment/llama-gemma4 --replicas=0

kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig \
  -n ai scale deployment/vllm --replicas=1
```

Resume GitOps:

```bash
flux --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig \
  -n flux-system resume kustomization apps
```

Re-verify the stable path:

```bash
curl http://192.168.2.205:8000/v1/models
curl http://192.168.2.203/api/health
```
