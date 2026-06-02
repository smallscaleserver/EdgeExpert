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
# Two-step install to preserve the base image's CUDA torch.
# Step 1: install unsloth + unsloth_zoo with --no-deps so pip does NOT pull
#   in a CPU torch from PyPI and overwrite the container's CUDA-enabled torch.
# Step 2: install all other deps normally (they don't touch torch).
RUN pip install --no-cache-dir --no-build-isolation --no-deps unsloth unsloth_zoo \
 && pip install --no-cache-dir --no-build-isolation \
    peft trl bitsandbytes datasets accelerate \
    sentencepiece protobuf einops wandb requests \
 && rm -rf /tmp/build /root/.cache/pip

WORKDIR /workspace/training
