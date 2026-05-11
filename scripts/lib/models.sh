#!/usr/bin/env bash
# =============================================================================
# scripts/lib/models.sh — declarative model registry parser
# =============================================================================
# Source AFTER common.sh so $REPO_ROOT is defined:
#   source "$(dirname "$0")/lib/common.sh"
#   source "$(dirname "$0")/lib/models.sh"
# =============================================================================

MODELS_FILE="${MODELS_FILE:-$REPO_ROOT/models.txt}"

# parse_model_line LINE
#   Echoes "<status> <provider> <model>" on success (rc=0).
#   Returns rc=1 for blank/comment lines so callers can `continue`.
#
#   status   = enabled | disabled
#   provider = ollama | vllm | hf   (defaults to ollama)
#   model    = the rest, including any ':tag' suffix
parse_model_line() {
  local line="$1"
  # Strip trailing inline comment, then trim whitespace.
  line="${line%%#*}"
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [[ -z "$line" ]] && return 1

  local status="enabled"
  if [[ "${line:0:1}" == "!" ]]; then
    status="disabled"
    line="${line:1}"
    line="${line#"${line%%[![:space:]]*}"}"
  fi

  # Only strip a leading token before ':' if it's a known provider —
  # model tags also use ':' (e.g. llama3.2:3b), so we can't split blindly.
  local provider="ollama" model="$line"
  case "$line" in
    ollama:*|vllm:*|hf:*)
      provider="${line%%:*}"
      model="${line#*:}"
      ;;
  esac

  printf '%s %s %s\n' "$status" "$provider" "$model"
}

# models_list_enabled — print enabled ollama model specs, one per line.
models_list_enabled() {
  _models_filter enabled ollama
}

# models_list_disabled — print disabled ollama model specs, one per line.
models_list_disabled() {
  _models_filter disabled ollama
}

_models_filter() {
  local want_status="$1" want_provider="$2"
  [[ -f "$MODELS_FILE" ]] || return 0
  local line parsed status provider model
  while IFS= read -r line || [[ -n "$line" ]]; do
    parsed=$(parse_model_line "$line") || continue
    read -r status provider model <<<"$parsed"
    if [[ "$status" == "$want_status" && "$provider" == "$want_provider" ]]; then
      printf '%s\n' "$model"
    fi
  done < "$MODELS_FILE"
  return 0
}
