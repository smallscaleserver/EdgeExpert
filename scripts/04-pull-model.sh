#!/usr/bin/env bash
# =============================================================================
# 04-pull-model.sh — download an Ollama model
# Usage:  bash scripts/04-pull-model.sh <model[:tag]>
# Example: bash scripts/04-pull-model.sh qwen2.5-coder:7b
# =============================================================================

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

MODEL="${1:-}"
if [[ -z "$MODEL" ]]; then
  cat <<EOF
Usage: bash scripts/04-pull-model.sh <model[:tag]>

Examples:
  bash scripts/04-pull-model.sh qwen2.5-coder:7b
  bash scripts/04-pull-model.sh llama3.2:3b
  bash scripts/04-pull-model.sh mistral:7b

Browse models: https://ollama.com/library
EOF
  exit 1
fi

check_docker
check_compose_v2
load_env
check_data_root || die "Run scripts/00-install.sh first"
ensure_ollama_started

section "📥 Pulling: $MODEL"
info "Storage: ${AI_DATA_ROOT}/ollama"

# Use -t only when stdout is a TTY so the script also works under
# `sudo`, CI, and other non-interactive shells.
exec_flags=(-i)
[[ -t 1 ]] && exec_flags+=(-t)
docker exec "${exec_flags[@]}" edge-ollama ollama pull "$MODEL"

ok "Pulled: $MODEL"
log ""
bash "$(dirname "$0")/05-list-models.sh"
