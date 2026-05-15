# =============================================================================
# scripts\win-claude-local.ps1 — Claude Code TUI using local Ollama model
# =============================================================================
# Routes the claude CLI through LiteLLM (Docker) → Ollama (Windows host).
# No Anthropic subscription used — inference runs 100% locally.
#
# Prerequisites:
#   make win-cloud     (starts LiteLLM + Open WebUI)
#   ollama pull qwen2.5-coder:7b
#
# GPU acceleration (Intel Arc 140T):
#   Ollama uses Vulkan for Intel Arc GPU on Windows.
#   OLLAMA_VULKAN=1 and VK_ICD_FILENAMES are set persistently in the user
#   environment by this script if not already configured.
#   The script will warn and optionally restart Ollama if a model is running
#   on CPU when GPU is available.
#
# Usage (from any git repo):
#   cd C:\your\repo
#
#   # Local AI (no login needed):
#   C:\Edge\edgeexpert\EdgeExpert\scripts\win-claude-local.ps1
#   C:\Edge\edgeexpert\EdgeExpert\scripts\win-claude-local.ps1 -Model qwen2.5-coder-large
#
#   # Real Anthropic API (login or API key):
#   C:\Edge\edgeexpert\EdgeExpert\scripts\win-claude-local.ps1 -Direct
#   C:\Edge\edgeexpert\EdgeExpert\scripts\win-claude-local.ps1 -Direct -Model claude-sonnet-4-6
#
# Or from the EdgeExpert repo:
#   make win-claude          # local Ollama
#   make win-claude-direct   # real Anthropic API
# =============================================================================

param(
    [string]$Model      = "",           # default depends on mode: claude-sonnet-4-6 (direct) or qwen2.5-coder-partial (local)
    [string]$LiteLLMUrl = "http://localhost:4000",
    [string]$ApiKey     = "sk-local",
    [switch]$Direct     # bypass LiteLLM - use real Anthropic API directly
)

# Set model default based on mode if not explicitly provided
if ($Model -eq "") {
    # qwen2.5-coder-partial: 70% GPU / 30% CPU hybrid — stable for long prompts.
    # LiteLLM fallback auto-switches to qwen2.5-coder-cpu if the model fails.
    $Model = if ($Direct) { "claude-sonnet-4-6" } else { "qwen2.5-coder-partial" }
}

# Read overrides from .env.windows if present
$envFile = Join-Path $PSScriptRoot "..\env.windows" -Resolve -ErrorAction SilentlyContinue
if (-not $envFile) {
    $envFile = Join-Path $PSScriptRoot "..\.env.windows"
}
$RealAnthropicKey = ""
if (Test-Path $envFile) {
    foreach ($line in Get-Content $envFile) {
        if ($line -match "^LITELLM_PORT=(\d+)")     { $LiteLLMUrl       = "http://localhost:$($matches[1].Trim())" }
        if ($line -match "^ANTHROPIC_API_KEY=(.+)") { $RealAnthropicKey = $matches[1].Trim() }
    }
}

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# UTF-8 — ป้องกันภาษาไทยแสดงเป็น garbage characters ใน Terminal
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 | Out-Null
$env:PYTHONIOENCODING = "utf-8"

# ==========================================================================
# Intel Arc GPU — ensure Vulkan acceleration is configured for Ollama
# ==========================================================================
# OLLAMA_VULKAN=1 enables experimental Vulkan GPU support (off by default).
# VK_ICD_FILENAMES tells the Vulkan loader where the Intel Arc ICD lives
# (needed because Intel Arc registers its ICD via the display-adapter
# registry path, which older Vulkan loaders don't scan).
$_intelVulkanIcd = "C:\Windows\System32\DriverStore\FileRepository\iigd_dch.inf_amd64_76787e203cb9b607\igvk64.json"

function _EnsureGpuEnv {
    $changed = $false
    if ([System.Environment]::GetEnvironmentVariable("OLLAMA_VULKAN", "User") -ne "1") {
        [System.Environment]::SetEnvironmentVariable("OLLAMA_VULKAN", "1", "User")
        Write-Host "  [GPU] Set OLLAMA_VULKAN=1 (user env)" -ForegroundColor DarkGray
        $changed = $true
    }
    if ((Test-Path $_intelVulkanIcd) -and ([System.Environment]::GetEnvironmentVariable("VK_ICD_FILENAMES", "User") -ne $_intelVulkanIcd)) {
        [System.Environment]::SetEnvironmentVariable("VK_ICD_FILENAMES", $_intelVulkanIcd, "User")
        # Also register in HKCU so all Vulkan loaders find the ICD
        $regKey = "HKCU:\SOFTWARE\Khronos\Vulkan\Drivers"
        New-Item -Path $regKey -Force -ErrorAction SilentlyContinue | Out-Null
        New-ItemProperty -Path $regKey -Name $_intelVulkanIcd -Value 0 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
        Write-Host "  [GPU] Set VK_ICD_FILENAMES (user env + HKCU registry)" -ForegroundColor DarkGray
        $changed = $true
    }
    # Apply to current process so child processes inherit
    $env:OLLAMA_VULKAN    = "1"
    $env:VK_ICD_FILENAMES = $_intelVulkanIcd
    return $changed
}

function _CheckOllamaGpu {
    # Skip GPU check for CPU-only models — they intentionally run on CPU
    if ($Model -match "-cpu$") { return }
    try {
        $psLines = ollama ps 2>$null
        # Only act if at least one model row is loaded (more than just the header line)
        $dataLines = ($psLines -split "`n") | Where-Object { $_ -match "\S" -and $_ -notmatch "^NAME\s" }
        if (-not $dataLines) { return }
        $psText = $psLines -join " "
        if ($psText -match "100% CPU") {
            Write-Host ""
            Write-Host "  [GPU] WARNING: Ollama model is running on CPU, not GPU." -ForegroundColor Yellow
            Write-Host "  [GPU] Restart Ollama (tray icon -> Quit, then relaunch) to apply GPU settings." -ForegroundColor Yellow
            Write-Host "  [GPU] After restarting, run this script again." -ForegroundColor Yellow
        } elseif ($psText -match "GPU") {
            Write-Host "  [GPU] Ollama is using GPU acceleration." -ForegroundColor Green
        }
    } catch {}
}

$_gpuChanged = _EnsureGpuEnv
if ($_gpuChanged) {
    Write-Host "  [GPU] Intel Arc Vulkan settings applied. Restart Ollama if it was already running." -ForegroundColor Yellow
}

# ==========================================================================
# DIRECT mode — real Anthropic API (login session or API key)
# ==========================================================================
if ($Direct) {
    Write-Host ""
    Write-Host "  Claude Code -> Anthropic API (direct)" -ForegroundColor Green

    if ($RealAnthropicKey) {
        $env:ANTHROPIC_API_KEY = $RealAnthropicKey
        Write-Host "  Using ANTHROPIC_API_KEY from .env.windows" -ForegroundColor Cyan
    } else {
        # No API key — rely on saved /login session token
        Remove-Item Env:\ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
        Write-Host "  No ANTHROPIC_API_KEY found - using saved login session (/login if needed)" -ForegroundColor Yellow
    }

    # Make sure we are NOT pointing at LiteLLM
    Remove-Item Env:\ANTHROPIC_BASE_URL -ErrorAction SilentlyContinue

    Write-Host "  Model: $Model" -ForegroundColor Cyan
    Write-Host "  Press Ctrl+C to exit" -ForegroundColor DarkGray
    Write-Host ""

    claude --model $Model
    return
}

# ==========================================================================
# LOCAL mode — LiteLLM → Ollama (no Anthropic account needed)
# ==========================================================================

# Check LiteLLM is reachable
try {
    $null = Invoke-RestMethod -Uri "$LiteLLMUrl/health/liveliness" -TimeoutSec 3
} catch {
    Write-Host "[ERROR] LiteLLM is not running at $LiteLLMUrl" -ForegroundColor Red
    Write-Host "  Start it first:  make win-cloud" -ForegroundColor Yellow
    Write-Host "  Or:" -ForegroundColor Yellow
    Write-Host "  docker compose -f docker-compose.windows.yml --env-file .env.windows --env-file .env.versions --profile cloud up -d" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "  Claude Code -> LiteLLM ($LiteLLMUrl) -> Ollama (local)" -ForegroundColor Cyan
Write-Host "  Model: $Model" -ForegroundColor Cyan
Write-Host "  Press Ctrl+C to exit" -ForegroundColor DarkGray
Write-Host ""

_CheckOllamaGpu

$env:ANTHROPIC_BASE_URL = $LiteLLMUrl
$env:ANTHROPIC_API_KEY  = $ApiKey

claude --model $Model
