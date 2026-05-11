#!/usr/bin/env bash
# =============================================================================
# 11-remove-host-tools.sh — remove host-side wrappers / MCP regs / npm globals
# =============================================================================
# Granular cleanup that does NOT touch containers, models, or anything under
# $AI_DATA_ROOT (other than the manifest file itself). Drains the artifact
# manifest written by setup scripts (31/33/37/38, etc.).
#
# Usage:
#   bash scripts/11-remove-host-tools.sh                    # interactive
#   bash scripts/11-remove-host-tools.sh --yes              # no prompts
#   bash scripts/11-remove-host-tools.sh --silent-if-empty  # quiet exit when nothing to do
# =============================================================================

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"
# shellcheck source=lib/manifest.sh
source "$(dirname "$0")/lib/manifest.sh"

ASSUME_YES=0
SILENT_IF_EMPTY=0
for arg in "$@"; do
  case "$arg" in
    --yes|-y)            ASSUME_YES=1 ;;
    --silent-if-empty)   SILENT_IF_EMPTY=1 ;;
    -h|--help)
      cat <<EOF
Usage: bash scripts/11-remove-host-tools.sh [--yes] [--silent-if-empty]

Removes host-side artifacts that setup scripts installed outside the repo:
  - wrappers in /usr/local/bin or ~/.local/bin (e.g. claude-local, claude-lmstudio)
  - Claude Code MCP server registrations
  - npm globals such as @anthropic-ai/claude-code

Models, containers, images, and \$AI_DATA_ROOT are NOT touched.
EOF
      exit 0 ;;
  esac
done

# We need $AI_DATA_ROOT to find the manifest. If .env doesn't exist yet, the
# manifest can't possibly exist either — bail quietly under --silent-if-empty.
if [[ -f "$REPO_ROOT/.env" ]]; then
  load_env
fi

if ! manifest_path >/dev/null 2>&1 || [[ -z "$(manifest_dump 2>/dev/null)" ]]; then
  if (( SILENT_IF_EMPTY )); then
    exit 0
  fi
  section "🧽 No host-side artifacts tracked"
  log "Nothing to remove. (The manifest at \$AI_DATA_ROOT/.manifest.list is empty or missing.)"
  exit 0
fi

section "🧽 Remove host-side tools"
log "The following host-side artifacts will be removed:"
manifest_dump | sed 's/^/  • /'
log ""
log "Containers, images, and models on disk are NOT touched."
log ""

if (( ! ASSUME_YES )); then
  if ! confirm "Continue?"; then
    log "Cancelled."
    exit 0
  fi
fi

manifest_drain
manifest_clear

log ""
ok "Host-side tools removed."
log "Models, containers, and images are unchanged. To restart the stack:"
log "  bash scripts/01-start.sh"
