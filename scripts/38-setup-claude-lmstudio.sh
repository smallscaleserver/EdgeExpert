#!/usr/bin/env bash
# =============================================================================
# 38-setup-claude-lmstudio.sh — Claude Code TUI on LM Studio (Option F-direct)
# =============================================================================
# Mirrors what https://www.youtube.com/watch?v=Cyn_Dm05_eU walks through:
# point the official Claude Code CLI at LM Studio's Anthropic-compatible
# endpoint, get the polished Claude Code UX backed by a local model, with no
# subscription burn and no LiteLLM round-trip.
#
# Mechanism
# ---------
# Claude Code reads ANTHROPIC_BASE_URL / ANTHROPIC_AUTH_TOKEN / ANTHROPIC_MODEL
# from the environment and calls /v1/messages on whatever URL you point it at.
# Recent LM Studio builds speak that endpoint natively (Developer tab →
# "Anthropic-compatible" pane). Result:
#
#   ┌──────────────┐   /v1/messages    ┌────────────┐
#   │  claude TUI  │ ─────────────────►│  LM Studio │  (host desktop app, GPU)
#   │ (unmodified) │   Anthropic JSON  │   :1234    │
#   └──────────────┘                   └────────────┘
#
# No proxy, no Docker round trip. (For the through-LiteLLM path that also
# surfaces LM Studio in Open WebUI / OpenCode, run scripts/37-setup-lmstudio.sh
# instead — the two scripts coexist.)
#
# What this does
# --------------
#   1. Verifies LM Studio is up locally and a model is loaded.
#   2. Verifies the Anthropic-compatible endpoint (/v1/messages) actually
#      answers — older LM Studio builds only do OpenAI; this script tells the
#      user to upgrade if so.
#   3. Verifies the `claude` CLI is installed (or runs 31-setup-claude-code.sh
#      to install it — that script also handles Node.js bootstrap).
#   4. Writes a wrapper `claude-lmstudio` that exports the right env vars and
#      execs the regular `claude` binary.
#
# Usage:
#   bash scripts/38-setup-claude-lmstudio.sh
#   claude-lmstudio                   # in any directory, like `claude`
#
# Re-running is safe.
# =============================================================================

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"
# shellcheck source=lib/manifest.sh
source "$(dirname "$0")/lib/manifest.sh"

ENV_FILE="$REPO_ROOT/.env"

section "🤖 Claude Code TUI + LM Studio (Option F-direct)"

[[ -f "$ENV_FILE" ]] || die ".env not found. Run: bash scripts/00-install.sh"
load_env  # so manifest knows about $AI_DATA_ROOT

# env_get / env_set / install_wrapper live in lib/common.sh.

# --- 1. LM Studio reachable? ------------------------------------------------
# From the host (where the wrapper will run), LM Studio always lives at
# localhost. LMSTUDIO_HOST in .env is for *containers* and is irrelevant here.
lmstudio_port="$(env_get LMSTUDIO_PORT || echo 1234)"
lmstudio_url="http://localhost:${lmstudio_port}"

section "🔎 Probing LM Studio at $lmstudio_url"
if ! curl -sf "$lmstudio_url/v1/models" >/dev/null 2>&1; then
  err "Cannot reach LM Studio at $lmstudio_url/v1/models"
  cat <<EOF

Open the LM Studio desktop app and:
  1. Load a model with tool-calling support (e.g. openai/gpt-oss-20b,
     llama-3.1-8b-instruct, qwen2.5-coder-7b-instruct).
  2. Developer tab → toggle "Status: Running" on.
  3. Verify "Reachable at" shows port ${lmstudio_port}.

If you don't have LM Studio yet, install it from https://lmstudio.ai
EOF
  exit 1
fi
ok "LM Studio reachable"

# --- 2. Anthropic-compatible endpoint present? ------------------------------
# Older LM Studio builds only ship the OpenAI-compatible endpoint. We probe
# /v1/messages with a minimal body — a 200 means we're good; a 404 means the
# build is too old. Anything else (5xx, network) gets surfaced verbatim.
section "🧪 Checking Anthropic-compatible endpoint"
probe_body='{"model":"probe","max_tokens":1,"messages":[{"role":"user","content":"ping"}]}'
http_code=$(curl -s -o /tmp/lmstudio-probe.json -w '%{http_code}' \
  -X POST "$lmstudio_url/v1/messages" \
  -H 'Content-Type: application/json' \
  -H 'anthropic-version: 2023-06-01' \
  -d "$probe_body" \
  || echo "000")

case "$http_code" in
  2*|400|422)
    # 200 = good. 400/422 = endpoint exists but rejected our intentionally
    # bogus model id — also good for our purposes.
    ok "/v1/messages responds (HTTP $http_code)"
    ;;
  404)
    err "LM Studio at $lmstudio_url returns 404 on /v1/messages."
    err "Your LM Studio build is too old or the Anthropic endpoint is disabled."
    err "Update LM Studio to a recent build, then re-run."
    rm -f /tmp/lmstudio-probe.json
    exit 1
    ;;
  *)
    err "Unexpected response from /v1/messages (HTTP $http_code). Body:"
    sed -n '1,20p' /tmp/lmstudio-probe.json >&2 || true
    rm -f /tmp/lmstudio-probe.json
    exit 1
    ;;
esac
rm -f /tmp/lmstudio-probe.json

# --- 3. Resolve the model id ------------------------------------------------
# Prefer the value already in .env (user's source of truth). If unset, take
# the first id LM Studio reports.
model="$(env_get LMSTUDIO_MODEL || true)"
if [[ -z "$model" ]]; then
  if command -v jq >/dev/null 2>&1; then
    model=$(curl -sf "$lmstudio_url/v1/models" | jq -r '.data[0].id // empty')
  else
    model=$(curl -sf "$lmstudio_url/v1/models" \
      | tr ',' '\n' \
      | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
      | head -n1)
  fi
fi
[[ -n "$model" ]] || die "Could not determine LM Studio model id."
ok "Using model: $model"

# --- 4. Ensure `claude` CLI is installed -----------------------------------
# 31-setup-claude-code.sh handles Node.js + npm install of @anthropic-ai/
# claude-code. We don't run the MCP-registration parts — those need cloud
# Claude. But the install + wrapper portions are idempotent and safe.
if ! command -v claude >/dev/null 2>&1; then
  info "claude CLI not found — running scripts/31-setup-claude-code.sh to install it…"
  # The 31 script also wants edge-ollama running for its MCP registration.
  # That's irrelevant for us, so set GITHUB_TOKEN unset and tolerate the
  # "ollama not running" exit by bringing the core stack up first.
  bash "$REPO_ROOT/scripts/31-setup-claude-code.sh" || \
    warn "31-setup-claude-code.sh exited non-zero (likely the MCP step). Continuing."
fi
command -v claude >/dev/null 2>&1 || die "claude CLI still missing. Install manually: npm i -g @anthropic-ai/claude-code"
ok "claude CLI installed: $(claude --version 2>/dev/null || echo 'unknown')"

# --- 5. Write the wrapper ---------------------------------------------------
wrapper_name="claude-lmstudio"

# LM Studio doesn't require an auth token, but Claude Code refuses to start
# without one. Send the literal placeholder LM Studio's docs use; LM Studio
# ignores it.
auth_token="lm-studio"

tmp="$(mktemp)"
cat >"$tmp" <<EOF
#!/usr/bin/env bash
# Auto-generated by scripts/38-setup-claude-lmstudio.sh — do not edit.
# Wires the unmodified Claude Code CLI to a local LM Studio server.
export ANTHROPIC_BASE_URL="${lmstudio_url}"
export ANTHROPIC_AUTH_TOKEN="${auth_token}"
export ANTHROPIC_MODEL="${model}"
# Same model for sub-agents / small-fast tasks — keep everything local.
export ANTHROPIC_SMALL_FAST_MODEL="${model}"
exec claude "\$@"
EOF
chmod u+rwX,g+rwX,o-rwx "$tmp"

target="$(install_wrapper "$wrapper_name" "$tmp")"
rm -f "$tmp"
manifest_add_path "$target"

ok "Installed wrapper: $target"
warn_if_not_on_path "$(dirname "$target")"

# --- 6. Done ----------------------------------------------------------------
log ""
section "✅ Done"
cat <<EOF
Start a Claude Code session backed by LM Studio:

  cd $REPO_ROOT
  $wrapper_name

The TUI is identical to a normal \`claude\` session. The model line at the
top will show '$model' and every token of inference happens on this host —
nothing leaves the machine.

Sanity check (one-shot, no TUI):

  curl -s $lmstudio_url/v1/messages \\
    -H 'anthropic-version: 2023-06-01' \\
    -H 'Content-Type: application/json' \\
    -d '{"model":"$model","max_tokens":64,"messages":[{"role":"user","content":"say hi"}]}'

Coexistence:
  • Plain \`claude\` (no -lmstudio suffix) is untouched — still uses your
    cloud subscription.
  • \`claude-local\` (Ollama via LiteLLM, Option D) is independent.
  • \`claude-lmstudio\` (this wrapper) bypasses the proxy entirely.

Switch models:
  1. Eject the current model in LM Studio, load a new one.
  2. Re-run this script — it picks up the new id automatically.

Caveats:
  • Tool-calling depends on the loaded model. 7B-class models still mis-
    format Anthropic tool calls sometimes; pick something with strong tool
    support (e.g. openai/gpt-oss-20b, qwen2.5-coder-32b, llama-3.1-70b).
  • The hardest reasoning still loses to cloud Claude.

Full guide: docs/AI-CODING-SETUP.md  (Option F — LM Studio)
EOF
