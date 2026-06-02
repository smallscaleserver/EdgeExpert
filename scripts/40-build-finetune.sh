#!/usr/bin/env bash
# =============================================================================
# 40-build-finetune.sh — Build / rebuild / remove the edge-finetune image
# =============================================================================
# Usage:
#   bash scripts/40-build-finetune.sh            # build (or rebuild)
#   bash scripts/40-build-finetune.sh --clean    # remove image + build cache
#   bash scripts/40-build-finetune.sh --remove   # remove image only (free disk)
# =============================================================================
set -euo pipefail
# shellcheck source=scripts/lib/common.sh
source "$(dirname "$0")/lib/common.sh"

IMAGE=$(env_get FINETUNE_IMAGE)
PYTORCH_BASE=$(env_get TRAINING_IMAGE)

case "${1:-}" in
  --remove)
    echo "Removing image: $IMAGE"
    docker rmi "$IMAGE" 2>/dev/null || echo "(already removed)"
    exit 0
    ;;
  --clean)
    echo "Removing image and build cache: $IMAGE"
    docker rmi "$IMAGE" 2>/dev/null || true
    docker builder prune --filter label=image="$IMAGE" -f 2>/dev/null || true
    ;;
esac

echo "Building $IMAGE"
echo "  Base PyTorch : $PYTORCH_BASE"
echo "  Context      : $(pwd)/training"
echo ""

compose --profile finetune build \
  --build-arg PYTORCH_IMAGE="$PYTORCH_BASE" \
  --progress=plain \
  finetune

echo ""
echo "Done: $IMAGE"
echo ""
echo "Run fine-tune:"
echo "  $(basename "$0" .sh) — then:"
echo "  docker compose --env-file .env --env-file .env.versions --profile finetune run --rm finetune \\"
echo "    python /workspace/scripts/finetune_thai_novel.py --export-gguf q8_0"
echo ""
echo "Generate dataset first:"
echo "  docker compose --env-file .env --env-file .env.versions --profile finetune run --rm finetune \\"
echo "    python /workspace/scripts/make_dataset.py --count 500"
echo ""
echo "Remove when done:"
echo "  bash scripts/40-build-finetune.sh --remove"
