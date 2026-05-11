#!/usr/bin/env bash
# =============================================================================
# 03-verify.sh — health check
# =============================================================================

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

section "🔍 edge-model-runtime — verify"

check_docker
load_env

# --- Containers --------------------------------------------------------------
section "📦 Container status"
compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" || true

# --- Disk --------------------------------------------------------------------
section "💾 Storage usage"
if [[ -d "${AI_DATA_ROOT:-}" ]]; then
  du -sh "$AI_DATA_ROOT"/* 2>/dev/null | sort -rh || warn "no data yet"
else
  warn "AI_DATA_ROOT not found: $AI_DATA_ROOT"
fi

# --- GPU ---------------------------------------------------------------------
section "🎮 GPU access (from inside Ollama container)"
if ollama_running; then
  if docker exec edge-ollama nvidia-smi --query-gpu=index,name,memory.used,memory.total \
       --format=csv,noheader 2>/dev/null; then
    :
  else
    warn "GPU not accessible inside container (CPU-only mode)"
  fi
else
  warn "edge-ollama container not running"
fi

# --- API health --------------------------------------------------------------
section "🔌 API health"
ollama_url="http://localhost:${OLLAMA_PORT:-11434}"
webui_url="http://localhost:${WEBUI_PORT:-3000}"
litellm_url="http://localhost:${LITELLM_PORT:-4000}"

if curl -sf "$ollama_url/api/tags" >/dev/null 2>&1; then
  if command -v jq >/dev/null 2>&1; then
    n=$(curl -sf "$ollama_url/api/tags" | jq '.models | length')
    ok "Ollama: OK ($n model(s))"
  else
    ok "Ollama: OK"
  fi
else
  err "Ollama: unreachable at $ollama_url"
fi

if curl -sf "$webui_url" >/dev/null 2>&1; then
  ok "WebUI: OK"
else
  err "WebUI: unreachable at $webui_url"
fi

# LiteLLM is opt-in — only check it if the container exists.
if docker ps --format '{{.Names}}' | grep -qx 'edge-litellm'; then
  if curl -sf "$litellm_url/health/liveliness" >/dev/null 2>&1; then
    if command -v jq >/dev/null 2>&1 && [[ -n "${LITELLM_MASTER_KEY:-}" ]]; then
      n=$(curl -sf -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
            "$litellm_url/v1/models" 2>/dev/null | jq '.data | length' 2>/dev/null || echo "?")
      ok "LiteLLM: OK ($n cloud model(s))"
    else
      ok "LiteLLM: OK"
    fi
  else
    err "LiteLLM: unreachable at $litellm_url"
  fi
fi

# LM Studio is host-side, opt-in. Only probe if the wrapper is installed
# OR LMSTUDIO_PORT is set in .env — otherwise we'd nag every user.
lmstudio_port="${LMSTUDIO_PORT:-1234}"
lmstudio_url="http://localhost:${lmstudio_port}"
if command -v claude-lmstudio >/dev/null 2>&1 || [[ -n "${LMSTUDIO_MODEL:-}" ]]; then
  if curl -sf "$lmstudio_url/v1/models" >/dev/null 2>&1; then
    if command -v jq >/dev/null 2>&1; then
      loaded=$(curl -sf "$lmstudio_url/v1/models" | jq -r '.data[0].id // "(none)"')
      ok "LM Studio: OK (loaded: $loaded)"
    else
      ok "LM Studio: OK"
    fi
  else
    warn "LM Studio: not responding at $lmstudio_url (desktop app not running, or model not loaded)"
  fi
fi

log ""
ok "Verification complete"
