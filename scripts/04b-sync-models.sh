#!/usr/bin/env bash
# =============================================================================
# 04b-sync-models.sh — pull every enabled model listed in models.txt
# =============================================================================
# Reconciles the declarative registry against what's installed in Ollama.
# Pulls anything missing. Never removes — use 06-remove-model.sh for that
# (preserves the 3-tier cleanup invariant from CLAUDE.md).
#
# Usage:  bash scripts/04b-sync-models.sh
# =============================================================================

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"
# shellcheck source=lib/models.sh
source "$(dirname "$0")/lib/models.sh"

check_docker
ensure_ollama_running
load_env

section "📜 Model registry: $MODELS_FILE"
if [[ ! -f "$MODELS_FILE" ]]; then
  warn "No registry found. See README → Multi-model Runtime."
  exit 0
fi

mapfile -t enabled  < <(models_list_enabled)
mapfile -t disabled < <(models_list_disabled)

info "enabled: ${#enabled[@]}    disabled: ${#disabled[@]}"

if [[ ${#enabled[@]} -eq 0 ]]; then
  warn "No enabled models in $MODELS_FILE — nothing to sync."
  exit 0
fi

# Snapshot installed models so we skip no-op pulls.
mapfile -t installed < <(docker exec edge-ollama ollama list 2>/dev/null | awk 'NR>1 {print $1}')

is_installed() {
  local needle="$1" m
  for m in "${installed[@]}"; do
    [[ "$m" == "$needle" ]] && return 0
  done
  return 1
}

failed=()
for model in "${enabled[@]}"; do
  if is_installed "$model"; then
    ok "present: $model"
    continue
  fi
  section "📥 pulling: $model"
  if ! docker exec -it edge-ollama ollama pull "$model"; then
    failed+=("$model")
    err "pull failed: $model"
  fi
done

if [[ ${#disabled[@]} -gt 0 ]]; then
  section "🚫 disabled (skipped — not deleted)"
  printf '   %s\n' "${disabled[@]}"
  log ""
  log "To free disk, run: bash scripts/06-remove-model.sh <model[:tag]>"
fi

log ""
if [[ ${#failed[@]} -gt 0 ]]; then
  err "Failed pulls: ${failed[*]}"
  exit 1
fi

ok "Sync complete."
