#!/usr/bin/env bash
# =============================================================================
# 33-setup-claude-local.sh — Claude Code TUI, local Ollama brain (Option D)
# =============================================================================
# Reuses the LiteLLM proxy from Option C, but in the *other* direction: the
# proxy already speaks Anthropic's `/v1/messages` API, so any client that
# honours `ANTHROPIC_BASE_URL` (Claude Code does) can be pointed at it. The
# proxy then forwards the call to a local Ollama model.
#
# Net result: the official Claude Code TUI, but with no cloud round-trip and
# no subscription usage — the model behind the curtain is Qwen / Nemotron /
# whatever you have in `ollama list`.
#
# What this does:
#   1. Verifies edge-ollama is running.
#   2. Verifies LiteLLM is running, starting the `cloud` profile if needed.
#   3. Verifies the requested model is registered in litellm/config.yaml AND
#      that the underlying Ollama tag is pulled (offers to pull if missing).
#   4. Writes a wrapper script `claude-local` (or `claude-local-<model>`) that
#      exports ANTHROPIC_BASE_URL / ANTHROPIC_AUTH_TOKEN / ANTHROPIC_MODEL and
#      execs the regular `claude` binary.
#   5. Prints usage.
#
# Re-running with a different model creates a separate wrapper alongside the
# default one, e.g. `claude-local-qwen2.5-coder-large`.
#
# Usage:
#   bash scripts/33-setup-claude-local.sh                       # qwen2.5-coder (7B)
#   bash scripts/33-setup-claude-local.sh qwen2.5-coder-large   # 32B, much better tool calls
#   bash scripts/33-setup-claude-local.sh nemotron-nano
#
# Limits to know about:
#   • Claude Code expects Anthropic tool-call format. 7B-class models often
#     mis-format tool calls; 32B (qwen2.5-coder-large) handles them well.
#   • Hardest reasoning still loses to cloud Claude. For multi-file refactors,
#     stick with Option B (Claude Code subscription + Ollama as MCP worker).
# =============================================================================

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"
# shellcheck source=lib/manifest.sh
source "$(dirname "$0")/lib/manifest.sh"

ENV_FILE="$REPO_ROOT/.env"
LITELLM_CONFIG="$REPO_ROOT/litellm/config.yaml"

# Argument: model_name as registered in litellm/config.yaml (NOT the Ollama tag).
MODEL="${1:-qwen2.5-coder}"

section "🧠 Claude Code TUI + local Ollama brain (Option D) — model: $MODEL"

check_docker
check_compose_v2
ensure_ollama_running

[[ -f "$ENV_FILE" ]] || die ".env not found. Run: bash scripts/00-install.sh"
[[ -f "$LITELLM_CONFIG" ]] || die "Missing $LITELLM_CONFIG"

load_env

: "${LITELLM_MASTER_KEY:?LITELLM_MASTER_KEY not set in .env. Run: bash scripts/32-setup-cloud-models.sh}"

LITELLM_PORT="${LITELLM_PORT:-4000}"
LITELLM_URL="http://localhost:${LITELLM_PORT}"

# --- 1. Verify the model is in LiteLLM config -------------------------------
# Match `  - model_name: <MODEL>` (single line YAML form we use).
if ! grep -qE "^[[:space:]]*-[[:space:]]+model_name:[[:space:]]+${MODEL}[[:space:]]*$" "$LITELLM_CONFIG"; then
  err "Model '$MODEL' is not registered in litellm/config.yaml."
  log "Registered model_names:"
  awk '/^[[:space:]]*-[[:space:]]+model_name:/ { print "  - " $3 }' "$LITELLM_CONFIG"
  die "Add an entry for '$MODEL' to $LITELLM_CONFIG, then re-run."
fi
ok "LiteLLM config has '$MODEL'"

# --- 2. Verify the underlying Ollama tag is pulled --------------------------
# Pull the `model:` line (e.g. `ollama_chat/qwen2.5-coder:32b`) for the entry.
ollama_ref="$(awk -v want="$MODEL" '
  $0 ~ "^[[:space:]]*-[[:space:]]+model_name:[[:space:]]+"want"[[:space:]]*$" { found=1; next }
  found && /^[[:space:]]*model:/ { sub(/^[^:]*:[[:space:]]*/, ""); print; exit }
' "$LITELLM_CONFIG")"

ollama_tag=""
case "$ollama_ref" in
  ollama_chat/*|ollama/*) ollama_tag="${ollama_ref#*/}" ;;
  *)
    warn "Model '$MODEL' is not an Ollama-backed entry (got '$ollama_ref'). Continuing without tag check."
    ;;
esac

if [[ -n "$ollama_tag" ]]; then
  if docker exec edge-ollama ollama list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "$ollama_tag"; then
    ok "Ollama tag pulled: $ollama_tag"
  else
    warn "Ollama tag not pulled: $ollama_tag"
    if confirm "Pull '$ollama_tag' now? (this can be several GB)"; then
      bash "$REPO_ROOT/scripts/04-pull-model.sh" "$ollama_tag"
    else
      die "Cannot continue without the underlying Ollama model. Pull it then re-run."
    fi
  fi
fi

# --- 3. Make sure LiteLLM is up ---------------------------------------------
if ! curl -sf "$LITELLM_URL/health/liveliness" >/dev/null 2>&1; then
  info "LiteLLM not reachable at $LITELLM_URL — starting it."
  compose --profile cloud up -d litellm
  wait_url "$LITELLM_URL/health/liveliness" 30 \
    || die "LiteLLM did not come up. Check: docker logs edge-litellm"
fi
ok "LiteLLM healthy at $LITELLM_URL"

# After editing config.yaml the running container may still hold the old
# version (the bind mount picks up file changes, but model_list is parsed at
# startup). Recreate so new entries are visible.
if ! curl -sf -H "Authorization: Bearer $LITELLM_MASTER_KEY" "$LITELLM_URL/v1/models" \
   | grep -q "\"id\":[[:space:]]*\"$MODEL\""; then
  info "Recreating LiteLLM so it picks up '$MODEL' from config.yaml…"
  compose --profile cloud up -d --force-recreate litellm
  wait_url "$LITELLM_URL/health/liveliness" 30 \
    || die "LiteLLM did not come back up."
fi

# Final smoke check: the model id is now exposed.
if ! curl -sf -H "Authorization: Bearer $LITELLM_MASTER_KEY" "$LITELLM_URL/v1/models" \
   | grep -q "\"id\":[[:space:]]*\"$MODEL\""; then
  die "LiteLLM does not advertise '$MODEL'. Check: docker logs edge-litellm"
fi
ok "LiteLLM advertises '$MODEL'"

# --- 4. Write the wrapper script --------------------------------------------
# Default name `claude-local` for the canonical 7B model; suffix the model
# name otherwise so multiple flavours can coexist.
if [[ "$MODEL" == "qwen2.5-coder" ]]; then
  wrapper_name="claude-local"
else
  wrapper_name="claude-local-${MODEL}"
fi

tmp="$(mktemp)"
cat >"$tmp" <<EOF
#!/usr/bin/env bash
# Auto-generated by scripts/33-setup-claude-local.sh — do not edit.
# Wires Claude Code (TUI) to LiteLLM, which forwards to local Ollama.
export ANTHROPIC_BASE_URL="${LITELLM_URL}"
export ANTHROPIC_AUTH_TOKEN="${LITELLM_MASTER_KEY}"
export ANTHROPIC_MODEL="${MODEL}"
# Same model for sub-agents — keep everything local.
export ANTHROPIC_SMALL_FAST_MODEL="${MODEL}"
exec claude "\$@"
EOF
chmod u+rwX,g+rwX,o-rwx "$tmp"

target="$(install_wrapper "$wrapper_name" "$tmp")"
rm -f "$tmp"
manifest_add_path "$target"

ok "Installed wrapper: $target"
warn_if_not_on_path "$(dirname "$target")"

# --- 5. Done ----------------------------------------------------------------
log ""
section "✅ Done"
cat <<EOF
Start a Claude Code session backed by local Ollama:

  cd $REPO_ROOT
  $wrapper_name

Inside the TUI everything looks identical to a normal \`claude\` session —
the model name shown will be '$MODEL', and all tool calls / thinking happen
on this host. Nothing leaves the machine.

Sanity check (one-shot, no TUI):

  curl -s $LITELLM_URL/v1/messages \\
    -H 'Authorization: Bearer \$LITELLM_MASTER_KEY' \\
    -H 'Content-Type: application/json' \\
    -d '{"model":"$MODEL","max_tokens":64,"messages":[{"role":"user","content":"say hi"}]}'

The plain \`claude\` command (no wrapper) still uses your cloud subscription —
this script does not modify it.

Switch model:
  bash scripts/33-setup-claude-local.sh qwen2.5-coder-large   # creates claude-local-qwen2.5-coder-large

Caveats:
  • 7B-class models miss Anthropic tool-call format frequently. Use
    qwen2.5-coder-large (32B) when you need reliable tool use.
  • For hardest reasoning, prefer Option B (Claude Code + cloud).

Full guide: docs/AI-CODING-SETUP.md
EOF
