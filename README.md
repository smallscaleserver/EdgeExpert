# edge-model-runtime

> Production-grade Docker runtime for running and training local LLMs on NVIDIA edge machines — MSI EdgeXpert, NVIDIA DGX Spark, or any Ubuntu + NVIDIA host.

Tested on:
- **MSI EdgeXpert** (x86_64, discrete NVIDIA GPU)
- **NVIDIA DGX Spark** (arm64/aarch64, GB10 / DGX OS 7.x, kernel 6.17 nvidia)
- **HP EliteBook / Windows 11 laptop** (Intel Arc GPU — Windows-native Ollama mode)
- Generic Ubuntu 22.04+ with NVIDIA Container Toolkit

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Docker](https://img.shields.io/badge/docker-compose-blue.svg)](https://docs.docker.com/compose/)
[![NVIDIA](https://img.shields.io/badge/NVIDIA-GPU-76B900.svg)](https://developer.nvidia.com/cuda-toolkit)

This stack runs local LLMs (Ollama + Open WebUI) with optional vLLM and PyTorch training profiles. **All models and data live outside containers**, so rebuilds, image upgrades, and Docker cleanups never force model re-downloads.

---

## ✨ Features

- 🐳 **100% Dockerized** — nothing installed on host OS
- 💾 **Persistent models** — host-side storage, survives rebuilds
- 🛡️ **3-tier cleanup** — safe → medium → nuclear
- 🎮 **Full NVIDIA GPU** support via Container Toolkit
- 🔌 **Optional profiles** — vLLM and PyTorch training (not pulled by default)
- 📌 **Pinned image versions** — reproducible deployments
- 🔐 **No `chmod 777`** — proper permission management
- 🩺 **Health checks** built in
- 🤖 **Claude Code ready** — see [`.claude/`](./.claude) for AI-assisted workflows
- 🧠 **Local AI coding agent** — drive [OpenCode (100% offline)](./docs/AI-CODING-SETUP.md#option-a--opencode-100-local) or [Claude Code + Ollama-as-worker via MCP](./docs/AI-CODING-SETUP.md#option-b--claude-code--ollama-as-worker)
- ☁️ **Unified Web UI** — optional [LiteLLM proxy](./docs/AI-CODING-SETUP.md#option-c--unified-web-ui-cloud--local-in-one-dropdown) puts Claude / GPT / Gemini in the same Open WebUI dropdown as your local models, also surfaced in OpenCode
- 🌐 **Web Codex playbook (TH)** — step-by-step browser workflow for Codex/Claude-style local coding in Open WebUI: [docs/WEB-CODEX-PLAYBOOK.md](./docs/WEB-CODEX-PLAYBOOK.md)
- 🪄 **Claude Code TUI on local Ollama** — [Option D](./docs/AI-CODING-SETUP.md#option-d--claude-code-tui-local-ollama-brain) routes the official `claude` CLI through LiteLLM's Anthropic adapter so a local model is the brain — same UX, no subscription burn
- 🎙 **Claude Code on LM Studio** — [Option F](./docs/AI-CODING-SETUP.md#option-f--claude-code-tui-on-lm-studio) plugs LM Studio (host desktop app) directly into Claude Code via its Anthropic-compatible endpoint, like the [YouTube walkthrough](https://www.youtube.com/watch?v=Cyn_Dm05_eU). The same model also appears in Open WebUI / OpenCode / OpenHands via LiteLLM (`make lmstudio`)

---

## 📋 Requirements

### Linux / DGX / MSI EdgeXpert (original mode)

| Component | Version |
|-----------|---------|
| Ubuntu Linux (or DGX OS) | 22.04+ / DGX OS 7.x |
| Architecture | `x86_64` or `arm64` (aarch64) |
| Docker Engine | 24.0+ |
| Docker Compose | v2.20+ |
| NVIDIA Driver | 535+ |
| NVIDIA Container Toolkit | latest |
| Data disk | ≥ 100 GB free, set via `AI_DATA_ROOT` in `.env` |

### Windows (laptop / desktop — no WSL2 required)

| Component | Version |
|-----------|---------|
| Windows 11 | 22H2+ |
| Docker Desktop | 4.20+ |
| Ollama for Windows | latest |
| GPU | Intel Arc / NVIDIA / CPU (all supported by Ollama.exe) |

> **Windows quick-start**: see [`docs/WINDOWS-SETUP.md`](./docs/WINDOWS-SETUP.md)

> **DGX Spark note:** DGX OS ships with Docker + NVIDIA Container Toolkit pre-installed, so you can skip the toolkit install below. Verify with `docker info | grep -i runtime` — you should see `nvidia`.

Install NVIDIA Container Toolkit:
```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt update && sudo apt install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

---

## 📁 Data Layout

All persistent data is on the host disk — **never inside containers**. The root path is whatever you set `AI_DATA_ROOT` to in `.env`:

```text
${AI_DATA_ROOT}/
├── ollama/        # Ollama models — DO NOT DELETE
├── open-webui/    # WebUI database & settings
├── hf-cache/      # HuggingFace cache (optional vLLM)
├── training/      # Optional training output
└── logs/          # Container logs (rotated)
```

Recommended values for `AI_DATA_ROOT`:

| Host | Recommended path |
|---|---|
| MSI EdgeXpert | `/mnt/edge-backup/ai-data` (external/secondary disk) |
| NVIDIA DGX Spark | `/home/<user>/ai-data` (single 1 TB NVMe; ~915 GB usable) |
| Generic Ubuntu | wherever you have ≥ 100 GB free |

> ⚠️ **Critical:** Do not delete `${AI_DATA_ROOT}/ollama` unless you intentionally want to wipe all downloaded models. The protection layers in `scripts/` are designed to prevent accidental deletion.

---

## 🚀 Quick Start

### Windows (Ollama native — recommended for laptops)

```powershell
# 1. Install Ollama for Windows  →  https://ollama.com/download/windows
# 2. Set OLLAMA_HOST=0.0.0.0 as a Machine env var, restart Ollama
# 3. Install Docker Desktop  →  https://www.docker.com/products/docker-desktop

git clone https://github.com/smallscaleserver/EdgeExpert.git
cd EdgeExpert
Copy-Item .env.windows.example .env.windows   # edit AI_DATA_ROOT and WEBUI_SECRET_KEY
make win-up                                    # starts Open WebUI at http://localhost:3000
ollama pull qwen2.5-coder:7b                   # pull a model

# Intel Arc GPU — enable Vulkan acceleration (one-time, then restart Ollama):
powershell -ExecutionPolicy Bypass -File scripts\win-tune-ollama.ps1
# After restarting Ollama: ollama ps → PROCESSOR column shows "100% GPU"
```

> **Intel Arc GPU**: Ollama's Vulkan backend is **off by default**. Run `win-tune-ollama.ps1` once to set `OLLAMA_VULKAN=1` and register the Intel ICD. Then restart Ollama. Models up to ~20 GB run at 100% GPU on Arc 140T (36 GB Vulkan VRAM from shared RAM).

Full guide: [`docs/WINDOWS-SETUP.md`](./docs/WINDOWS-SETUP.md)

### Linux / Ubuntu / DGX Spark / MSI EdgeXpert

```bash
# 1. Clone
git clone https://github.com/smallscaleserver/EdgeExpert.git
cd EdgeExpert

# 2. Configure: copy .env.example to .env and set AI_DATA_ROOT and GPU_DRIVER
cp .env.example .env
$EDITOR .env   # set AI_DATA_ROOT and GPU_DRIVER (nvidia | intel | cpu)

# 3. Install (first time only)
bash scripts/00-install.sh

# 4. Pull a model
bash scripts/04-pull-model.sh qwen2.5-coder:7b

# Or pull a Nemotron variant (default: nano — see docs/MODEL-RECOMMENDATIONS.md)
bash scripts/0a-pull-nemotron.sh nano

# 5. Open WebUI
open http://localhost:3000   # or http://<host-ip>:3000 from another machine

# 6. AI coding CLI (aider) — local, no outbound calls
cd /your/project
bash /path/to/edge-model-runtime/scripts/06-coding-cli.sh          # local (Ollama)
bash /path/to/edge-model-runtime/scripts/06-coding-cli.sh --cloud  # cloud (Anthropic via LiteLLM)

# 7. Auto-start on boot
bash scripts/07-install-systemd.sh --enable
```

> **Recommended clone location on DGX Spark:** `/home/<user>/edge-model-runtime` (e.g. `/home/expert/edge-model-runtime`). Keep `AI_DATA_ROOT` on the same disk to avoid cross-mount copies.

---

## 💻 Windows Local AI Coding Workflow (Tested)

> Tested on HP EliteBook 8 Gi 14-inch, Intel Core Ultra 7 265H, Intel Arc 140T GPU, 64 GB RAM, Windows 11.
> All inference runs locally — no Anthropic subscription consumed during coding sessions.

### Architecture

```
Claude Code CLI (Windows host)
        │
        ▼  ANTHROPIC_BASE_URL=http://localhost:4000
LiteLLM proxy  (Docker container, port 4000)
        │
        ▼  ollama_chat/qwen2.5-coder:7b
Ollama.exe     (Windows host, port 11434)
        │
        ▼
Intel Arc 140T GPU  ←  36 GB Vulkan VRAM (shared from 64 GB RAM, requires OLLAMA_VULKAN=1)

Open WebUI  (Docker container, port 3000)  ←  browser UI, same models
```

### Step 0 — One-time prerequisites

**Install Ollama for Windows** (host-side, once):
```powershell
winget install Ollama.Ollama
# or download from https://ollama.com/download/windows
```

**Install Docker Desktop** (once):
```
https://www.docker.com/products/docker-desktop
```

**Install Claude Code** (host-side, once — requires Node.js):
```powershell
# Check Node.js (comes pre-installed on many machines)
node --version   # need v18+

# Install Claude Code
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
npm install -g @anthropic-ai/claude-code

# Verify
claude --version   # should print e.g. 2.1.139 (Claude Code)
```

**Install GitHub CLI** (once — needed for `gh auth` and PR creation):
```powershell
winget install --id GitHub.cli
gh --version
```

### Step 1 — Clone and configure

```powershell
git clone https://github.com/smallscaleserver/EdgeExpert.git
cd EdgeExpert

# Copy Windows env template
Copy-Item .env.windows.example .env.windows
```

Edit `.env.windows` — minimum required changes:
```ini
AI_DATA_ROOT=C:/ai-data          # forward slashes; directory must exist
WEBUI_SECRET_KEY=any-random-string
LITELLM_MASTER_KEY=sk-changeme   # change this; used as API key by Claude Code
```

Create the data directory:
```powershell
New-Item -ItemType Directory -Force "C:\ai-data\open-webui"
```

### Step 2 — Run the setup script (as Administrator)

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
.\scripts\win-setup.ps1
```

This script:
1. Sets `OLLAMA_HOST=0.0.0.0` (so Docker containers can reach Ollama)
2. Sets `OLLAMA_MODELS=C:\ai-data\ollama\models` (keeps models off the user profile)
3. Creates `C:\ai-data\open-webui` and `C:\ai-data\ollama\models`
4. Restarts Ollama so env vars take effect
5. Starts Open WebUI via `docker-compose.windows.yml`
6. Pulls `qwen2.5-coder:7b` (~4.7 GB)

### Step 3 — Check models and stack health

```powershell
# Confirm Ollama is running and model is available
ollama list
# NAME                ID              SIZE
# qwen2.5-coder:7b    dae161e27b0e    4.7 GB

# Confirm containers are healthy
docker compose -f docker-compose.windows.yml --env-file .env.windows --env-file .env.versions ps
# NAMES             STATUS
# edge-open-webui   Up ... (healthy)
# edge-litellm      Up ... (healthy)    ← only after make win-cloud

# Test Ollama API
Invoke-RestMethod http://localhost:11434/api/tags | Select-Object -ExpandProperty models | Select-Object name

# Test LiteLLM (after make win-cloud)
Invoke-RestMethod http://localhost:4000/health/liveliness
# I'm alive!
```

Optional — pull a larger model for better code quality:
```powershell
ollama pull qwen2.5-coder:14b   # ~9 GB, noticeably better on multi-file tasks
ollama pull qwen2.5-coder:32b   # ~20 GB, fits in 64 GB RAM, near-Claude quality
```

### Step 4 — GitHub auth (one-time)

Required for `git push` and PR creation:
```powershell
# Configure git identity
git config --global user.name  "your-github-username"
git config --global user.email "your@email.com"

# Authenticate GitHub CLI (browser flow)
gh auth login
# Choose: GitHub.com → HTTPS → Login with a web browser

# Verify
gh auth status
```

### Step 5 — Start local AI coding session

Start LiteLLM (bridges Claude Code → Ollama):
```powershell
make win-cloud
# or:
docker compose -f docker-compose.windows.yml --env-file .env.windows --env-file .env.versions --profile cloud up -d
```

Launch Claude Code — choose one mode:

**Local AI (no Anthropic account needed):**
```powershell
cd C:\your\repo        # any git repo
make win-claude        # from the EdgeExpert directory

# or from any directory:
powershell -ExecutionPolicy Bypass -File C:\Edge\edgeexpert\EdgeExpert\scripts\win-claude-local.ps1
powershell -ExecutionPolicy Bypass -File C:\Edge\edgeexpert\EdgeExpert\scripts\win-claude-local.ps1 -Model qwen2.5-coder-large
```

**Real Anthropic API (login session or API key):**
```powershell
make win-claude-direct        # from the EdgeExpert directory

# or from any directory:
powershell -ExecutionPolicy Bypass -File C:\Edge\edgeexpert\EdgeExpert\scripts\win-claude-local.ps1 -Direct
powershell -ExecutionPolicy Bypass -File C:\Edge\edgeexpert\EdgeExpert\scripts\win-claude-local.ps1 -Direct -Model claude-sonnet-4-6
```

> **First time with `-Direct`?** Run `claude` once and type `/login` to save your Anthropic session,  
> or set `ANTHROPIC_API_KEY=sk-ant-...` in `.env.windows`.

Inside Claude Code, use it exactly like the cloud version:
```
> Read README.md and add a Quick Start section
> Add type hints to all functions in src/utils.py
> Find all TODO comments and create GitHub issues for each
> Refactor auth.py to use dataclasses, then run the tests
```

Switch model inside the session with `/model`:
```
/model qwen2.5-coder:14b     # upgrade to 14b mid-session
/model qwen2.5-coder:32b     # or 32b for hardest tasks
```

### Step 6 — Safe diff / commit / push workflow

**Always review before committing:**
```powershell
git status                  # what files changed
git diff                    # full diff of unstaged changes
git diff --staged           # what is staged
git log --oneline -5        # recent commits
```

**Commit with a conventional message:**
```powershell
git add <specific-files>    # stage only what you intend (not git add -A blindly)
git commit -m "feat(auth): add refresh-token support"
```

**Push and open a PR:**
```powershell
git push origin main

# Or open a PR (requires gh auth):
gh pr create --title "feat: add refresh-token support" --body "Closes #42"
gh pr view --web            # open the PR in the browser
```

**If the AI made a mistake — undo the last commit safely:**
```powershell
git reset HEAD~1            # undo commit, keep file changes (soft-ish)
# review, fix, then re-commit
```

### Windows daily-ops reference

```powershell
make win-up             # start Open WebUI only
make win-cloud          # start Open WebUI + LiteLLM (needed for make win-claude)
make win-claude         # Claude Code TUI → local Ollama (no Anthropic account needed)
make win-claude-direct  # Claude Code TUI → real Anthropic API (login or API key)
make win-down           # stop all containers
make win-status         # show container status

ollama list                       # list installed models
ollama pull qwen2.5-coder:14b     # pull a larger model
ollama rm  qwen2.5-coder:7b       # free disk space
```

Open WebUI (browser chat with local models): http://localhost:3000

---

## 🌐 End-to-end: Web UI → local model → GitHub PR

This is the full Codex / Claude-Code-style loop using **only the browser** for the
chat, with a local Ollama model as the brain. The model proposes a unified diff,
and one `make` command applies it, commits, pushes, and opens a PR.

Detailed Thai walkthrough: [`docs/WEB-CODEX-PLAYBOOK.md`](./docs/WEB-CODEX-PLAYBOOK.md).
The numbered steps below are the same flow, condensed.

### Step 1 — Pull a coding model

```bash
bash scripts/01-start.sh                          # core stack (Ollama + Open WebUI)
bash scripts/04-pull-model.sh qwen2.5-coder:14b   # 7b for ≤8 GB VRAM, 32b for 24 GB+
bash scripts/03-verify.sh                         # confirm GPU + endpoints healthy
```

Multi-model? Add lines to [`models.txt`](./models.txt) and run
`bash scripts/04b-sync-models.sh` instead — see [Multi-model Runtime](#multi-model-runtime-declarative-registry).

### Step 2 — One-time GitHub auth (host-side)

`make apply-patch ... PR=1` shells out to `gh`, so authorize it once:

```bash
gh auth login            # pick GitHub.com → HTTPS → paste a PAT (repo scope)
gh auth status           # verify
```

### Step 3 — Open the Web UI and configure a Codex preset

```bash
make webui               # opens http://localhost:3000
```

In Open WebUI:

1. **Workspace → Models →** pick `qwen2.5-coder:*`.
2. Paste the **Codex-style system prompt** from
   [`docs/WEB-CODEX-PLAYBOOK.md` §2](./docs/WEB-CODEX-PLAYBOOK.md#2-ตั้งค่า-model-preset-ใน-open-webui).
3. Set **Temperature = 0.1–0.2** and save as the default for coding chats.
4. *(Optional)* `bash scripts/32-setup-cloud-models.sh` — adds Claude / GPT /
   Gemini to the **same dropdown** via LiteLLM, so you can A/B local vs. cloud
   without leaving the browser.

### Step 4 — Two-pass chat (Plan, then Patch)

Use the Codex/Claude-Code rhythm right inside the WebUI chat:

- **Pass A — Plan.** Paste the relevant files / paths and ask for a 3–7 bullet
  plan plus assumptions. Iterate until the plan is right.
- **Pass B — Patch.** Then send:

  ```text
  Now output ONLY a unified diff patch.
  Rules:
  - No explanation text outside the diff.
  - Keep changes minimal.
  - Include file paths relative to repo root.
  ```

Copy the diff from the chat into a local file:

```bash
$EDITOR /tmp/web.patch        # paste the unified diff
```

### Step 5 — Apply, commit, push, open PR (one command)

```bash
# dry preview only
make apply-patch P=/tmp/web.patch

# apply + commit + push + open PR on GitHub
make apply-patch P=/tmp/web.patch COMMIT=1 PUSH=1 PR=1 \
  MSG="fix: handle empty config in loader"
```

Behind the scenes, [`scripts/35-apply-web-patch.sh`](./scripts/35-apply-web-patch.sh):

1. Refuses to run on a dirty working tree (override with `FORCE=1`) so your
   in-flight WIP is never swept into the AI commit.
2. Runs `git apply --check` first — if it fails, paste the error back into
   the WebUI chat and ask the model to regenerate just the broken hunks.
3. Applies the patch, commits with `MSG`, pushes the branch, and runs
   `gh pr create` when `PR=1`.

### Step 6 — Verify, then iterate

```bash
bash scripts/03-verify.sh     # stack healthy
git log --oneline -5          # confirm AI commit landed
gh pr view --web              # review the PR in the browser
```

If reviewers leave comments, paste them back into the WebUI chat and repeat
**Step 4 → Step 5**. The loop is: *chat in browser → diff → `make apply-patch`
→ PR updated*.

> **Want the model to edit files directly instead of producing a diff?**
> That's [Option A (`make codex`)](#pick-your-ai-coding-workflow) or
> [Option D (`make claude-local`)](#pick-your-ai-coding-workflow) — same local
> Ollama brain, but a TUI agent that runs `git`/`gh` itself. The browser flow
> above is the equivalent for users who want to stay 100% in the WebUI.

---

## 🎓 Usage

### Pick your AI coding workflow

The repo ships four ways to use a coding assistant on this stack — pick what
matches the job. All of them edit your real git repo and can push to GitHub.

| You want… | Use | One-liner |
|---|---|---|
| Codex/Claude-Code feel, 100% local, edits files directly | **OpenCode TUI** (Option A) | `make codex` |
| Same UX but using a local Ollama model as the brain | **Claude Code on local Ollama** (Option D) | `make claude-local` |
| Same UX but the brain is a model you manage in LM Studio | **Claude Code on LM Studio** (Option F) | `make claude-lmstudio` |
| Hardest reasoning (cloud Claude) + local worker via MCP | **Claude Code + cloud** (Option B) | `make claude-cloud` |
| Browser only — chat in Open WebUI, paste back a unified diff | **Web Codex** (Option C-style) | `make webui`, then `make apply-patch P=/tmp/x.patch COMMIT=1 PUSH=1 PR=1` |
| Surface a host LM Studio model in Open WebUI / OpenCode dropdowns | **LM Studio shared** (Option F-shared) | `make lmstudio` |

`make codex` and `make claude-local` are the closest equivalents to ChatGPT
Codex / Claude Code on a local model — they edit files in this repo and run
`git`/`gh` directly. The browser flow uses the
[Web Codex playbook](./docs/WEB-CODEX-PLAYBOOK.md): the model returns a
unified diff, then `scripts/35-apply-web-patch.sh` (wrapped by
`make apply-patch`) applies + commits + pushes + opens a PR.

Full details and trade-offs: [`docs/AI-CODING-SETUP.md`](./docs/AI-CODING-SETUP.md).

### Upgrading an existing install

You **do not** need `docker compose down` to pull updates. Models live on
the host (`${AI_DATA_ROOT}/ollama`) — they survive every flow below. Only
restart containers when `docker-compose.yml` or `.env.versions` actually
changes.

| What changed in the update | What to run |
|---|---|
| Only scripts / docs / `opencode.json` / `.claude/` | `git pull` — done. Running containers untouched. |
| `docker-compose.yml` or `.env.example` | `git pull && bash scripts/01-start.sh` (Compose recreates only what changed). |
| `.env.versions` (image bumps) | `git pull && bash scripts/09-update-images.sh`. |
| Want a clean container restart anyway | `bash scripts/02-stop.sh && bash scripts/01-start.sh`. Models kept. |

The simple **"works for any update"** recipe:

```bash
cd ~/edge-model-runtime
git status                          # check for local edits (your .env is gitignored & safe)
git pull                            # fetch latest
bash scripts/03-verify.sh           # confirm stack is still healthy
```

After the AI-coding update specifically:

```bash
# Option A — local agent
bash scripts/30-setup-opencode.sh

# Option B — Claude Code + Ollama worker (re-run any time to refresh MCP wiring)
GITHUB_TOKEN=ghp_xxx bash scripts/31-setup-claude-code.sh
```

If `git pull` complains about local changes, stash first:

```bash
git stash && git pull && git stash pop
```

### Daily ops

```bash
bash scripts/01-start.sh       # Start (fast, no auto-pull)
bash scripts/02-stop.sh        # Safe stop (preserves models)
bash scripts/03-verify.sh      # Health check
```

### Model management

```bash
bash scripts/04-pull-model.sh qwen2.5-coder:7b
bash scripts/04b-sync-models.sh                     # pull every enabled entry in models.txt
bash scripts/05-list-models.sh
bash scripts/06-remove-model.sh qwen2.5-coder:7b   # specific model
bash scripts/07-run-model.sh qwen2.5-coder:7b      # interactive CLI
bash scripts/08-disk-report.sh                      # disk usage
bash scripts/09-update-images.sh                    # update Docker images
```

### Multi-model Runtime (declarative registry)

For stacks that run more than one model, list them in [`models.txt`](./models.txt)
instead of pulling each one by hand. Edit the file, run sync, done.

```text
# models.txt
ollama:qwen2.5-coder:7b
ollama:llama3.2:3b
!ollama:mistral:7b      # leading '!' = disabled, kept on disk, not re-pulled
```

Format:

| Token | Meaning |
|---|---|
| `provider:model:tag` | full spec (today only `ollama:` is supported; `vllm:`, `hf:` reserved) |
| `model:tag` | provider defaults to `ollama` |
| `# …` | comment (line or trailing) |
| `!entry` | disabled — skipped by sync, **not deleted** |

Then:

```bash
bash scripts/04b-sync-models.sh
```

The sync script:
- pulls every **enabled** entry that isn't already installed
- prints the **disabled** list for visibility, but never removes anything
  (use `06-remove-model.sh` to actually free disk — keeps the 3-tier
  cleanup invariant intact)

Adding / removing a model is now an edit to a text file plus one command —
no need to touch `docker-compose.yml` or any script.


### Codex/Claude-style repo automation

```bash
make hooks-install   # install git hooks (pre-commit + commit-msg)
make quick-check     # shellcheck + compose config + safety invariants
make ai-review       # quick-check then show git status
make ai-fix          # chmod normalize + quick-check
make ai-pr           # write a PR notes stub in .pr-notes.md
```

These commands provide a repeatable local workflow for plan→patch→validate→PR.

### Cleanup levels

| Level | Script | What it removes | Models? |
|-------|--------|-----------------|---------|
| **L1** | `02-stop.sh` | Running containers | ✅ kept |
| **L2** | `10-cleanup-docker.sh` | Containers + images + caches | ✅ kept |
| **L3** | `20-wipe-models.sh` | **Everything including models** | ❌ deleted |

### Optional profiles

```bash
# vLLM (HuggingFace inference)
docker compose --env-file .env --env-file .env.versions \
  --profile vllm up -d vllm

# Training (PyTorch interactive)
docker compose --env-file .env --env-file .env.versions \
  --profile training run --rm training bash
```

---

## 🏗️ Project Structure

```text
edge-model-runtime/
├── docker-compose.yml         # Inference + optional vLLM/training profiles
├── .env.example               # Copy to .env
├── .env.versions              # Pinned image versions
├── models.txt                 # Declarative model registry (see Multi-model Runtime)
├── .gitignore
├── README.md
├── LICENSE
│
├── .claude/                   # Claude Code config
│   ├── settings.json
│   └── commands/
│
├── scripts/
│   ├── 00-install.sh
│   ├── 01-start.sh
│   ├── 02-stop.sh
│   ├── 03-verify.sh
│   ├── 04-pull-model.sh
│   ├── 04b-sync-models.sh
│   ├── 05-list-models.sh
│   ├── 06-remove-model.sh
│   ├── 07-run-model.sh
│   ├── 08-disk-report.sh
│   ├── 09-update-images.sh
│   ├── 10-cleanup-docker.sh
│   ├── 20-wipe-models.sh
│   ├── uninstall.sh
│   └── lib/
│       ├── common.sh
│       └── models.sh
│
├── training/
│   ├── README.md
│   ├── requirements.txt
│   └── examples/
│       └── lora-finetune.py
│
└── docs/
    ├── ARCHITECTURE.md
    ├── TROUBLESHOOTING.md
    ├── MODEL-RECOMMENDATIONS.md
    └── AI-CODING-SETUP.md      # OpenCode / Claude Code + local Ollama worker
```

---

## 🔄 Rebuild Safety Matrix

| Action | Containers | Images | Models | Re-download? |
|--------|-----------|--------|--------|--------------|
| `02-stop.sh` | removed | kept | kept | ❌ no |
| `09-update-images.sh` | restarted | upgraded | kept | ❌ no |
| `10-cleanup-docker.sh` | removed | removed | kept | ❌ no |
| `20-wipe-models.sh` | removed | removed | **deleted** | ✅ yes |

The model directory (`${AI_DATA_ROOT}/ollama`) is bind-mounted into the container at `/root/.ollama`. Removing the container does not touch the host directory — Ollama just sees its models again on next start.

---

## 🤖 Recommended Models

### Small (≤ 8 GB VRAM)
- `qwen2.5-coder:7b` — coding
- `llama3.2:3b` — general
- `mistral:7b` — general

### Medium (16 GB VRAM)
- `qwen2.5-coder:14b` — coding
- `llama3.1:8b-instruct-q8_0` — high-quality general

### Large (24 GB+ VRAM)
- `qwen2.5-coder:32b`
- `llama3.3:70b-instruct-q4_K_M`

See [`docs/MODEL-RECOMMENDATIONS.md`](./docs/MODEL-RECOMMENDATIONS.md) for full list.

---

## 🛠️ Claude Code Integration

This repo ships with `.claude/commands/` for common operations. From Claude Code:

```
/install        # run installer
/pull <model>   # download a model
/verify         # health check
/cleanup        # level 2 cleanup
```

See [`.claude/README.md`](./.claude/README.md).

---

## 🤖 Local AI Coding Agent (Codex / Claude Code style)

Run a fully local AI coding agent — no subscription, no outbound model API calls,
no data leaving the machine. The agent edits real files, runs `git commit`, and
can push to GitHub, exactly like Codex or Claude Code.

> **⚠️ Back up `.env` before experimenting** — it contains `ANTHROPIC_API_KEY`
> and `LITELLM_MASTER_KEY`. Run `bash scripts/19-backup-secrets.sh` or
> `emr backup` to save a timestamped copy to `${AI_DATA_ROOT}/backups/env/`.

### Prerequisites

- Docker + NVIDIA Container Toolkit installed (`bash scripts/00-install.sh` sets this up)
- `~/.gitconfig` with `user.name` and `user.email` (required for git commits)
- SSH key in `~/.ssh/id_ed25519` added to GitHub (for `git push`)
- Stack running and at least one coding model pulled (steps below)

### 1 — Start the stack

```bash
make up
# or: bash scripts/01-start.sh
# or: emr start
```

Verify everything is healthy:

```bash
make status
# or: bash scripts/03-verify.sh
```

### 2 — Pull a local coding model

```bash
bash scripts/04-pull-model.sh qwen2.5-coder:7b
# or: emr pull qwen2.5-coder:7b
```

The model is stored on the host at `${AI_DATA_ROOT}/ollama` and survives
container rebuilds. Check what is installed:

```bash
bash scripts/05-list-models.sh
# or: emr models
```

Recommended models by VRAM — see [docs/MODEL-RECOMMENDATIONS.md](./docs/MODEL-RECOMMENDATIONS.md).

### 3 — Interactive AI coding session (aider)

`emr aider` launches [aider](https://aider.chat) inside a Docker container,
pointed at the local Ollama model. Files in your **current directory** are
mounted read-write; git identity comes from `~/.gitconfig`.

```bash
cd ~/my-project          # any git repo
emr aider                # local Ollama mode (default, no outbound AI calls)
```

Inside the session:
```
> add type hints to all functions in utils.py
> write a pytest for the new function and commit it
> /quit
```

> **Local mode never calls Anthropic or any external AI API.** All inference
> runs on the Ollama container on this machine.

Switch to a different local model:

```bash
emr aider --model qwen2.5-coder:14b
```

### 4 — One-shot agent edits and auto-commits (`--message`)

Skip the interactive session and give the agent a single task:

```bash
cd ~/my-project
emr aider -- --message "Add a --dry-run flag to the CLI" --yes-always
emr aider -- --message "Write docstrings for every public function" --yes-always
emr aider -- --message "Refactor auth.py to use dataclasses" --yes-always
```

`--yes-always` skips confirmation prompts; the agent edits files and commits
automatically. Each run streams the model's reasoning and shows the diff before
committing.

**Demo task** (this is exactly what was run to wire `emr aider` into this repo):

```bash
cd /home/expert/edge-model-runtime
emr aider -- \
  --message "Add emr aider, systemd-install, systemd-uninstall, backup subcommands to bin/emr" \
  --yes-always
```

Output:
```
Model: openai/qwen2.5-coder:7b with whole edit format
Git repo: .git with 67 files
Applied edit to bin/emr
Commit 1ea9c41 feat(bin/emr): add aider, systemd-install, systemd-uninstall, and backup subcommands
```

### 5 — Cloud mode (LiteLLM → Anthropic)

When you need stronger reasoning, switch to cloud without changing anything else:

```bash
emr aider --cloud                           # interactive, claude-sonnet-4-6
emr aider --cloud -- --message "..." --yes-always   # one-shot
```

This routes through the local LiteLLM proxy (`edge-litellm:4000`) to Anthropic.
Requires `ANTHROPIC_API_KEY` and `LITELLM_MASTER_KEY` in `.env`.
Check LiteLLM is healthy: `curl -s http://localhost:4000/health/liveliness`

### 6 — OpenCode TUI (Codex-style, 100% local)

[OpenCode](https://github.com/opencode-dev/opencode) is a terminal UI similar
to Codex. It reads your repo, proposes edits, and runs `git` commands:

```bash
make codex
# or: emr setup opencode   (first-time setup, then: opencode)
```

Pointed at Ollama by default; select a model from the in-TUI dropdown.

### 7 — Claude Code TUI on local Ollama (Option D)

Run the official `claude` CLI but route it through LiteLLM → Ollama so no
Anthropic subscription is used:

```bash
make claude-local
# or: emr setup claude-local qwen2.5-coder:7b
```

### 8 — OpenHands web IDE

Browser-based agentic IDE — select a repo, type a task, and the agent clones,
edits, runs tests, commits, and pushes:

- **URL:** http://192.168.1.6:3030
- **Login:** no login screen (open access on LAN)
- `AGENTS_WEB_USER` / `AGENTS_WEB_PASS` in `.env` are legacy keys from a
  removed service — OpenHands itself has no authentication by default
- Set **LLM model** to `qwen2.5-coder` (local) or `claude-sonnet-4-6` (cloud)
  in OpenHands Settings → LLM
- **API key:** use `LITELLM_MASTER_KEY` from `.env`
- **Base URL:** `http://192.168.1.6:4000`

Start OpenHands:

```bash
emr setup coding-web
# or: docker compose --profile coding-web up -d openhands
```

### 9 — Validate your changes

After the agent edits and commits, always run:

```bash
make quick-check      # shellcheck + compose render + invariants
```

Check what changed:

```bash
git status
git log --oneline -5
git diff HEAD~1       # show last commit's diff
```

Push to remote:

```bash
git push origin main
```

### Quick-reference table

| Goal | Command |
|---|---|
| Interactive coding session (local) | `cd ~/repo && emr aider` |
| One-shot task + auto-commit (local) | `emr aider -- --message "..." --yes-always` |
| Interactive session (cloud) | `emr aider --cloud` |
| OpenCode TUI (Codex-like) | `make codex` |
| Claude Code TUI (local Ollama) | `make claude-local` |
| Claude Code TUI (cloud Anthropic) | `make claude-cloud` |
| OpenHands web IDE | `http://192.168.1.6:3030` |
| Pull a model | `emr pull qwen2.5-coder:7b` |
| List installed models | `emr models` |
| Validate changes | `make quick-check` |
| Backup `.env` secrets | `emr backup` |

---

## 🐛 Troubleshooting

See [`docs/TROUBLESHOOTING.md`](./docs/TROUBLESHOOTING.md).

Quick checks:
```bash
docker compose ps
docker compose logs ollama
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi
bash scripts/03-verify.sh
```

---

## 📜 License

MIT — see [LICENSE](./LICENSE)

---

## 🙏 Credits

Built on top of [Ollama](https://github.com/ollama/ollama), [Open WebUI](https://github.com/open-webui/open-webui), [vLLM](https://github.com/vllm-project/vllm), and the [NVIDIA Container Toolkit](https://github.com/NVIDIA/nvidia-container-toolkit).

## Local AI Coding Proof

This repository was safely edited by the local Ollama-powered AI coding workflow through emr aider.

Proof marker: LOCAL_AI_EDIT_PROOF_2026_OLLAMA_EMR_AIDER

See docs/LOCAL_AI_CODING_DEMO.md for the full local AI coding demo.
