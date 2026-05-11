#!/usr/bin/env bash
# =============================================================================
# 37-setup-lmstudio.sh — wire host-side LM Studio into the stack (Option F)
# =============================================================================
# LM Studio (https://lmstudio.ai) is a desktop app that exposes an OpenAI- and
# Anthropic-compatible local server (default :1234). Two integrations live in
# this repo:
#
#   F-shared  — this script. Registers LM Studio as a model in LiteLLM so it
#               appears in the same dropdown as Ollama and cloud models, in
#               Open WebUI / OpenCode / OpenHands.
#
#   F-direct  — bash scripts/38-setup-claude-lmstudio.sh
#               Installs a `claude-lmstudio` wrapper that points Claude Code
#               straight at LM Studio's Anthropic-compatible endpoint, like
#               the YouTube walkthrough at
#               https://www.youtube.com/watch?v=Cyn_Dm05_eU. No proxy needed
#               — Claude Code talks /v1/messages directly to LM Studio.
#
# Both can be set up; they coexist. The shared path is what makes Open WebUI
# show "lmstudio" alongside qwen2.5-coder etc.
#
# What this does:
#   1. Verifies .env / .env.versions exist.
#   2. Verifies LM Studio is reachable on the host (defaults: localhost:1234).
#   3. Verifies the loaded model id matches LMSTUDIO_MODEL in .env (offers to
#      auto-fix .env if it does not).
#   4. Ensures LITELLM_MASTER_KEY exists (generates one if not, same as
#      32-setup-cloud-models.sh).
#   5. Brings up the `cloud` profile (LiteLLM) and recreates it so it picks
#      up the LM Studio entry from litellm/config.yaml.
#   6. Smoke-tests the round trip: client → LiteLLM → LM Studio.
#
# Usage:
#   bash scripts/37-setup-lmstudio.sh                   # use values from .env
#   LMSTUDIO_PORT=1235 bash scripts/37-setup-lmstudio.sh
#
# Re-running is safe: existing keys are preserved.
# =============================================================================

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

ENV_FILE="$REPO_ROOT/.env"

section "🎙  LM Studio bridge (Option F — shared via LiteLLM)"

check_docker
check_compose_v2

[[ -f "$ENV_FILE" ]] || die ".env not found. Run: bash scripts/00-install.sh"

# env_get / env_set live in lib/common.sh.

# --- 1. Resolve LM Studio host:port -----------------------------------------
# From the host we always check `localhost`. The container side uses
# `host.docker.internal` (configured via extra_hosts in docker-compose.yml);
# that's a separate concern and is verified later by the smoke test.
lmstudio_port="${LMSTUDIO_PORT:-$(env_get LMSTUDIO_PORT || echo 1234)}"
lmstudio_host_local="localhost"
lmstudio_url_local="http://${lmstudio_host_local}:${lmstudio_port}"

section "🔎 Probing LM Studio at $lmstudio_url_local"
if ! curl -sf "$lmstudio_url_local/v1/models" >/dev/null 2>&1; then
  err "Cannot reach LM Studio at $lmstudio_url_local/v1/models"
  cat <<EOF

Open the LM Studio desktop app and:
  1. Load a model (any tool-using chat model — e.g. openai/gpt-oss-20b).
  2. Open the Developer tab (left sidebar) → toggle "Status: Running" on.
  3. Confirm the "Reachable at" URL shows port ${lmstudio_port}.
     If it shows a different port, set LMSTUDIO_PORT in .env to match.
  4. Re-run this script.

If you don't have LM Studio yet, install it from https://lmstudio.ai
(macOS / Windows / Linux desktop app).
EOF
  exit 1
fi
ok "LM Studio reachable at $lmstudio_url_local"

# --- 2. Read the loaded model id and reconcile with .env --------------------
# LM Studio /v1/models returns OpenAI-style {data:[{id:"<model-id>"}, ...]}.
# We pick the first id; if the user has multiple loaded, they can override
# LMSTUDIO_MODEL in .env manually.
loaded_model=""
if command -v jq >/dev/null 2>&1; then
  loaded_model=$(curl -sf "$lmstudio_url_local/v1/models" | jq -r '.data[0].id // empty')
else
  # jq-free fallback: grep the first "id":"…" pair.
  loaded_model=$(curl -sf "$lmstudio_url_local/v1/models" \
    | tr ',' '\n' \
    | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -n1)
fi

if [[ -z "$loaded_model" ]]; then
  warn "LM Studio responded but reported no loaded model."
  warn "Load a model in the LM Studio UI, then re-run."
  exit 1
fi
ok "LM Studio reports loaded model: $loaded_model"

env_model="$(env_get LMSTUDIO_MODEL || echo)"
if [[ -z "$env_model" ]]; then
  env_set LMSTUDIO_MODEL "$loaded_model"
  ok "Wrote LMSTUDIO_MODEL=$loaded_model to .env"
elif [[ "$env_model" != "$loaded_model" ]]; then
  warn "LMSTUDIO_MODEL in .env ('$env_model') does not match loaded model ('$loaded_model')."
  if confirm "Update .env to '$loaded_model'?"; then
    env_set LMSTUDIO_MODEL "$loaded_model"
    ok "Updated LMSTUDIO_MODEL=$loaded_model"
  else
    info "Keeping .env as-is. Requests will fail with 404 until LM Studio loads '$env_model'."
  fi
else
  ok "LMSTUDIO_MODEL already matches: $env_model"
fi

# Default LMSTUDIO_HOST/_PORT/_API_KEY only if missing — never clobber user.
[[ -n "$(env_get LMSTUDIO_HOST     || echo)" ]] || env_set LMSTUDIO_HOST     "host.docker.internal"
[[ -n "$(env_get LMSTUDIO_PORT     || echo)" ]] || env_set LMSTUDIO_PORT     "$lmstudio_port"
[[ -n "$(env_get LMSTUDIO_API_KEY  || echo)" ]] || env_set LMSTUDIO_API_KEY  "lm-studio"

# --- 3. LiteLLM master key --------------------------------------------------
master_key="$(env_get LITELLM_MASTER_KEY || true)"
if [[ -z "$master_key" ]]; then
  master_key="sk-edge-$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 32)"
  env_set LITELLM_MASTER_KEY "$master_key"
  ok "Generated LITELLM_MASTER_KEY (saved to .env)"
else
  ok "LITELLM_MASTER_KEY already set"
fi

# --- 4. Bring LiteLLM up (or recreate so the LM Studio entry refreshes) -----
# `model_list` is parsed at proxy startup, and the env vars referenced via
# `os.environ/...` are read once on container create. So even if LiteLLM is
# already running, we force-recreate to pick up potentially-changed
# LMSTUDIO_MODEL / LMSTUDIO_HOST.
section "🚀 Recreating LiteLLM with LM Studio entry"
compose --profile cloud up -d --force-recreate litellm

litellm_port="$(env_get LITELLM_PORT || echo 4000)"
litellm_url="http://localhost:${litellm_port}"

section "⏳ Waiting for LiteLLM"
wait_url "$litellm_url/health/liveliness" 30 \
  || die "LiteLLM did not become healthy in 30s. Check: docker logs edge-litellm"
ok "LiteLLM healthy at $litellm_url"

# --- 5. Verify LiteLLM advertises 'lmstudio' --------------------------------
if ! curl -sf -H "Authorization: Bearer $master_key" "$litellm_url/v1/models" \
   | grep -q '"id":[[:space:]]*"lmstudio"'; then
  err "LiteLLM does not advertise 'lmstudio'. Possible causes:"
  err "  - litellm/config.yaml is missing the lmstudio entry (re-pull this branch)"
  err "  - LITELLM_MASTER_KEY changed since the container was created"
  err "Check: docker logs edge-litellm"
  exit 1
fi
ok "LiteLLM advertises 'lmstudio'"

# --- 6. End-to-end smoke test: LiteLLM → LM Studio --------------------------
# We deliberately DO NOT validate the response body — we just want to confirm
# the HTTP round-trip succeeds with a 2xx. A non-2xx here means LiteLLM
# couldn't reach `host.docker.internal:1234` (firewall, LM Studio crashed,
# extra_hosts not applied because container was created before this branch).
section "🧪 Smoke test: LiteLLM → LM Studio"
http_code=$(curl -s -o /tmp/lmstudio-smoke.json -w '%{http_code}' \
  -H "Authorization: Bearer $master_key" \
  -H 'Content-Type: application/json' \
  "$litellm_url/v1/chat/completions" \
  -d '{"model":"lmstudio","max_tokens":16,"messages":[{"role":"user","content":"ping"}]}' \
  || echo "000")

if [[ "$http_code" =~ ^2 ]]; then
  ok "Round-trip OK (HTTP $http_code)"
else
  err "Round-trip failed (HTTP $http_code). Response:"
  sed -n '1,20p' /tmp/lmstudio-smoke.json >&2 || true
  warn "Containers can usually reach the host via 'host.docker.internal'."
  warn "If this Linux box has the gateway disabled, set LMSTUDIO_HOST=172.17.0.1"
  warn "(or your docker bridge IP) in .env and re-run."
fi
rm -f /tmp/lmstudio-smoke.json

# --- 7. Done ----------------------------------------------------------------
log ""
section "✅ Done"
webui_url="http://localhost:$(env_get WEBUI_PORT || echo 3000)"

cat <<EOF
LM Studio:   $lmstudio_url_local           (host-side desktop app)
LiteLLM:     $litellm_url            (model id: 'lmstudio' → $loaded_model)
Open WebUI:  $webui_url

Use it:
  • Browser:    open $webui_url, pick 'lmstudio' from the model dropdown
                (alongside qwen2.5-coder, claude-*, etc.)
  • Claude Code direct (no proxy, fastest):
                bash scripts/38-setup-claude-lmstudio.sh
                claude-lmstudio
  • OpenCode:   set -a && source .env && set +a
                opencode    # 'lmstudio' provider is wired in opencode.json
  • OpenHands:  in Settings → LLM, model id is 'lmstudio' (LiteLLM proxy).

Switch models:
  1. Eject the current model in LM Studio and load a new one.
  2. Re-run this script — it will reconcile LMSTUDIO_MODEL in .env and
     recreate LiteLLM.

To stop sharing LM Studio (Claude Code direct still works):
  docker compose --profile cloud stop litellm

Full guide: docs/AI-CODING-SETUP.md  (Option F — LM Studio)
EOF
