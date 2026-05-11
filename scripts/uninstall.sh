#!/usr/bin/env bash
# =============================================================================
# uninstall.sh — interactive uninstaller
# =============================================================================
# Front door for users who want to "remove this thing." Maps each tier to the
# right numbered script. Default behaviour PRESERVES models — only Tier 4
# wipes them, and only after typing 'DELETE ALL'.
#
# Tier matrix (mirrors README → Cleanup levels):
#
#   Tier 1   Stop containers                     02-stop.sh
#   Tier 2   Remove containers + images          10-cleanup-docker.sh
#            (models kept)
#   Tier 3   Tier 2 + remove host wrappers /     10-cleanup-docker.sh
#            MCP regs / npm globals              --include-host-tools
#            (models kept)
#   Tier 4   WIPE EVERYTHING incl. models        20-wipe-models.sh
#
# Tier 3 is what most users want when they say "remove the Claude Code
# extras but keep my downloaded models" — it leaves $AI_DATA_ROOT alone.
# =============================================================================

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"
# shellcheck source=lib/manifest.sh
source "$(dirname "$0")/lib/manifest.sh"

section "🗑️  edge-model-runtime — uninstall"

# Show what's currently installed so the user has context before picking.
load_env 2>/dev/null || true
manifest_summary=""
if [[ -n "${AI_DATA_ROOT:-}" ]] && [[ -n "$(manifest_dump 2>/dev/null)" ]]; then
  manifest_summary=$(manifest_dump | sed 's/^/    /')
fi

cat <<EOF
Pick a tier. Each tier is more aggressive than the last; everything is
reversible up to (and not including) Tier 4.

  1) Stop containers only
       — frees RAM/GPU; models, images, everything else stays.
  2) Remove containers + Docker images (keep models)
       — frees Docker disk usage. Models on host survive — no re-download.
  3) Tier 2 + remove host wrappers / MCP regs / npm globals (keep models)
       — full uninstall of the agentic CLIs (claude-local, claude-lmstudio,
         the bin/emr symlink, …) but \$AI_DATA_ROOT/ollama is untouched.
  4) WIPE EVERYTHING incl. models (DANGEROUS, requires typing DELETE ALL)
       — re-downloading every model afterwards is on you.

  q) Quit (default)

EOF

if [[ -n "$manifest_summary" ]]; then
  log "Currently tracked host-side artifacts (Tier 3 / 4 will remove these):"
  log "$manifest_summary"
  log ""
fi

read -r -p "Selection [1/2/3/4/q]: " choice
case "$choice" in
  1) bash "$SCRIPT_DIR/02-stop.sh" ;;
  2) bash "$SCRIPT_DIR/10-cleanup-docker.sh" ;;
  3) bash "$SCRIPT_DIR/10-cleanup-docker.sh" --include-host-tools ;;
  4) bash "$SCRIPT_DIR/20-wipe-models.sh" ;;
  q|Q|"") log "Cancelled." ;;
  *) err "Invalid selection: $choice"; exit 1 ;;
esac
