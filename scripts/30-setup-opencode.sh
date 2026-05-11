#!/usr/bin/env bash
# =============================================================================
# 30-setup-opencode.sh — install OpenCode and point it at the local Ollama
# =============================================================================
# Option A: 100% local agentic coding.
#
# What this does:
#   1. Verifies the edge-ollama container is running.
#   2. Ensures a coding model is installed (default: qwen2.5-coder:7b).
#   3. Installs the OpenCode CLI (https://opencode.ai) if missing.
#   4. Confirms the project-level opencode.json is in place.
#
# Run from repo root:  bash scripts/30-setup-opencode.sh [model]
# =============================================================================

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"
# shellcheck source=lib/manifest.sh
source "$(dirname "$0")/lib/manifest.sh"
load_env  # so manifest knows about $AI_DATA_ROOT

MODEL="${1:-qwen2.5-coder:7b}"

section "🤖 OpenCode + Ollama setup (Option A — 100% local)"

check_docker
ensure_ollama_running

# --- 1. Coding model --------------------------------------------------------
if docker exec edge-ollama ollama list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "$MODEL"; then
  ok "Coding model already installed: $MODEL"
else
  info "Pulling coding model: $MODEL"
  bash "$REPO_ROOT/scripts/04-pull-model.sh" "$MODEL"
fi

# --- 2. OpenCode CLI --------------------------------------------------------
if command -v opencode >/dev/null 2>&1; then
  ok "OpenCode already installed: $(opencode --version 2>/dev/null || echo 'unknown')"
else
  info "Installing OpenCode CLI…"
  if ! command -v curl >/dev/null 2>&1; then
    die "curl is required to install OpenCode. Install it and re-run."
  fi
  # Official installer (writes to ~/.opencode by default; PATH is appended in shell rc)
  curl -fsSL https://opencode.ai/install | bash
  if ! command -v opencode >/dev/null 2>&1; then
    warn "OpenCode installed but not on PATH yet."
    warn "Open a new shell, or add ~/.opencode/bin to PATH."
  fi
  # Track the install dir so cleanup knows about it.
  if [[ -d "$HOME/.opencode" ]]; then
    manifest_add_path "$HOME/.opencode"
  fi
fi

# --- 3. Project config ------------------------------------------------------
if [[ -f "$REPO_ROOT/opencode.json" ]]; then
  ok "Project config present: opencode.json"
else
  warn "opencode.json missing — re-clone or run: git checkout opencode.json"
fi

log ""
section "✅ Done"

# Detect whether the LiteLLM cloud proxy has been set up — if so, the user
# can also pick Claude / GPT / Gemini from the OpenCode model picker, but
# only after exporting LITELLM_MASTER_KEY into the shell environment.
cloud_hint=""
if [[ -f "$REPO_ROOT/.env" ]] && grep -qE '^[[:space:]]*LITELLM_MASTER_KEY=.+' "$REPO_ROOT/.env"; then
  cloud_hint=$(cat <<'EOF'

Cloud models (via LiteLLM) are also wired into opencode.json. To use them,
load the master key into your shell first:

  set -a && source .env && set +a
  opencode

Tip: add that to your shell rc, or use direnv, so you don't have to repeat it.
EOF
)
fi

cat <<EOF
Start an OpenCode session in this repo:

  cd $REPO_ROOT
  opencode

Default model is set in opencode.json (currently: ollama/$MODEL).
Switch models inside OpenCode with the model picker, or edit opencode.json.
$cloud_hint

Full guide: docs/AI-CODING-SETUP.md
EOF
