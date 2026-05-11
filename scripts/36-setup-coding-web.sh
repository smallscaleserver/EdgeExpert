#!/usr/bin/env bash
# =============================================================================
# 36-setup-coding-web.sh — OpenHands agentic web IDE (Option E)
# =============================================================================
# Bring up an OpenHands instance alongside Open WebUI so the same browser
# tab pattern (open URL → pick model → work) extends to GitHub repo work:
# clone, edit with an agent, run tests, commit, push.
#
# What this does:
#   1. Verifies .env / .env.versions exist.
#   2. Ensures LITELLM_MASTER_KEY and ANTHROPIC_API_KEY are set (OpenHands
#      reuses them via the LiteLLM proxy).
#   3. Brings up the `cloud` profile (LiteLLM) if not already running, so the
#      OpenHands container can reach `http://litellm:4000` on first launch.
#   4. Creates ${AI_DATA_ROOT}/openhands for OpenHands state with sane perms.
#   5. Pulls the OpenHands image and starts the `coding-web` profile.
#   6. Waits for the OpenHands HTTP port to answer.
#   7. Prints the URL plus the GitHub OAuth callback URL the user needs when
#      registering an OAuth App on GitHub (optional — PAT in Settings works
#      too).
#
# Re-running is safe: existing keys, state, and OAuth config are preserved.
# =============================================================================

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

ENV_FILE="$REPO_ROOT/.env"

section "🧑‍💻  OpenHands web IDE (Option E)"

check_docker
check_compose_v2

[[ -f "$ENV_FILE" ]] || die ".env not found. Run: bash scripts/00-install.sh"

# env_get / env_set live in lib/common.sh.

# --- 1. LiteLLM master key (must exist; OpenHands authenticates with it) ----
master_key="$(env_get LITELLM_MASTER_KEY || true)"
if [[ -z "$master_key" ]]; then
  warn "LITELLM_MASTER_KEY not set in .env."
  log  "Run scripts/32-setup-cloud-models.sh first — that wizard generates"
  log  "the master key and starts the LiteLLM proxy OpenHands depends on."
  exit 1
fi
ok "LITELLM_MASTER_KEY found in .env"

# --- 2. Make sure LiteLLM is up (cloud profile) -----------------------------
if ! docker ps --format '{{.Names}}' | grep -qx 'edge-litellm'; then
  section "🚀 Starting LiteLLM proxy (required by OpenHands)"
  compose --profile cloud up -d litellm
  litellm_url="http://localhost:$(env_get LITELLM_PORT || echo 4000)"
  if wait_url "$litellm_url/health/liveliness" 30; then
    ok "LiteLLM is healthy"
  else
    warn "LiteLLM did not become healthy in 30s — continuing anyway."
  fi
else
  ok "LiteLLM already running"
fi

# --- 3. State directory under AI_DATA_ROOT ----------------------------------
load_env
: "${AI_DATA_ROOT:?AI_DATA_ROOT must be set in .env}"
state_dir="$AI_DATA_ROOT/openhands"
if [[ ! -d "$state_dir" ]]; then
  mkdir -p "$state_dir"
  # Match the 00-install.sh convention: u+rwX,g+rwX,o-rwx (no chmod 777).
  chmod u+rwX,g+rwX,o-rwx "$state_dir" 2>/dev/null || true
  ok "Created $state_dir"
else
  ok "State dir exists: $state_dir"
fi

# --- 4. Pull image + start coding-web profile -------------------------------
section "🚀 Starting OpenHands"
compose --profile coding-web pull openhands
compose --profile coding-web up -d openhands

# --- 5. Wait for the HTTP port ----------------------------------------------
openhands_port="$(env_get OPENHANDS_PORT || echo 3030)"
openhands_url="http://localhost:${openhands_port}"
section "⏳ Waiting for OpenHands at $openhands_url"
# Any HTTP response (incl. 401/redirect) means the server is up.
if wait_url "$openhands_url/" 60 --any; then
  ok "OpenHands up at $openhands_url"
else
  warn "OpenHands did not respond in 60s. Check: docker logs edge-openhands"
fi

# --- 6. Done — print next steps --------------------------------------------
log ""
section "✅ Done"
host_lan_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
host_lan_ip="${host_lan_ip:-localhost}"
github_cb="http://${host_lan_ip}:${openhands_port}/api/integrations/github/callback"

cat <<EOF
OpenHands:   $openhands_url   (or http://${host_lan_ip}:${openhands_port} on the LAN)
LiteLLM:     http://localhost:$(env_get LITELLM_PORT || echo 4000)
Open WebUI:  http://localhost:$(env_get WEBUI_PORT  || echo 3000)   (still works, runs in parallel)

Use it from the browser:
  1. Open OpenHands at $openhands_url
  2. Settings (gear icon) → LLM
       • Provider:     LiteLLM Proxy
       • Base URL:     http://litellm:4000
       • API key:      <LITELLM_MASTER_KEY from .env>
       • Model:        claude-opus-4-7   (or any other id from LiteLLM)
  3. Settings → Git → connect GitHub
       • OAuth (recommended): see "GitHub OAuth setup" below.
       • Or paste a fine-grained PAT (repo + workflow scopes).
  4. New conversation → "Clone https://github.com/<you>/<repo> and …"

GitHub OAuth setup (one-time, optional):
  1. Visit https://github.com/settings/developers → "New OAuth App"
  2. Application name:          edge-openhands
     Homepage URL:              ${openhands_url}
     Authorization callback:    ${github_cb}
  3. Create the app, copy the Client ID and (after generating) the Secret.
  4. Set in .env:
       GITHUB_APP_CLIENT_ID=<client id>
       GITHUB_APP_CLIENT_SECRET=<client secret>
  5. Re-run this script — OpenHands will pick up the new env on recreate.

To stop just the web IDE (keeps everything else running):
  docker compose --profile coding-web stop openhands

Full guide: docs/AI-CODING-SETUP.md  (Option E — Web agentic IDE)
EOF
