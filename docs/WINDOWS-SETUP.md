# Windows Setup Guide (Native Ollama + Docker Desktop)

> **ภาษาไทย / Thai summary**: ติดตั้ง Ollama บน Windows โดยตรง + ใช้ Docker Desktop สำหรับ Open WebUI — ไม่ต้องการ WSL2 ไม่ต้อง Linux รองรับ Intel Arc GPU (เช่น Arc 140T) และ NVIDIA GPU บน Windows เช่นกัน

---

## Architecture

```
Windows host
├── ollama.exe          ← runs local LLMs, uses Intel Arc / NVIDIA / CPU
│   port 11434 (0.0.0.0)
│
└── Docker Desktop
    ├── edge-open-webui  :3000  ← browser UI, talks to ollama via host.docker.internal
    └── edge-litellm     :4000  ← optional cloud proxy (Claude / GPT / Gemini)
```

Models are stored directly on Windows at `%OLLAMA_MODELS%` (default: `%USERPROFILE%\.ollama\models`).

---

## Supported Hardware

| Machine | GPU | Notes |
|---|---|---|
| HP EliteBook (Intel Arc 140T) | Intel Arc (shared RAM) | Requires `OLLAMA_VULKAN=1` — run `win-tune-ollama.ps1` once to configure automatically |
| Any Windows 11 laptop/desktop | NVIDIA | Ollama.exe uses CUDA automatically |
| Any Windows machine | CPU only | Slower but works without a GPU |

---

## Prerequisites

| Tool | Version | Download |
|---|---|---|
| Windows 11 | 22H2+ | — |
| Docker Desktop | 4.20+ | https://www.docker.com/products/docker-desktop |
| Ollama for Windows | latest | https://ollama.com/download/windows |

---

## Step 1 — Install Ollama for Windows

1. Download and run the Ollama installer from https://ollama.com/download/windows
2. After install, Ollama runs as a background service (system tray icon).

**Allow Docker containers to reach Ollama:**

By default Ollama only listens on `127.0.0.1`. Docker containers need `0.0.0.0`.
Set this as a **System Environment Variable** (not user-level):

```
Variable name:  OLLAMA_HOST
Value:          0.0.0.0
```

How to set it (PowerShell as Administrator):
```powershell
[System.Environment]::SetEnvironmentVariable("OLLAMA_HOST", "0.0.0.0", "Machine")
```

Then **restart Ollama** (right-click tray icon → Quit, then relaunch).

Verify Ollama is reachable:
```powershell
curl http://localhost:11434/api/tags
```

---

## Step 2 — Set model storage path (optional)

Ollama stores models at `%USERPROFILE%\.ollama\models` by default (~6 GB per 7B model).
To move them to a drive with more space (e.g. `C:\ai-data\ollama\models`):

```powershell
[System.Environment]::SetEnvironmentVariable("OLLAMA_MODELS", "C:\ai-data\ollama\models", "Machine")
```

Restart Ollama after changing this.

---

## Step 3 — Install Docker Desktop

1. Download from https://www.docker.com/products/docker-desktop
2. Install with default settings (WSL2 backend is optional — not required for this setup)
3. Start Docker Desktop and wait for the whale icon to appear in the system tray

**Allow Docker to access your data drive:**

Docker Desktop → Settings → Resources → File Sharing → Add `C:\ai-data` (or wherever you set `AI_DATA_ROOT`).

---

## Step 4 — Clone the repo and configure

```powershell
git clone https://github.com/smallscaleserver/EdgeExpert.git
cd EdgeExpert

# Copy the Windows env template
Copy-Item .env.windows.example .env.windows
```

Edit `.env.windows` — minimum changes needed:
```ini
AI_DATA_ROOT=C:/ai-data          # must exist; use forward slashes
WEBUI_SECRET_KEY=any-random-string
```

Create the data directory:
```powershell
New-Item -ItemType Directory -Force "C:\ai-data\open-webui"
```

---

## Step 5 — Start Open WebUI

```powershell
# Core stack (Open WebUI only)
docker compose -f docker-compose.windows.yml --env-file .env.windows --env-file .env.versions up -d

# Or if make is installed (Git Bash / Chocolatey make):
make win-up
```

Open http://localhost:3000 — create your admin account on first launch.

---

## Step 6 — Pull a model

```powershell
# Pull directly via Ollama CLI (no Docker needed)
ollama pull qwen2.5-coder:7b

# Verify
ollama list
```

Recommended models for this machine (HP EliteBook, 64 GB RAM, Intel Arc 140T):

| Model | Size | Use |
|---|---|---|
| `qwen2.5-coder:7b` | ~4 GB | Coding, fast |
| `qwen2.5-coder:14b` | ~9 GB | Coding, better quality |
| `llama3.2:3b` | ~2 GB | General chat, very fast |
| `qwen2.5-coder:32b` | ~20 GB | Best quality, fits in 64 GB RAM |

> **Intel Arc 140T GPU note**: Ollama uses Intel Arc GPU via **Vulkan**. Vulkan support is experimental and **off by default** — you must set `OLLAMA_VULKAN=1` once (the `win-tune-ollama.ps1` script does this automatically). The Arc 140T exposes up to **36 GB** of shared system RAM as Vulkan VRAM, so models up to ~20 GB run entirely on GPU. Verify with `ollama ps` — the `PROCESSOR` column should show `100% GPU`.

---

## Step 7 — (Optional) Add cloud models via LiteLLM

To add Claude / GPT / Gemini to the same Open WebUI dropdown:

1. Add your API keys to `.env.windows`:
   ```ini
   ANTHROPIC_API_KEY=sk-ant-...
   LITELLM_MASTER_KEY=sk-changeme  # change this
   ```

2. Start with the cloud profile:
   ```powershell
   docker compose -f docker-compose.windows.yml --env-file .env.windows --env-file .env.versions --profile cloud up -d
   # or: make win-cloud
   ```

3. Cloud models (claude-sonnet-4-6, etc.) now appear in the Open WebUI model dropdown alongside local Ollama models.

---

## Daily operations

```powershell
# Start
make win-up
# or: docker compose -f docker-compose.windows.yml --env-file .env.windows --env-file .env.versions up -d

# Stop
make win-down
# or: docker compose -f docker-compose.windows.yml --env-file .env.windows --env-file .env.versions down

# Status
make win-status
# or: docker compose -f docker-compose.windows.yml --env-file .env.windows --env-file .env.versions ps

# Pull a new model
ollama pull <model-name>

# List installed models
ollama list

# Remove a model
ollama rm <model-name>
```

---

## Troubleshooting

### Open WebUI shows "Ollama not connected"
- Check Ollama is running: `curl http://localhost:11434/api/tags`
- Check `OLLAMA_HOST=0.0.0.0` is set as a Machine-level env var (not User-level)
- Restart Ollama after changing OLLAMA_HOST

### Docker can't write to AI_DATA_ROOT
- Docker Desktop → Settings → Resources → File Sharing — add the drive
- Use forward slashes in `.env.windows`: `C:/ai-data` not `C:\ai-data`

### Intel Arc GPU not being used by Ollama (shows "100% CPU" in `ollama ps`)

Ollama's Vulkan backend is **experimental and disabled by default**. Fix:

**Step 1 — Enable Vulkan and register the ICD (run once):**
```powershell
# Run the tuning script — it handles everything automatically:
powershell -ExecutionPolicy Bypass -File scripts\win-tune-ollama.ps1
```

Or manually:
```powershell
# 1. Enable Vulkan GPU backend
[System.Environment]::SetEnvironmentVariable("OLLAMA_VULKAN", "1", "User")

# 2. Find and register the Intel Arc Vulkan ICD
$icd = Get-ChildItem "C:\Windows\System32\DriverStore\FileRepository" -Filter "igvk64.json" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
[System.Environment]::SetEnvironmentVariable("VK_ICD_FILENAMES", $icd, "User")
New-Item "HKCU:\SOFTWARE\Khronos\Vulkan\Drivers" -Force | Out-Null
New-ItemProperty "HKCU:\SOFTWARE\Khronos\Vulkan\Drivers" -Name $icd -Value 0 -PropertyType DWORD -Force | Out-Null
```

**Step 2 — Restart Ollama** (right-click tray icon → Quit, then relaunch from Start menu)

**Step 3 — Verify:**
```powershell
ollama ps
# PROCESSOR column should show: 100% GPU
```

**Why this happens**: Intel Arc registers its Vulkan ICD via the Windows display-adapter registry path, not the traditional `HKLM\SOFTWARE\Khronos\Vulkan\Drivers` key that Ollama's bundled Vulkan loader reads. The fix above registers it in the user-level Khronos key and sets `VK_ICD_FILENAMES` as a fallback.

**Intel Arc driver requirement**: 31.0.101.x or later (driver 32.0.101.8508 confirmed working).

### Claude Code tool-use fails with local model (`model runner has unexpectedly stopped` or no file changes)

Two bugs in **Ollama ≤ 0.23.4** break Claude Code tool-use:

| Bug | Symptom | Root cause |
|---|---|---|
| Vulkan runner crash | `model runner has unexpectedly stopped` on every request | Experimental Vulkan backend OOMs / segfaults on long prompts (>800 tokens). Claude Code system prompt + tool defs = ~3000–5000 tokens. |
| Tool call format | Claude Code responds with text suggestions but makes no file changes | Ollama 0.23.4 does not convert Qwen's `<tool_call>` tags to OpenAI `tool_calls` JSON. Claude Code ignores text-format tool calls. |

**Fix: Upgrade Ollama.**

```powershell
# 1. Download latest Ollama installer for Windows from:
#    https://ollama.com/download/windows
#    then run the installer (it upgrades in-place, models are preserved)

# 2. After upgrade, verify version:
ollama --version   # should be > 0.23.4

# 3. Re-run GPU setup (in case the update reset env vars):
powershell -ExecutionPolicy Bypass -File "C:\Edge\edgeexpert\EdgeExpert\scripts\win-tune-ollama.ps1"
```

**While waiting to upgrade** (workaround using partial GPU + CPU fallback):
```powershell
# qwen2.5-coder-partial: 70% GPU, ~5 tok/s — stable for short prompts
# Automatic fallback to qwen2.5-coder-cpu if the GPU runner crashes
powershell -ExecutionPolicy Bypass -File "C:\Edge\edgeexpert\EdgeExpert\scripts\win-claude-local.ps1" -Model qwen2.5-coder-partial
```
Note: the workaround prevents the crash but tool calls may still return as text (no file edits) until Ollama is upgraded. The model will give you instructions you can run manually.

### LiteLLM returns `KeyError: 'arguments'` for local models

This is a bug in **LiteLLM 1.44.2**'s Ollama handler (`ollama.py:473`). Fixed in `litellm/config.windows.yaml` by using `openai/<model>` + `api_base: .../v1` instead of `ollama/<model>`. No action needed if using this repo's config.

### Port 3000 already in use
- Change `WEBUI_PORT=3001` in `.env.windows`

---

## Comparison: Windows mode vs Linux/WSL2 mode

| Feature | Windows (this guide) | Linux / WSL2 |
|---|---|---|
| Ollama | Native `.exe` | Docker container |
| GPU | Auto-detected by Ollama.exe | Via compose overlay (`GPU_DRIVER`) |
| Scripts (`scripts/*.sh`) | Not used | Full support |
| `make win-*` targets | ✅ | ❌ (use `make up` / `make down`) |
| Model storage | Windows path (`C:\...`) | Linux path (`/home/...`) |
| MSI EdgeXpert / DGX Spark | ❌ (use Linux mode) | ✅ |
