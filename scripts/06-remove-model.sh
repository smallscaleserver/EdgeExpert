#!/usr/bin/env bash
# =============================================================================
# 06-remove-model.sh — remove a single Ollama model
# Usage:  bash scripts/06-remove-model.sh <model[:tag]>
# =============================================================================

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

MODEL="${1:-}"
if [[ -z "$MODEL" ]]; then
  err "Usage: bash scripts/06-remove-model.sh <model[:tag]>"
  log ""
  bash "$(dirname "$0")/05-list-models.sh"
  exit 1
fi

check_docker
ensure_ollama_running

# Verify model exists
if ! docker exec edge-ollama ollama list | awk 'NR>1 {print $1}' | grep -qx "$MODEL"; then
  warn "Model not installed: $MODEL"
  log ""
  bash "$(dirname "$0")/05-list-models.sh"
  exit 1
fi

section "🗑️  Remove model: $MODEL"
if ! confirm "Are you sure?"; then
  log "Cancelled."
  exit 0
fi

# Note: 'ollama rm' (NOT just 'rm') — fixes the bug from earlier draft.
docker exec edge-ollama ollama rm "$MODEL"

ok "Removed: $MODEL"
log ""
bash "$(dirname "$0")/05-list-models.sh"
