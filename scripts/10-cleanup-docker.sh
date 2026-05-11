#!/usr/bin/env bash
# =============================================================================
# 10-cleanup-docker.sh — LEVEL 2 cleanup
# =============================================================================
# Removes containers, this stack's images, and Docker build cache.
# Models on host are PRESERVED.
# =============================================================================

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"
# shellcheck source=lib/manifest.sh
source "$(dirname "$0")/lib/manifest.sh"

# Flags:
#   --include-host-tools   also drain manifest (claude-local wrappers, MCP regs, …)
INCLUDE_HOST_TOOLS=0
for arg in "$@"; do
  case "$arg" in
    --include-host-tools) INCLUDE_HOST_TOOLS=1 ;;
    -h|--help)
      cat <<EOF
Usage: bash scripts/10-cleanup-docker.sh [--include-host-tools]

Removes containers + images for this stack. Preserves models on the host.
Pass --include-host-tools to also remove tracked host wrappers, MCP regs,
and npm globals (a.k.a. cleanup --full from the emr CLI).
EOF
      exit 0 ;;
  esac
done

section "🧹 LEVEL 2 cleanup — containers + images"
load_env

cat <<EOF
This will remove:
  • All containers from this stack
  • Docker images: $OLLAMA_IMAGE, $OPEN_WEBUI_IMAGE, $CUDA_TEST_IMAGE
    (and LiteLLM/OpenHands/vLLM/training/aider images if pulled)
  • Dangling images and build cache

This will PRESERVE:
  • $AI_DATA_ROOT/ollama       (models)
  • $AI_DATA_ROOT/open-webui   (chat history & users)
  • $AI_DATA_ROOT/hf-cache     (HuggingFace cache)
  • $AI_DATA_ROOT/training     (training outputs)
EOF
if (( INCLUDE_HOST_TOOLS )); then
  cat <<EOF

ALSO removing host-side artifacts tracked in the manifest:
$(manifest_dump 2>/dev/null | sed 's/^/  • /' || echo '  (manifest empty)')
EOF
fi
log ""
if ! confirm "Continue?"; then
  log "Cancelled."
  exit 0
fi

# --- Remove containers from compose ----------------------------------------
section "Removing containers"
compose down --remove-orphans

# --- Remove images from this stack -----------------------------------------
section "Removing images"
for var in OLLAMA_IMAGE OPEN_WEBUI_IMAGE LITELLM_IMAGE OPENHANDS_IMAGE VLLM_IMAGE TRAINING_IMAGE CUDA_TEST_IMAGE AIDER_CLI_IMAGE; do
  img="${!var:-}"
  [[ -z "$img" ]] && continue
  if docker image inspect "$img" >/dev/null 2>&1; then
    if docker image rm "$img" >/dev/null 2>&1; then
      ok "removed $img"
    else
      warn "could not remove $img (in use?)"
    fi
  fi
done

# --- Optionally drain manifest (host wrappers, MCP regs, npm globals) ------
if (( INCLUDE_HOST_TOOLS )); then
  section "Removing host-side artifacts"
  manifest_drain
  manifest_clear
fi

# --- Prune dangling --------------------------------------------------------
section "Pruning"
docker image prune -f
docker builder prune -f
docker network prune -f

ok "Level 2 cleanup complete."
log ""
log "Models preserved at: $AI_DATA_ROOT/ollama"
log "Restart with: bash scripts/01-start.sh   (will re-pull only if image was removed)"
