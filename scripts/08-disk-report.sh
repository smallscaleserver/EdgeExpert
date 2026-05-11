#!/usr/bin/env bash
# =============================================================================
# 08-disk-report.sh — disk usage breakdown
# =============================================================================

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

load_env

section "💾 Host data usage — $AI_DATA_ROOT"
if [[ -d "${AI_DATA_ROOT:-}" ]]; then
  # || true: some subdirs may be root-owned by containers; errors are suppressed
  # and must not abort the report (set -euo pipefail is active).
  du -sh "$AI_DATA_ROOT"/* 2>/dev/null | sort -rh || true
  log ""
  log "Total:"
  du -sh "$AI_DATA_ROOT" 2>/dev/null || true
else
  warn "AI_DATA_ROOT not found: ${AI_DATA_ROOT:-(unset)}"
fi

section "📋 Ollama models"
if ollama_running; then
  docker exec edge-ollama ollama list
else
  warn "edge-ollama not running — start with bash scripts/01-start.sh"
fi

section "🐳 Docker disk usage (system-wide)"
docker system df

section "📦 Docker images for this stack"
load_env
for var in OLLAMA_IMAGE OPEN_WEBUI_IMAGE LITELLM_IMAGE OPENHANDS_IMAGE VLLM_IMAGE TRAINING_IMAGE CUDA_TEST_IMAGE AIDER_CLI_IMAGE; do
  img="${!var:-}"
  [[ -z "$img" ]] && continue
  if docker image inspect "$img" >/dev/null 2>&1; then
    size=$(docker image inspect "$img" --format '{{.Size}}' | numfmt --to=iec 2>/dev/null || echo "?")
    ok  "$img ($size)"
  else
    warn "$img — not pulled"
  fi
done

section "💽 Filesystem"
df -h "${AI_DATA_ROOT:-/}" 2>/dev/null || df -h /

section "🎙  LM Studio (host-side, not managed by this stack)"
lmstudio_port="${LMSTUDIO_PORT:-1234}"
if curl -sf "http://localhost:${lmstudio_port}/v1/models" >/dev/null 2>&1; then
  if command -v jq >/dev/null 2>&1; then
    curl -sf "http://localhost:${lmstudio_port}/v1/models" \
      | jq -r '.data[].id' | sed 's/^/  /'
  else
    ok "LM Studio responding at :${lmstudio_port} (install jq to list models)"
  fi
  log ""
  log "  Model files live in LM Studio's own folder (not under AI_DATA_ROOT)."
  log "  Manage them via the LM Studio UI → My Models."
else
  log "  LM Studio not running on :${lmstudio_port} — desktop app handles its own storage."
fi
