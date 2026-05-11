#!/usr/bin/env bash
# =============================================================================
# 07-install-systemd.sh — install/manage the edge-model-runtime systemd unit
# =============================================================================
# Creates /etc/systemd/system/edge-model-runtime.service so the stack starts
# automatically after boot.
#
# Usage:
#   bash scripts/07-install-systemd.sh [--enable] [--reinstall] [--help]
#
# Flags:
#   --enable      Enable (auto-start on boot) after installing
#   --reinstall   Overwrite an existing unit file
#   --help        Show this message
# =============================================================================

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

ENABLE=0
REINSTALL=0
for arg in "$@"; do
  case "$arg" in
    --enable)    ENABLE=1 ;;
    --reinstall) REINSTALL=1 ;;
    -h|--help)
      cat <<EOF
Usage: bash scripts/07-install-systemd.sh [--enable] [--reinstall]

Installs edge-model-runtime.service so the Docker Compose stack starts on boot.

Flags:
  --enable      Also enable the unit (auto-start on boot after install)
  --reinstall   Allow overwriting an already-installed unit
  --help        Show this help

After installing:
  sudo systemctl start  edge-model-runtime   # start now
  sudo systemctl stop   edge-model-runtime   # stop (containers preserved, not removed)
  sudo systemctl status edge-model-runtime   # health check
  sudo systemctl enable edge-model-runtime   # enable auto-start on boot
  sudo systemctl disable edge-model-runtime  # disable auto-start

The unit reads COMPOSE_PROFILES from .env at install time (default: cloud,coding-web).
To change profiles, edit .env then re-run with --reinstall.

To uninstall: bash scripts/17-uninstall-systemd.sh
EOF
      exit 0
      ;;
    *) die "Unknown flag: $1. Use --help." ;;
  esac
done

UNIT_NAME="edge-model-runtime.service"
UNIT_PATH="/etc/systemd/system/${UNIT_NAME}"

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
check_docker
check_compose_v2
load_env

: "${REPO_ROOT:?}"
: "${AI_DATA_ROOT:?AI_DATA_ROOT not set}"

if [[ -f "$UNIT_PATH" ]] && (( REINSTALL == 0 )); then
  err "$UNIT_PATH already exists."
  err "Run with --reinstall to overwrite, or bash scripts/17-uninstall-systemd.sh to remove first."
  exit 1
fi

# ---------------------------------------------------------------------------
# Build --profile flags from COMPOSE_PROFILES (.env var, default cloud,coding-web)
# ---------------------------------------------------------------------------
PROFILES="${COMPOSE_PROFILES:-cloud,coding-web}"
PROFILE_FLAGS=""
for p in ${PROFILES//,/ }; do
  PROFILE_FLAGS="${PROFILE_FLAGS} --profile ${p}"
done

section "⚙️  Installing $UNIT_NAME"
info "REPO_ROOT:       $REPO_ROOT"
info "COMPOSE_PROFILES: $PROFILES"
info "Unit path:       $UNIT_PATH"

# ---------------------------------------------------------------------------
# Generate unit file
# ---------------------------------------------------------------------------
UNIT_CONTENT="[Unit]
Description=edge-model-runtime (Ollama + Open WebUI + optional profiles)
Documentation=https://github.com/coinbaseblock/edge-model-runtime
After=docker.service network-online.target
Wants=docker.service network-online.target
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
Restart=on-failure
RestartSec=10s
User=expert
Group=docker
WorkingDirectory=${REPO_ROOT}

ExecStart=/usr/bin/docker compose \\
    --env-file ${REPO_ROOT}/.env \\
    --env-file ${REPO_ROOT}/.env.versions \\
    ${PROFILE_FLAGS} \\
    up -d

ExecStop=/usr/bin/docker compose \\
    --env-file ${REPO_ROOT}/.env \\
    --env-file ${REPO_ROOT}/.env.versions \\
    ${PROFILE_FLAGS} \\
    stop

TimeoutStartSec=300
TimeoutStopSec=120

[Install]
WantedBy=multi-user.target
"

# ---------------------------------------------------------------------------
# Write unit file (requires sudo)
# ---------------------------------------------------------------------------
if [[ -w /etc/systemd/system ]]; then
  printf '%s' "$UNIT_CONTENT" > "$UNIT_PATH"
else
  printf '%s' "$UNIT_CONTENT" | sudo tee "$UNIT_PATH" > /dev/null
fi
ok "Wrote $UNIT_PATH"

# Reload daemon
if command -v sudo >/dev/null 2>&1; then
  sudo systemctl daemon-reload
else
  systemctl daemon-reload
fi
ok "systemctl daemon-reload"

# ---------------------------------------------------------------------------
# Optionally enable
# ---------------------------------------------------------------------------
if (( ENABLE )); then
  if command -v sudo >/dev/null 2>&1; then
    sudo systemctl enable "$UNIT_NAME"
  else
    systemctl enable "$UNIT_NAME"
  fi
  ok "Enabled (will start on boot)"
fi

log ""
ok "Installation complete."
log ""
log "Next steps:"
log "  sudo systemctl start  edge-model-runtime   # start now"
log "  sudo systemctl enable edge-model-runtime   # enable auto-start on boot"
log "  sudo systemctl status edge-model-runtime   # verify"
log "  sudo systemctl stop   edge-model-runtime   # stop (containers preserved)"
log ""
log "To uninstall: bash scripts/17-uninstall-systemd.sh"
