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

The staged backend now expects the original manually chosen GGUF artifact:

- source repo: `bartowski/google_gemma-4-26B-A4B-it-GGUF`
- file: `google_gemma-4-26B-A4B-it-Q6_K.gguf`
- expected size: `22862570624` bytes

That restores the exact artifact that was deleted after the failed `vLLM`
experiment.

## Preserved staging contract

The original Gemma 4 staging contract is still preserved here:

- model source: `bartowski/google_gemma-4-26B-A4B-it-GGUF`
- file: `google_gemma-4-26B-A4B-it-Q6_K.gguf`
- tokenizer: `google/gemma-4-26B-A4B-it`
- target context: `16384`

The following flags were part of the earlier `vLLM`-specific attempt and remain
documented for that reason, but `llama-server` does not use these exact parser
or cache flags:

- `--kv-cache-dtype fp8`
- `--moe-backend marlin`
- `--enforce-eager`
- `--gpu-memory-utilization 0.95`
- `--tensor-parallel-size 1`
- `--enable-auto-tool-choice`
- `--tool-call-parser gemma4`
- `--reasoning-parser gemma4`

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

## Pre-stage the GGUF onto disk

Use a one-off downloader pod mounted to `llama-gemma4-cache`:

```bash
kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig \
  -n ai apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: llama-gemma4-cache-download
  namespace: ai
spec:
  restartPolicy: Never
  containers:
    - name: downloader
      image: busybox:1.36
      command:
        - sh
        - -ec
        - |
          set -eu
          mkdir -p /cache/gguf
          target=/cache/gguf/google_gemma-4-26B-A4B-it-Q6_K.gguf
          expected_size=22862570624
          current_size="$(stat -c '%s' "${target}" 2>/dev/null || echo 0)"
          if [ "${current_size}" != "${expected_size}" ] || [ -e "${target}.aria2" ]; then
            rm -f "${target}" "${target}.part" "${target}.aria2"
            wget -O "${target}.part" "https://huggingface.co/bartowski/google_gemma-4-26B-A4B-it-GGUF/resolve/main/google_gemma-4-26B-A4B-it-Q6_K.gguf"
            mv "${target}.part" "${target}"
          fi
      volumeMounts:
        - name: cache
          mountPath: /cache
  volumes:
    - name: cache
      persistentVolumeClaim:
        claimName: llama-gemma4-cache
EOF
```

Watch progress:

```bash
kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig \
  -n ai logs -f pod/llama-gemma4-cache-download
```

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

If the cache pod has already completed successfully, the first activation only
has to load the local GGUF from the dedicated static cache PV at
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
