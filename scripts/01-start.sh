#!/usr/bin/env bash
# =============================================================================
# 01-start.sh — start core services (fast, predictable)
# =============================================================================
# Does NOT auto-pull images. Use scripts/09-update-images.sh for that.
# =============================================================================

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

section "▶️  Starting edge-model-runtime"

check_docker
check_compose_v2
check_data_root || die "Run scripts/00-install.sh first"

compose up -d ollama open-webui

sleep 2

ok "Services starting"
log ""
log "  WebUI:      http://localhost:${WEBUI_PORT:-3000}"
log "  Ollama API: http://localhost:${OLLAMA_PORT:-11434}"
log ""
log "Run 'bash scripts/03-verify.sh' to confirm health."
