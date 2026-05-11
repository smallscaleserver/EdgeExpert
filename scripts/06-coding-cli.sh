#!/usr/bin/env bash
# =============================================================================
# 06-coding-cli.sh — aider AI coding CLI launcher
# =============================================================================
# Runs aider inside a Docker container against Ollama (local, default) or
# LiteLLM→Anthropic (cloud, --cloud flag). Files in the current directory
# are mounted read-write so aider can create, edit, and git-commit them.
#
# Usage:
#   bash scripts/06-coding-cli.sh [--local] [--cloud] [--model <name>] [-- <aider-args>]
#
# Flags:
#   --local              Use local Ollama coder model (default)
#   --cloud              Use cloud model via LiteLLM proxy
#   --model <name>       Override model name (no openai/ prefix needed)
#   --help               Show this help
#   -- <aider-args>      Pass remaining args verbatim to aider
#
# Examples:
#   bash scripts/06-coding-cli.sh
#   bash scripts/06-coding-cli.sh --cloud
#   bash scripts/06-coding-cli.sh --model qwen2.5-coder:14b
#   bash scripts/06-coding-cli.sh -- --message "add docstrings" --yes-always
# =============================================================================

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

# ---------------------------------------------------------------------------
# Parse flags
# ---------------------------------------------------------------------------
MODE=local
MODEL_OVERRIDE=""
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --local)       MODE=local;  shift ;;
    --cloud)       MODE=cloud;  shift ;;
    --model)       MODEL_OVERRIDE="$2"; shift 2 ;;
    -h|--help)
      cat <<EOF
Usage: bash scripts/06-coding-cli.sh [--local] [--cloud] [--model <name>] [-- <aider-args>]

Runs aider (AI pair-programming CLI) against this stack's LLM endpoints.

Flags:
  --local              Local Ollama coder model  (default; no outbound AI calls)
  --cloud              Cloud model via LiteLLM → Anthropic
  --model <name>       Override model (without openai/ prefix)
  --help               Show this message
  -- <aider-args>      Extra args forwarded to aider

Environment (read from .env):
  CODING_CLI_LOCAL_MODEL   local model name  (default: qwen2.5-coder:7b)
  CODING_CLI_CLOUD_MODEL   cloud model name  (default: claude-sonnet-4-6)
  AIDER_IMAGE              Docker image      (default: from .env.versions)

Examples:
  bash scripts/06-coding-cli.sh                          # local, interactive
  bash scripts/06-coding-cli.sh --cloud                  # cloud, interactive
  bash scripts/06-coding-cli.sh -- --message "add tests" # one-shot local
  bash scripts/06-coding-cli.sh --cloud -- --message "..." --yes-always

Troubleshooting:
  Auth error from LiteLLM (401/403):
    Confirm LITELLM_MASTER_KEY is set in .env and edge-litellm is running.
    Test: curl -s http://localhost:4000/health/liveliness
  Model not found (404 / "no such model"):
    For --local: run 'ollama list' inside edge-ollama to see available models.
    For --cloud: check litellm/config.yaml for registered model names.
  Tool-calling unsupported ("No tool use support"):
    Switch to a model that supports function-calling.
    For Ollama: qwen2.5-coder:7b and :14b support tool-calling.
    For cloud:  claude-sonnet-4-6 fully supports tools.
EOF
      exit 0
      ;;
    --)  shift; EXTRA_ARGS+=("$@"); break ;;
    *)   EXTRA_ARGS+=("$1"); shift ;;
  esac
done

# ---------------------------------------------------------------------------
# Load environment
# ---------------------------------------------------------------------------
check_docker
load_env

# ---------------------------------------------------------------------------
# Resolve model and endpoint
# ---------------------------------------------------------------------------
if [[ "$MODE" == "local" ]]; then
  BASE_MODEL="${MODEL_OVERRIDE:-${CODING_CLI_LOCAL_MODEL:-qwen2.5-coder:7b}}"
  # Point directly at Ollama on the shared compose network
  API_BASE="http://edge-ollama:11434/v1"
  API_KEY="ollama"
  ENDPOINT_LABEL="Ollama (local, no outbound calls)"
else
  BASE_MODEL="${MODEL_OVERRIDE:-${CODING_CLI_CLOUD_MODEL:-claude-sonnet-4-6}}"
  # Point at LiteLLM proxy which routes to Anthropic
  API_BASE="http://edge-litellm:${LITELLM_PORT:-4000}/v1"
  API_KEY="${LITELLM_MASTER_KEY:?LITELLM_MASTER_KEY not set in .env — run scripts/32-setup-cloud-models.sh}"
  ENDPOINT_LABEL="LiteLLM → Anthropic (cloud)"
fi

# Aider needs the openai/ prefix for OpenAI-compatible endpoints
if [[ "$BASE_MODEL" != openai/* && "$BASE_MODEL" != ollama/* ]]; then
  AIDER_MODEL="openai/${BASE_MODEL}"
else
  AIDER_MODEL="$BASE_MODEL"
fi

AIDER_IMAGE="${AIDER_IMAGE:-${AIDER_CLI_IMAGE:-paulgauthier/aider:v0.64.1}}"

# ---------------------------------------------------------------------------
# Prepare persistent config dir owned by the calling user
# ---------------------------------------------------------------------------
HOST_UID=$(id -u)
HOST_GID=$(id -g)
AIDER_CACHE="${AI_DATA_ROOT}/coding-cli"
mkdir -p "$AIDER_CACHE"
chmod u+rwX,g+rwX,o-rwx "$AIDER_CACHE"

section "🤖 aider — AI coding CLI"
info "Mode:     $ENDPOINT_LABEL"
info "Model:    $AIDER_MODEL"
info "Image:    $AIDER_IMAGE"
info "Workdir:  $(pwd)"
log ""

# ---------------------------------------------------------------------------
# Run aider
# ---------------------------------------------------------------------------
# --network edge-ai-net        reach edge-ollama / edge-litellm by hostname
# --user HOST_UID:HOST_GID     files created in /workspace are owned by caller
# HOME=/tmp/aider-home         gives aider a writable home under AI_DATA_ROOT
# /etc/gitconfig               system-level gitconfig (readable by any UID)
# GIT_SSH_COMMAND              point at the mounted SSH key for git push
# ---------------------------------------------------------------------------
docker run --rm -it \
  --network edge-ai-net \
  --user "${HOST_UID}:${HOST_GID}" \
  -v "$(pwd):/workspace" \
  -v "${HOME}/.gitconfig:/etc/gitconfig:ro" \
  -v "${HOME}/.ssh:/tmp/ssh:ro" \
  -v "${AIDER_CACHE}:/tmp/aider-home" \
  -w /workspace \
  -e HOME=/tmp/aider-home \
  -e GIT_SSH_COMMAND="ssh -i /tmp/ssh/id_ed25519 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/tmp/aider-home/.ssh_known_hosts" \
  -e OPENAI_API_BASE="${API_BASE}" \
  -e OPENAI_API_KEY="${API_KEY}" \
  -e AIDER_NO_AUTO_COMMITS=false \
  "${AIDER_IMAGE}" \
  --model "${AIDER_MODEL}" \
  "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}"
