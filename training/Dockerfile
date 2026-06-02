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
# --no-build-isolation: pip builds packages inside the current env so it can
# find the system torch that ships in the base image. Without this, packages
# like xformers (pulled in by unsloth) fail because their isolated build env
# has no torch.
RUN pip install --no-cache-dir --no-build-isolation -r requirements-finetune.txt \
 && rm -rf /tmp/build /root/.cache/pip

WORKDIR /workspace/training
