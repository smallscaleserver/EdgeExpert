#!/usr/bin/env bash
# =============================================================================
# 05-list-models.sh — list installed Ollama models
# =============================================================================

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

check_docker
ensure_ollama_running
load_env

section "📋 Installed models"
docker exec edge-ollama ollama list

section "💾 Model storage"
du -sh "${AI_DATA_ROOT}/ollama" 2>/dev/null || warn "no models directory yet"

log ""
log "Pull more:    bash scripts/04-pull-model.sh <model[:tag]>"
log "Run a model:  bash scripts/07-run-model.sh <model[:tag]>"
log "Remove one:   bash scripts/06-remove-model.sh <model[:tag]>"
