# AI-assisted coding on this stack

Six ways to use this runtime. Pick one — they coexist.

| | A · OpenCode | B · Claude Code + Ollama worker | C · Unified Web UI | D · Claude Code on local Ollama | E · OpenHands web IDE | F · Claude Code on LM Studio |
|---|---|---|---|---|---|---|
| Main interface | TUI | TUI | Open WebUI (browser) | TUI | OpenHands (browser) | TUI |
| Main agent | OpenCode (open source) | Claude Code (subscription) | Whatever model you pick from the dropdown | Claude Code — brain is Ollama | OpenHands agent (open source) | Claude Code — brain is LM Studio |
| Inference | 100% local Ollama | Cloud Claude **+** local Ollama for offload | Local Ollama **and** cloud (Claude/GPT/Gemini) in one menu | 100% local Ollama (via LiteLLM) | Any model from LiteLLM | 100% local LM Studio (host desktop app) |
| Cost | $0 | Claude subscription | $0 local / pay cloud | $0 | $0 local / pay cloud | $0 |
| Best when | offline / privacy required | hardest reasoning, multi-file refactor | quick chat, comparing models | you like Claude Code's UX but want a local Ollama model | "Codex / claude.ai/code"-style web flow | already manage models in LM Studio (GGUF, MLX, Anthropic-compat endpoint) — same UX as the [YouTube walkthrough](https://www.youtube.com/watch?v=Cyn_Dm05_eU) |

Both options share the same **local MCP worker** at
[`scripts/lib/ollama-mcp-server.py`](../scripts/lib/ollama-mcp-server.py),
a tiny Python-stdlib stdio server that exposes Ollama as MCP tools:
`ollama_generate`, `ollama_summarize`, `ollama_embed`, `ollama_list_models`.

---

## Prerequisites (both options)

```bash
# Stack up and at least one coding model installed
bash scripts/01-start.sh
bash scripts/04-pull-model.sh qwen2.5-coder:7b      # or :14b / :32b for more VRAM

# Optional, only needed for ollama_embed
bash scripts/04-pull-model.sh nomic-embed-text
```

Models suited to coding agents on this stack (see
[`docs/MODEL-RECOMMENDATIONS.md`](MODEL-RECOMMENDATIONS.md)):

| VRAM | Recommended |
|---|---|
| 8 GB  | `qwen2.5-coder:7b` |
| 16 GB | `qwen2.5-coder:14b`, `deepseek-coder-v2:16b` |
| 24 GB+| `qwen2.5-coder:32b`, `nemotron-3-nano` |

---

## Option A — OpenCode (100% local)

OpenCode is an open-source agentic coding TUI with the same shape as Claude
Code (slash commands, tool use, MCP). It speaks any OpenAI-compatible
endpoint, so it talks straight to Ollama.

```bash
bash scripts/30-setup-opencode.sh           # default model qwen2.5-coder:7b
bash scripts/30-setup-opencode.sh qwen2.5-coder:32b   # or pick your own
```

That script:
1. Confirms `edge-ollama` is running.
2. Pulls the chosen coding model if missing.
3. Installs the OpenCode CLI (one-line installer from `opencode.ai`).
4. Verifies `opencode.json` (project config, points at `http://localhost:11434/v1`).

Then:

```bash
cd /path/to/edge-model-runtime
opencode
```

The project-level [`opencode.json`](../opencode.json) registers the local
Ollama provider, sets `qwen2.5-coder:7b` as default, and wires the
`ollama-tools` MCP so OpenCode can also call `ollama_summarize` etc. on
sub-tasks.

### GitHub from OpenCode

OpenCode runs `git` and shell commands directly, so the simplest GitHub
workflow is:

```bash
gh auth login                 # one-time, host-level
```

Then ask OpenCode to "create a PR for these changes" and it will use `gh`.
For a structured GitHub MCP, add a block to `opencode.json` under `mcp`:

```jsonc
"github": {
  "type": "local",
  "command": ["npx", "-y", "@modelcontextprotocol/server-github"],
  "environment": { "GITHUB_PERSONAL_ACCESS_TOKEN": "ghp_xxx" }
}
```

> Don't commit a real token. Use a shell env var or a local-only file.

---

## Option B — Claude Code + Ollama-as-worker

You already pay for Claude — keep using it as the main brain, but let the
local Ollama instance handle:

- summarising long log files / large source files before they go in context,
- generating boilerplate / first-draft unit tests,
- computing embeddings for code search,
- any quick question you'd rather not send out.

### One-time setup

```bash
# Optional — set this first to also register the GitHub MCP server
export GITHUB_TOKEN=ghp_yourFineGrainedPAT

bash scripts/31-setup-claude-code.sh
```

That script:
1. Confirms `edge-ollama` is running and the coding model is installed.
2. Installs Node.js 20 if missing — via [`nvm`](https://github.com/nvm-sh/nvm)
   when run as a normal user (no sudo, lives in `~/.nvm`), or via the NodeSource
   apt repo when run as root. Override with `EDGE_NODE_INSTALL=nvm|nodesource|skip`.
3. Installs the Claude Code CLI (`npm i -g @anthropic-ai/claude-code`).
4. Registers two MCP servers on your **user-scoped** Claude Code config:
   - `ollama`  → `python3 scripts/lib/ollama-mcp-server.py`
   - `github`  → `@modelcontextprotocol/server-github` (only if `GITHUB_TOKEN` is set)

> If you already exported `GITHUB_TOKEN` and need to re-run with sudo (for the
> NodeSource path), use `sudo -E` so the env var survives.

### Log in (uses your subscription)

```bash
claude login
```

Pick "Anthropic Console / Claude.ai subscription" when prompted — this binds
the CLI to the plan you're already paying for. No API key needed for that
flow; usage counts against your subscription.

### Use it

```bash
cd /path/to/edge-model-runtime
claude
```

Inside the session:

```
/mcp                    # should list:  ollama  (and github if configured)
```

Then prompt naturally — Claude will pick when to delegate. To force
delegation, be explicit:

> Use `ollama_summarize` to compress `scripts/00-install.sh`, then suggest
> three improvements based on the summary.

> Use `ollama_generate` with `qwen2.5-coder:7b` to draft 5 unit tests for
> `lib/common.sh::confirm_phrase`. I'll review and refine.

### Why this is "local 100%" on the worker side

The MCP server (`scripts/lib/ollama-mcp-server.py`) only talks to
`http://localhost:11434`. Anything routed through `ollama_*` tools never
leaves the host. The main Claude conversation still goes to Anthropic — only
explicit tool calls stay local. If you need *full* offline, use Option A.

---


> ต้องการทำงาน "Codex/Claude Code style" ผ่านหน้าเว็บอย่างเดียว? ดูคู่มือ
> [`docs/WEB-CODEX-PLAYBOOK.md`](./WEB-CODEX-PLAYBOOK.md) (ภาษาไทย, step-by-step) — รวม workflow แบบ Plan → Patch และวิธี `git apply` จริงใน repo.

## Option C — Unified Web UI (cloud + local in one dropdown)

You already get Open WebUI on `http://localhost:3000` for chatting with the
local Ollama models. Option C adds a small **LiteLLM** proxy that fronts
cloud providers (Anthropic, OpenAI, Gemini, …) as an OpenAI-compatible
endpoint, so cloud models show up in the **same model dropdown** as your
local ones. You log in once, pick a model from the menu, and chat — no
per-tool config.

### One-time setup

```bash
bash scripts/32-setup-cloud-models.sh
```

That wizard:
1. Generates a `LITELLM_MASTER_KEY` in `.env` (used by Open WebUI to talk
   to the proxy).
2. Prompts for `ANTHROPIC_API_KEY` if missing and saves it to `.env`.
   Press Enter to skip — you can edit `.env` later and re-run.
3. Brings up the `cloud` profile (`docker compose --profile cloud up -d
   litellm`) and recreates Open WebUI so it picks up the new endpoint.
4. Lists the cloud models LiteLLM is now serving.

### Use it from the browser

1. Open `http://localhost:3000` in your browser.
2. Click the model dropdown (top-left). Local Ollama models and Claude
   (or any cloud model you've enabled) appear in the same list.
3. Pick one and chat.

### Use it from OpenCode (TUI)

The same LiteLLM proxy is wired into [`opencode.json`](../opencode.json)
under a `litellm` provider, so the OpenCode model picker shows both
`ollama/...` and `litellm/claude-...` entries.

The proxy requires the master key, which lives in `.env` (gitignored).
Load it into the shell before starting OpenCode:

```bash
set -a && source .env && set +a
opencode
```

Use [direnv](https://direnv.net/) to make that automatic per directory.

### Adding more providers

Edit `.env`:

```env
OPENAI_PROVIDER_API_KEY=sk-...
GEMINI_API_KEY=...
```

Then uncomment the matching block in
[`litellm/config.yaml`](../litellm/config.yaml) and re-run
`bash scripts/32-setup-cloud-models.sh`. Anything you don't want listed,
delete from that file.

### Stopping the cloud proxy

The local stack keeps running:

```bash
docker compose --profile cloud stop litellm
```

The Open WebUI dropdown will fall back to local-only models on next
refresh.

### Privacy note

Calls routed to a cloud model leave your host (that's the whole point —
they're cloud models). Calls to local Ollama models still never leave.
LiteLLM logs requests at `INFO` level by default — set `LITELLM_LOG=WARNING`
in `.env` to quiet that.

---

## Option D — Claude Code TUI, local Ollama brain

Same `claude` CLI as Option B, but instead of going to Anthropic the
requests go to the LiteLLM proxy from Option C, which forwards them to a
local Ollama model. You get the polished Claude Code UI without burning
subscription tokens — useful for routine edits, drafts, and "rubber-duck"
work where cloud Claude is overkill.

The mechanism is a stock Claude Code feature: it reads
`ANTHROPIC_BASE_URL` / `ANTHROPIC_AUTH_TOKEN` from the environment and
calls `/v1/messages` on whatever URL you point it at. LiteLLM speaks that
endpoint natively for Ollama backends.

```
┌──────────────┐  /v1/messages   ┌────────────┐   /api/chat   ┌─────────┐
│  claude TUI  │ ───────────────►│  LiteLLM   │ ─────────────►│ Ollama  │
│ (unmodified) │  Anthropic JSON │ (Anthropic │  Ollama JSON  │  (GPU)  │
└──────────────┘                 │  adapter)  │               └─────────┘
                                 └────────────┘
```

### Prerequisites

- Option C set up first (so LiteLLM is configured and `LITELLM_MASTER_KEY`
  exists in `.env`).
- The `claude` CLI installed (`bash scripts/31-setup-claude-code.sh` — you
  do not need to log in for Option D, the wrapper bypasses login).

### One-time setup

```bash
bash scripts/33-setup-claude-local.sh                       # default: qwen2.5-coder (7B)
# or pick another LiteLLM model_name:
bash scripts/33-setup-claude-local.sh qwen2.5-coder-large   # 32B, much better tool calls
bash scripts/33-setup-claude-local.sh nemotron-nano
bash scripts/33-setup-claude-local.sh gpt-oss               # OpenAI open-weights 20B,
                                                            # the LM Studio video model
                                                            # (pull with: scripts/04-pull-model.sh gpt-oss:20b)
```

That script:
1. Verifies `edge-ollama` and `edge-litellm` are running (starts LiteLLM if not).
2. Verifies the requested model is registered in
   [`litellm/config.yaml`](../litellm/config.yaml) and the underlying Ollama
   tag is pulled (offers to pull if missing).
3. Recreates LiteLLM if needed so newly added entries become visible.
4. Installs a wrapper script (`claude-local`, or `claude-local-<model>`) that
   exports the right env vars and execs `claude`.

### Use it

```bash
cd /path/to/anywhere
claude-local                      # qwen2.5-coder
claude-local-qwen2.5-coder-large  # 32B, if you ran the 32B setup
```

The TUI is identical to a normal `claude` session. The model line at the
top shows the local model name. All inference happens on the GPU.

The plain `claude` command (no `-local` suffix) is **untouched** and still
talks to Anthropic via your subscription.

### Adding a new local model

1. Pull it: `bash scripts/04-pull-model.sh <ollama-tag>`
2. Add an entry under `model_list:` in
   [`litellm/config.yaml`](../litellm/config.yaml):
   ```yaml
   - model_name: my-model
     litellm_params:
       model: ollama_chat/<ollama-tag>
       api_base: http://ollama:11434
   ```
3. `bash scripts/33-setup-claude-local.sh my-model`

### Caveats

- Claude Code expects Anthropic-style tool calls. 7B-class models mis-format
  them often — fine for chat / single-file edits, flaky for multi-step tool
  use. Use `qwen2.5-coder-large` (32B) when you need reliable tool use.
- The hardest reasoning still loses to cloud Claude. For multi-file refactors
  prefer Option B (cloud brain, local worker).
- LiteLLM logs every request at `INFO` by default. Set
  `LITELLM_LOG=WARNING` in `.env` to quiet the container logs.

---

## Option E — Web agentic IDE (OpenHands)

The browser-native counterpart to Claude Code. OpenHands is an open-source
agentic IDE that runs as a service on your host: open `http://<host>:3030`,
connect a GitHub account, point at a repo, and chat with an agent that can
clone, edit, run shell commands, run tests, commit, and push — all visible
in a file-tree + chat + terminal layout, no TUI required.

```
                              ┌─────────────────────────────┐
                              │  Browser                     │
                              │  ───────────────────────────│
  http://<host>:3030 ─────────►│ OpenHands UI                │
                              │  (file tree · chat · term)  │
                              └────────────┬────────────────┘
                                           │ /v1/messages
                                           ▼
                                   ┌──────────────┐
                                   │   LiteLLM    │  (your existing proxy)
                                   │   :4000      │
                                   └──────┬───────┘
                                          │
                       ┌──────────────────┼─────────────────────┐
                       ▼                  ▼                     ▼
                 Anthropic           OpenAI/Gemini          local Ollama
                 (claude-*)            (optional)         (qwen, nemotron)
```

This runs **alongside** Open WebUI on the same host, on a different port —
both stay available, no fork or patch of Open WebUI is involved. The agent
spawns short-lived sandbox containers via the host's Docker socket; that's
the trust model — same as any docker-in-docker tool, only enable on
hardware you own.

### Prerequisites

- Option C set up first (`bash scripts/32-setup-cloud-models.sh`) so the
  LiteLLM proxy and `LITELLM_MASTER_KEY` exist.
- Docker socket access for the user running the script (the wizard uses
  `compose --profile coding-web`, which mounts `/var/run/docker.sock`).

### One-time setup

```bash
bash scripts/36-setup-coding-web.sh
```

That wizard:
1. Verifies `LITELLM_MASTER_KEY` exists and the LiteLLM proxy is healthy.
2. Creates `${AI_DATA_ROOT}/openhands` for OpenHands state.
3. Pulls the OpenHands image and starts the `coding-web` profile.
4. Waits for the HTTP port to come up.
5. Prints the URL plus the GitHub OAuth callback URL you'd need when
   registering an OAuth App.

### Use it from the browser

1. Open `http://<host>:3030`.
2. **Settings → LLM** (one-time)
   - Provider: `LiteLLM Proxy`
   - Base URL: `http://litellm:4000`
   - API key: the `LITELLM_MASTER_KEY` from `.env`
   - Model: any id LiteLLM serves — e.g. `claude-opus-4-7`,
     `qwen2.5-coder-large`, `nemotron-nano`
3. **Settings → Git → connect GitHub**
   - **OAuth (recommended).** Follow "GitHub OAuth setup" below — one-time.
   - Or paste a fine-grained PAT (`repo` + `workflow` scopes).
4. **New conversation**, e.g.
   > Clone `https://github.com/<you>/<repo>`, find the failing test in
   > `tests/api/users.test.ts`, fix it, run the suite, and open a PR
   > titled "fix: null guard in users router".

### GitHub OAuth setup (optional, one-time)

1. https://github.com/settings/developers → **New OAuth App**
2. Fill in:
   - Application name: `edge-openhands`
   - Homepage URL: `http://<host>:3030`
   - Authorization callback URL:
     `http://<host>:3030/api/integrations/github/callback`
3. Create the app, copy **Client ID** and (after generating) **Client
   Secret**.
4. Add to `.env`:
   ```env
   GITHUB_APP_CLIENT_ID=<client id>
   GITHUB_APP_CLIENT_SECRET=<client secret>
   ```
5. Re-run `bash scripts/36-setup-coding-web.sh` so the container picks up
   the new env. After that, OpenHands' "Connect GitHub" button uses
   OAuth — no token paste needed.

### Stopping just the web IDE

The local stack keeps running:

```bash
docker compose --profile coding-web stop openhands
```

### Caveats

- OpenHands' main app gets root-equivalent power on the host via the
  Docker socket. That's how it spawns sandboxes — there's no lighter
  alternative without giving up the "agent runs commands" feature. Treat
  this stack as a single-tenant trusted environment.
- Sandbox containers are per-session and ephemeral. State for
  conversations / settings / OAuth lives in `${AI_DATA_ROOT}/openhands`;
  cloned repos inside a sandbox **do not** persist across sessions
  unless you `git push` them somewhere. This is intentional for a PoC —
  treat each task as an end-to-end clone → edit → push cycle.
- 7B-class local models are flaky for OpenHands' tool calls (same caveat
  as Option D). Use `qwen2.5-coder-large` (32B), `claude-haiku-4-5`, or
  larger for reliable agent behaviour.
- This is a **proof-of-concept** scope: OpenHands is enabled but not
  auto-pulled by `00-install.sh`, no nav link is wired into Open WebUI,
  and no end-to-end PR-creation test is in `03-verify.sh`. If the PoC
  works for your use cases, those are the obvious next steps.

---

## Option F — Claude Code TUI on LM Studio

Same idea as Option D, but the local brain is [LM Studio](https://lmstudio.ai)
— a desktop app many people already use to download and run GGUF / MLX
models with a polished UI. Recent LM Studio builds expose **both** an
OpenAI-compatible **and** an Anthropic-compatible local server, so Claude
Code can talk to it directly with no proxy in between.

This mirrors the
[YouTube walkthrough](https://www.youtube.com/watch?v=Cyn_Dm05_eU) ("I Ran
Claude Code for FREE… Here's How"): point `ANTHROPIC_BASE_URL` at LM
Studio's `:1234`, pick the model id LM Studio reports, done.

```
┌──────────────┐   /v1/messages    ┌────────────┐
│  claude TUI  │ ─────────────────►│  LM Studio │  (host desktop app, GPU)
│ (unmodified) │   Anthropic JSON  │   :1234    │
└──────────────┘                   └────────────┘
```

Two paths ship in this repo, and they coexist with each other and with
options A–E:

| Path | What you get | Run |
|---|---|---|
| **F-direct** | `claude-lmstudio` CLI wrapper. Fastest — no proxy hop. Same flow as the YouTube clip. | `bash scripts/38-setup-claude-lmstudio.sh` then `claude-lmstudio` |
| **F-shared** | LM Studio appears as `lmstudio` in LiteLLM, surfacing in Open WebUI / OpenCode / OpenHands alongside Ollama and cloud models. | `bash scripts/37-setup-lmstudio.sh` |

You can run both — F-direct gives you a Claude Code session straight on
LM Studio, F-shared makes the same model show up in the browser dropdown.

### Prerequisites

1. Install LM Studio on the host: <https://lmstudio.ai>
2. Open it, pick **My Models → Download** a model with strong tool-call
   support. The video uses `openai/gpt-oss-20b`; alternatives that work
   well: `qwen2.5-coder-32b-instruct`, `llama-3.1-70b-instruct`, any
   instruct-tuned 13B+.
3. Open the **Developer** tab → load the model → toggle **Status: Running**
   on. Confirm "Reachable at" shows `http://<your-host>:1234`. The right-
   hand panel shows the **API Model Identifier** — copy that string.

### F-direct — `claude-lmstudio` (no proxy)

```bash
bash scripts/38-setup-claude-lmstudio.sh
```

That script:
1. Probes LM Studio at `http://localhost:${LMSTUDIO_PORT:-1234}` and bails
   with a clear hint if it's unreachable.
2. Verifies the **Anthropic-compatible** endpoint (`POST /v1/messages`)
   actually answers — older LM Studio builds only ship the OpenAI
   endpoint, in which case you need to update.
3. Reads (or auto-detects) the loaded model id from `/v1/models` and
   stores it in `.env` as `LMSTUDIO_MODEL`.
4. Installs the `claude` CLI if missing (delegates to
   `scripts/31-setup-claude-code.sh`).
5. Writes a wrapper at `/usr/local/bin/claude-lmstudio` (or
   `~/.local/bin/claude-lmstudio` if no sudo) that exports
   `ANTHROPIC_BASE_URL` / `ANTHROPIC_AUTH_TOKEN` / `ANTHROPIC_MODEL` and
   execs the regular `claude` binary.

Use it:

```bash
cd /path/to/anywhere
claude-lmstudio
```

The TUI is identical to a normal `claude` session — model line shows
the LM Studio model id, every token of inference happens on the host.
The plain `claude` command is **untouched** and still uses your cloud
subscription.

Sanity check (no TUI):

```bash
curl -s http://localhost:1234/v1/messages \
  -H 'anthropic-version: 2023-06-01' \
  -H 'Content-Type: application/json' \
  -d '{"model":"openai/gpt-oss-20b","max_tokens":64,"messages":[{"role":"user","content":"say hi"}]}'
```

### F-shared — LM Studio in LiteLLM

If you want the same LM Studio model to show up in Open WebUI, OpenCode,
and OpenHands alongside Ollama and cloud Claude:

```bash
# Prerequisite: scripts/32-setup-cloud-models.sh has run at least once,
# so LITELLM_MASTER_KEY exists. (37 will auto-generate one if not, but
# 32 also wires Open WebUI to the proxy — which is what makes the model
# visible in the browser.)
bash scripts/37-setup-lmstudio.sh
```

That script:
1. Probes LM Studio on `localhost:${LMSTUDIO_PORT:-1234}` (host side).
2. Reads the loaded model id and reconciles it with `LMSTUDIO_MODEL`
   in `.env` (offers to overwrite if they disagree).
3. Ensures `LITELLM_MASTER_KEY` exists (generates one if needed).
4. Recreates the LiteLLM container so it picks up the LM Studio entry
   from [`litellm/config.yaml`](../litellm/config.yaml). The container
   reaches LM Studio via `host.docker.internal:1234` (configured by
   `extra_hosts` on the `litellm` service in `docker-compose.yml`).
5. Smoke-tests `LiteLLM → LM Studio` with a real chat completion.

Use it:

* **Browser** (Open WebUI): pick `lmstudio` from the dropdown next to
  `qwen2.5-coder`, `claude-opus-4-7`, etc.
* **OpenCode TUI**: a `lmstudio` provider is wired into
  [`opencode.json`](../opencode.json) for the **direct** path (port
  1234), and `litellm/lmstudio` is also available via the `litellm`
  provider.
* **OpenHands** (Option E): pick model id `lmstudio`. Requests flow
  `OpenHands → LiteLLM → host LM Studio`.
* **Claude Code with `claude-local`-style wrapping**: not supported via
  this path because LiteLLM rewrites the model id; use F-direct
  (`claude-lmstudio`) instead.

### Switching models in LM Studio

LM Studio is a stateful desktop app: the running model is whatever you
last loaded in the UI. To switch:

1. Eject the current model in LM Studio, load a new one.
2. Re-run whichever 37/38 setup you used. Both auto-detect the new id
   and reconcile `LMSTUDIO_MODEL` in `.env`.

### Caveats

- **Tool-call quality varies by model.** 7B-class models still mis-
  format Anthropic tool calls. Stick to instruct-tuned ≥ 13B (the
  YouTube video uses 20B, which works well).
- **LM Studio is per-user.** Models live in LM Studio's own folder, not
  under `${AI_DATA_ROOT}`. The 3-tier cleanup in this repo does not
  touch them — manage via LM Studio → My Models.
- **Anthropic endpoint is build-dependent.** Very old LM Studio builds
  only have the OpenAI endpoint. F-direct's setup script detects this
  and tells you to update; F-shared (via LiteLLM, which only uses the
  OpenAI endpoint) keeps working on older builds.
- **From inside Docker, LM Studio is at `host.docker.internal:1234`.**
  This is set up automatically via `extra_hosts` on the `litellm` and
  `open-webui` services. On rare Linux setups where the gateway is
  disabled, set `LMSTUDIO_HOST=172.17.0.1` (or your bridge IP) in
  `.env` and re-run script 37.

---

## Verifying the MCP server by hand

Useful for debugging without launching a full agent:

```bash
# List the tools the server advertises
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
  | python3 scripts/lib/ollama-mcp-server.py

# Run a generation end-to-end
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"ollama_list_models","arguments":{}}}' \
  | python3 scripts/lib/ollama-mcp-server.py
```

---

## Troubleshooting

**`/mcp` shows the server as failed** — Run the verification snippet above. If
it errors with `URLError`, start the stack: `bash scripts/01-start.sh`.

**Model not found** — `bash scripts/05-list-models.sh` to see what's installed,
then `bash scripts/04-pull-model.sh <name>`.

**OpenCode can't see Ollama** — Confirm `curl -s http://localhost:11434/api/tags`
returns JSON. If you run OpenCode from a different host, change `baseURL` in
`opencode.json` to the EdgeXpert's IP.

**Claude Code MCP edits live where?** — `~/.claude.json` (user scope). To
remove: `claude mcp remove ollama --scope user`.

**Both setups break after I upgraded the stack** — Models live on the host
(`${AI_DATA_ROOT}/ollama`), so they survive. Re-run `01-start.sh`; nothing
about MCP wiring depends on container internals.
