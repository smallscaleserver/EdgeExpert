# syntax=docker/dockerfile:1
# =============================================================================
# edge-finetune — LoRA fine-tune image (unsloth + QLoRA + GGUF export)
# =============================================================================
# Build : docker compose --profile finetune build finetune
# Run   : docker compose --profile finetune run --rm finetune bash
# Remove: docker rmi $(FINETUNE_IMAGE)   # see .env.versions
# =============================================================================

ARG PYTORCH_IMAGE=nvcr.io/nvidia/pytorch:26.04-py3
FROM ${PYTORCH_IMAGE}

WORKDIR /tmp/build

COPY requirements-finetune.txt .
RUN pip install --no-cache-dir -r requirements-finetune.txt \
 && rm -rf /tmp/build /root/.cache/pip

WORKDIR /workspace/training
