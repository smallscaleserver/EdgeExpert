#!/usr/bin/env bash
# =============================================================================
# 32-setup-cloud-models.sh — wire cloud LLMs into the Open WebUI dropdown
# =============================================================================
# Option C: Unified Web UI. Run a LiteLLM proxy alongside Ollama so cloud
# models (Claude, GPT, Gemini …) show up in the same model dropdown as the
# local models. You log in to Open WebUI in your browser, pick a model from
# the menu, and chat — no per-tool config.
#
# What this does:
#   1. Verifies .env / .env.versions exist (run 00-install.sh otherwise).
#   2. Generates LITELLM_MASTER_KEY in .env if missing.
#   3. Prompts for ANTHROPIC_API_KEY if missing in .env (skip with Enter).
#      Other providers (OpenAI, Gemini) are edited manually in .env +
#      uncommented in litellm/config.yaml.
#   4. Pulls the LiteLLM image and starts the `cloud` profile.
#   5. Restarts open-webui so it picks up the new OPENAI_API_BASE_URL env.
#   6. Waits for the LiteLLM health check, then lists registered models.
#
# Re-running is safe: existing keys are preserved.
# =============================================================================

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

ENV_FILE="$REPO_ROOT/.env"

section "☁️  Cloud models in Open WebUI (Option C)"

check_docker
check_compose_v2

[[ -f "$ENV_FILE" ]] || die ".env not found. Run: bash scripts/00-install.sh"

# env_get / env_set live in lib/common.sh now (used by 32/36/37/38 alike).

# --- 1. Master key ----------------------------------------------------------
master_key="$(env_get LITELLM_MASTER_KEY)"
if [[ -z "$master_key" ]]; then
  master_key="sk-edge-$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 32)"
  env_set LITELLM_MASTER_KEY "$master_key"
  ok "Generated LITELLM_MASTER_KEY (saved to .env)"
else
  ok "LITELLM_MASTER_KEY already set"
fi

# --- 2. Anthropic key -------------------------------------------------------
anthropic_key="$(env_get ANTHROPIC_API_KEY)"
if [[ -z "$anthropic_key" ]]; then
  log ""
  log "Anthropic API key (https://console.anthropic.com/settings/keys)."
  log "Press Enter to skip — you can edit .env later and re-run this script."
  read -r -s -p "  ANTHROPIC_API_KEY: " anthropic_key
  echo
  if [[ -n "$anthropic_key" ]]; then
    env_set ANTHROPIC_API_KEY "$anthropic_key"
    ok "Saved ANTHROPIC_API_KEY"
  else
    warn "Skipped — Claude models will return 'unauthorized' until set."
  fi
else
  ok "ANTHROPIC_API_KEY already set"
fi

# --- 3. Bring up LiteLLM ----------------------------------------------------
section "🚀 Starting LiteLLM proxy"
compose --profile cloud up -d litellm

# --- 4. Restart Open WebUI to pick up new OPENAI_* env ----------------------
# The OPENAI_API_KEY env (= LITELLM_MASTER_KEY) is interpolated at container
# create time. If WebUI was started before the master key existed, it has the
# placeholder value baked in.
section "🔄 Refreshing Open WebUI"
compose up -d --force-recreate open-webui

# --- 5. Wait for health -----------------------------------------------------
section "⏳ Waiting for LiteLLM"
litellm_url="http://localhost:$(env_get LITELLM_PORT || echo 4000)"
litellm_url="${litellm_url%/}"
if wait_url "$litellm_url/health/liveliness" 30; then
  ok "LiteLLM up at $litellm_url"
else
  warn "LiteLLM did not become healthy in 30s. Check: docker logs edge-litellm"
fi

# --- 6. List models exposed by the proxy ------------------------------------
section "📋 Models registered with LiteLLM"
if curl -sf -H "Authorization: Bearer $master_key" "$litellm_url/v1/models" \
   | (command -v jq >/dev/null && jq -r '.data[].id' || cat); then
  :
else
  warn "Could not list models (proxy not ready or master key mismatch)"
fi

# --- 7. Done ----------------------------------------------------------------
log ""
section "✅ Done"
webui_url="http://localhost:$(env_get WEBUI_PORT || echo 3000)"
cat <<EOF
Open WebUI:  $webui_url
LiteLLM:     $litellm_url   (master key saved in .env)

Use it from the browser:
  1. Open $webui_url
  2. Click the model dropdown (top-left). Claude models appear
     alongside your local Ollama models — pick one and chat.

Use it from OpenCode (TUI):
  The same models are wired into opencode.json under the "litellm" provider.
  Load the key into your shell, then start OpenCode:

    set -a && source .env && set +a
    opencode

  Inside OpenCode the picker now shows both 'ollama/...' and
  'litellm/claude-...'. Switch any time.

To add OpenAI / Gemini:
  • Set OPENAI_PROVIDER_API_KEY or GEMINI_API_KEY in .env
  • Uncomment the matching block in litellm/config.yaml
  • Re-run: bash scripts/32-setup-cloud-models.sh

To stop the cloud proxy (keeps local stack running):
  docker compose --profile cloud stop litellm

Full guide: docs/AI-CODING-SETUP.md
EOF
