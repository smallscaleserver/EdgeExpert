#!/usr/bin/env bash
# =============================================================================
# 17-uninstall-systemd.sh — LEVEL 1 cleanup: remove systemd unit
# =============================================================================
# Disables and removes the edge-model-runtime.service unit.
# Does NOT stop running containers (use 02-stop.sh for that).
# =============================================================================

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

UNIT_NAME="edge-model-runtime.service"
UNIT_PATH="/etc/systemd/system/${UNIT_NAME}"

section "🗑️  Uninstalling $UNIT_NAME"

if [[ ! -f "$UNIT_PATH" ]]; then
  warn "$UNIT_PATH not found — nothing to uninstall."
  exit 0
fi

if ! confirm "Remove $UNIT_PATH and disable auto-start on boot?"; then
  log "Cancelled."
  exit 0
fi

# Stop if active
if systemctl is-active --quiet "$UNIT_NAME" 2>/dev/null; then
  info "Service is active — stopping first (containers are preserved)."
  if command -v sudo >/dev/null 2>&1; then
    sudo systemctl stop "$UNIT_NAME"
  else
    systemctl stop "$UNIT_NAME"
  fi
fi

# Disable and remove
if command -v sudo >/dev/null 2>&1; then
  sudo systemctl disable "$UNIT_NAME" 2>/dev/null || true
  sudo rm -f "$UNIT_PATH"
  sudo systemctl daemon-reload
else
  systemctl disable "$UNIT_NAME" 2>/dev/null || true
  rm -f "$UNIT_PATH"
  systemctl daemon-reload
fi

ok "Removed $UNIT_PATH"
ok "daemon-reload complete"
log ""
log "Containers are still running (if they were before)."
log "To stop them:   bash scripts/02-stop.sh"
log "To reinstall:   bash scripts/07-install-systemd.sh --enable"
