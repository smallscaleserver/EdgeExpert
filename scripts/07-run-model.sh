#!/usr/bin/env bash
# =============================================================================
# 07-run-model.sh — interactive CLI session with a model
# Usage:  bash scripts/07-run-model.sh <model[:tag]>
# =============================================================================

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

MODEL="${1:-}"
if [[ -z "$MODEL" ]]; then
  err "Usage: bash scripts/07-run-model.sh <model[:tag]>"
  log ""
  bash "$(dirname "$0")/05-list-models.sh"
  exit 1
fi

check_docker
ensure_ollama_running

section "🤖 Running: $MODEL"
info "Type /bye or press Ctrl+D to exit"
log ""

docker exec -it edge-ollama ollama run "$MODEL"
