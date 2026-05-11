#!/usr/bin/env bash
# =============================================================================
# scripts/lib/common.sh — shared helpers
# =============================================================================
# Source this from every script:
#   source "$(dirname "$0")/lib/common.sh"
# =============================================================================

set -euo pipefail

# --- Resolve repo root (parent of scripts/) ---------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Colors ------------------------------------------------------------------
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'
  C_RED=$'\033[0;31m'
  C_GREEN=$'\033[0;32m'
  C_YELLOW=$'\033[0;33m'
  C_BLUE=$'\033[0;34m'
  C_BOLD=$'\033[1m'
else
  C_RESET="" C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_BOLD=""
fi

log()      { printf "%s\n" "$*"; }
info()     { printf "%sℹ%s  %s\n"  "$C_BLUE"   "$C_RESET" "$*"; }
ok()       { printf "%s✓%s  %s\n"  "$C_GREEN"  "$C_RESET" "$*"; }
warn()     { printf "%s⚠%s  %s\n"  "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()      { printf "%s✗%s  %s\n"  "$C_RED"    "$C_RESET" "$*" >&2; }
section()  { printf "\n%s%s%s\n"   "$C_BOLD"   "$*"      "$C_RESET"; }
die()      { err "$*"; exit 1; }

# --- Env file loader ---------------------------------------------------------
# Loads .env and .env.versions safely (handles spaces, quotes, comments).
load_env() {
  local f
  for f in "$REPO_ROOT/.env" "$REPO_ROOT/.env.versions"; do
    [[ -f "$f" ]] || continue
    set -a
    # shellcheck disable=SC1090
    source "$f"
    set +a
  done
}

# --- Compose wrapper ---------------------------------------------------------
# Always passes both env files. Usage: compose up -d
compose() {
  local args=()
  [[ -f "$REPO_ROOT/.env" ]]          && args+=(--env-file "$REPO_ROOT/.env")
  [[ -f "$REPO_ROOT/.env.versions" ]] && args+=(--env-file "$REPO_ROOT/.env.versions")
  ( cd "$REPO_ROOT" && docker compose "${args[@]}" "$@" )
}

# --- Preflight checks --------------------------------------------------------
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

check_docker() {
  require_cmd docker
  docker info >/dev/null 2>&1 || die "Docker daemon not reachable. Is it running? Are you in the 'docker' group?"
}

check_compose_v2() {
  docker compose version >/dev/null 2>&1 || \
    die "Docker Compose v2 required. Install: https://docs.docker.com/compose/install/"
}

check_data_root() {
  load_env
  : "${AI_DATA_ROOT:?AI_DATA_ROOT is not set in .env}"
  if [[ ! -d "$AI_DATA_ROOT" ]]; then
    warn "AI_DATA_ROOT does not exist: $AI_DATA_ROOT"
    warn "Run: bash scripts/00-install.sh"
    return 1
  fi
  return 0
}

# --- Confirmation helpers ----------------------------------------------------
confirm() {
  local prompt="${1:-Continue?}"
  local reply
  read -r -p "$prompt [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

confirm_phrase() {
  local prompt="$1"
  local phrase="$2"
  local reply
  read -r -p "$prompt (type '$phrase' to confirm): " reply
  [[ "$reply" == "$phrase" ]]
}

# --- Container helpers -------------------------------------------------------
ollama_running() {
  docker ps --format '{{.Names}}' | grep -qx 'edge-ollama'
}

ensure_ollama_running() {
  if ! ollama_running; then
    die "Container 'edge-ollama' is not running. Start with: bash scripts/01-start.sh"
  fi
}

# Wait for the Ollama HTTP API to respond. Reads OLLAMA_PORT from .env.
wait_ollama_api() {
  local timeout="${1:-30}"
  local url="http://localhost:${OLLAMA_PORT:-11434}/api/tags"
  local i
  for ((i=0; i<timeout; i++)); do
    curl -sf "$url" >/dev/null 2>&1 && return 0
    sleep 1
  done
  return 1
}

# Start edge-ollama if it isn't running, then wait for the API to be ready.
# Caller is expected to have run check_docker, check_compose_v2, load_env,
# and check_data_root already.
ensure_ollama_started() {
  if ollama_running; then
    return 0
  fi
  info "Container 'edge-ollama' is not running — starting it…"
  compose up -d ollama
  if ! wait_ollama_api 30; then
    die "Ollama API did not become ready within 30s. Try: bash scripts/03-verify.sh"
  fi
  ok "edge-ollama is up"
}

# --- HTTP wait helper --------------------------------------------------------
# Poll URL until it returns 2xx (or any HTTP code if --any) or timeout. Used
# by setup scripts that wait for LiteLLM / OpenHands / etc. to come up.
#   wait_url URL [TIMEOUT_SECONDS] [--any]
wait_url() {
  local url="$1" timeout="${2:-30}" mode="${3:-2xx}" i code
  for ((i=0; i<timeout; i++)); do
    if [[ "$mode" == "--any" ]]; then
      code=$(curl -s -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || echo "000")
      [[ "$code" =~ ^[2-4][0-9][0-9]$ ]] && return 0
    else
      curl -sf "$url" >/dev/null 2>&1 && return 0
    fi
    sleep 1
  done
  return 1
}

# --- .env read/write helpers -------------------------------------------------
# Previously duplicated across 32/36/37/38 — unify here. Scripts that need to
# touch .env should source this file and use these helpers.
ENV_FILE_PATH="${ENV_FILE_PATH:-$REPO_ROOT/.env}"

# Print the value for KEY in $ENV_FILE_PATH. Returns 1 if unset/blank.
env_get() {
  local key="$1" val
  [[ -f "$ENV_FILE_PATH" ]] || return 1
  val=$(awk -F= -v k="$key" '
    /^[[:space:]]*#/ { next }
    $1 == k { sub(/^[^=]*=/, ""); print; exit }
  ' "$ENV_FILE_PATH")
  [[ -n "$val" ]] || return 1
  printf '%s' "$val"
}

# Set or replace KEY=VALUE in $ENV_FILE_PATH. Adds the line if missing.
env_set() {
  local key="$1" value="$2" tmp
  [[ -f "$ENV_FILE_PATH" ]] || die "$ENV_FILE_PATH not found. Run: bash scripts/00-install.sh"
  if grep -qE "^[[:space:]]*${key}=" "$ENV_FILE_PATH"; then
    tmp="$(mktemp)"
    awk -v k="$key" -v v="$value" '
      BEGIN { done = 0 }
      {
        if (!done && $0 ~ "^[[:space:]]*"k"=") {
          print k"="v
          done = 1
        } else {
          print
        }
      }
    ' "$ENV_FILE_PATH" > "$tmp"
    install -m 0640 "$tmp" "$ENV_FILE_PATH"
    rm -f "$tmp"
  else
    printf "%s=%s\n" "$key" "$value" >> "$ENV_FILE_PATH"
  fi
}

# --- Host wrapper installer --------------------------------------------------
# Picks /usr/local/bin if writable (with sudo as a fallback), else ~/.local/bin.
# Echoes the chosen install dir on stdout. Used by 31/33/38/00 to install
# CLI wrappers; result is registered via manifest_add_path.
#
# Usage:
#   target_dir=$(pick_install_dir) ; install -m 0755 ... "$target_dir/foo"
pick_install_dir() {
  local install_dir
  if [[ -w /usr/local/bin ]]; then
    install_dir="/usr/local/bin"
  elif command -v sudo >/dev/null 2>&1; then
    install_dir="/usr/local/bin"
  else
    install_dir="$HOME/.local/bin"
    mkdir -p "$install_dir"
  fi
  printf '%s' "$install_dir"
}

# Install $src as $name into the chosen dir, using sudo only when needed.
# Echoes the absolute target path; returns 0 on success.
install_wrapper() {
  local name="$1" src="$2" target sudo_cmd=""
  local dir; dir="$(pick_install_dir)"
  target="$dir/$name"
  if [[ "$dir" == "/usr/local/bin" && ! -w /usr/local/bin ]]; then
    sudo_cmd="sudo"
  fi
  if [[ -n "$sudo_cmd" ]]; then
    $sudo_cmd install -m 0755 "$src" "$target"
  else
    install -m 0755 "$src" "$target"
  fi
  printf '%s' "$target"
}

# Warn (once) if a chosen install dir is not on PATH for the current shell.
warn_if_not_on_path() {
  local dir="$1"
  case ":$PATH:" in
    *":$dir:"*) return 0 ;;
  esac
  warn "$dir is not on PATH in this shell."
  warn "Add to your shell rc:  export PATH=\"$dir:\$PATH\""
}
