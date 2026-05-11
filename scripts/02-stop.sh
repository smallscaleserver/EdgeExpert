#!/usr/bin/env bash
# =============================================================================
# 02-stop.sh — safe stop (preserves models)
# =============================================================================

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

section "⏹️  Stopping edge-model-runtime"

check_docker
compose down

ok "All containers stopped."
load_env
info "Models preserved at: ${AI_DATA_ROOT:-/mnt/edge-backup/ai-data}/ollama"
info "Restart with: bash scripts/01-start.sh"
