FROM vllm/vllm-openai:gemma4@sha256:156ef5e278adb1e7fb822c8442638440a9048a89e235a2f874f093839b9597dc

# Gemma 4 support in the official vLLM recipe expects the 5.5.x transformers line.
RUN python -m pip install --no-cache-dir --upgrade "transformers==5.5.0"

RUN python - <<'PY'
import transformers
assert transformers.__version__ == "5.5.0", transformers.__version__
print("Pinned transformers", transformers.__version__)
PY
