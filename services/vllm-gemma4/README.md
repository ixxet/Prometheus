# Gemma 4 vLLM Runtime

This image extends the official `vllm/vllm-openai:gemma4` image and pins
`transformers==5.5.0`, which matches the current upstream Gemma 4 recipe.

Why this exists:

- the stock Prometheus `vLLM` deployment previously used a generic `vllm` image
- Gemma 4 support now has its own upstream runtime image
- the user requested that `transformers` stay on the Gemma 4-compatible line

What this does not solve by itself:

- an authenticated Hugging Face token for private or gated model sources
- the exact single-file GGUF filename to serve
- the remaining runtime risk of the experimental `GGUF` path in `vLLM`
