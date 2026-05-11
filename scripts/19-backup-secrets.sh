#!/usr/bin/env bash
# =============================================================================
# 19-backup-secrets.sh — backup .env and .env.versions
# =============================================================================
# Copies secrets to ${AI_DATA_ROOT}/backups/env/<timestamp>/ with mode 600.
# Optionally GPG-encrypts the backup.
#
# Usage:
#   bash scripts/19-backup-secrets.sh [--gpg <recipient>] [--help]
#
# Flags:
#   --gpg <recipient>   GPG-encrypt the backup for this key ID or email
#   --help              Show this message
#
# Suggested cron (add to crontab -e — NOT installed automatically):
#   # Weekly .env backup, log to AI_DATA_ROOT/logs/
#   0 3 * * 0  cd /home/expert/edge-model-runtime && \
#               bash scripts/19-backup-secrets.sh >> \
#               /mnt/edge-backup/ai-data/logs/backup-secrets.log 2>&1
# =============================================================================

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

GPG_RECIPIENT=""
for arg in "$@"; do
  case "$arg" in
    --gpg)      GPG_RECIPIENT="${2:-}"; shift 2 ;;
    -h|--help)
      grep '^#' "$0" | grep -v '^#!/' | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) die "Unknown flag: $arg. Use --help." ;;
  esac
done

# ---------------------------------------------------------------------------
# Load env and validate
# ---------------------------------------------------------------------------
load_env

: "${AI_DATA_ROOT:?AI_DATA_ROOT not set in .env}"

if [[ ! -f "$REPO_ROOT/.env" ]]; then
  die ".env not found at $REPO_ROOT/.env. Nothing to back up."
fi

# Refuse to run if .env contains a placeholder Anthropic key (not yet configured).
# A placeholder looks like the literal string from .env.example (empty or "sk-ant-api03-REPLACE").
CURRENT_KEY=$(env_get ANTHROPIC_API_KEY 2>/dev/null || echo "")
if [[ -z "$CURRENT_KEY" || "$CURRENT_KEY" == *"REPLACE"* || "$CURRENT_KEY" == "sk-ant-api03-..." ]]; then
  die ".env still has a placeholder ANTHROPIC_API_KEY. Configure it before backing up."
fi

# ---------------------------------------------------------------------------
# Create backup directory
# ---------------------------------------------------------------------------
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="${AI_DATA_ROOT}/backups/env/${TIMESTAMP}"
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

section "🔐 Backing up secrets"
info "Destination: $BACKUP_DIR"

# ---------------------------------------------------------------------------
# Copy files
# ---------------------------------------------------------------------------
for f in .env .env.versions; do
  src="${REPO_ROOT}/${f}"
  [[ -f "$src" ]] || continue
  dst="${BACKUP_DIR}/${f}"
  if [[ -n "$GPG_RECIPIENT" ]]; then
    gpg --yes --recipient "$GPG_RECIPIENT" --encrypt --output "${dst}.gpg" "$src" \
      || die "GPG encryption failed for $f"
    chmod 600 "${dst}.gpg"
    ok "Encrypted: ${dst}.gpg"
  else
    install -m 600 "$src" "$dst"
    ok "Copied: $dst"
  fi
done

# ---------------------------------------------------------------------------
# Print restore command
# ---------------------------------------------------------------------------
log ""
ok "Backup complete: $BACKUP_DIR"
log ""
log "Restore command:"
if [[ -n "$GPG_RECIPIENT" ]]; then
  log "  gpg --decrypt ${BACKUP_DIR}/.env.gpg > ${REPO_ROOT}/.env"
  log "  gpg --decrypt ${BACKUP_DIR}/.env.versions.gpg > ${REPO_ROOT}/.env.versions"
else
  log "  cp ${BACKUP_DIR}/.env ${REPO_ROOT}/.env"
  log "  cp ${BACKUP_DIR}/.env.versions ${REPO_ROOT}/.env.versions"
fi
log ""
log "Then restart the stack:"
log "  cd ${REPO_ROOT} && bash scripts/01-start.sh"
log ""
log "Cron suggestion (weekly, append to crontab -e):"
log "  0 3 * * 0  cd ${REPO_ROOT} && bash scripts/19-backup-secrets.sh >> ${AI_DATA_ROOT}/logs/backup-secrets.log 2>&1"
