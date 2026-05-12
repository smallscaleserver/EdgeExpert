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
    [string]$Model      = "",           # default depends on mode: claude-sonnet-4-6 (direct) or qwen2.5-coder (local)
    [string]$LiteLLMUrl = "http://localhost:4000",
    [string]$ApiKey     = "sk-local",
    [switch]$Direct     # bypass LiteLLM - use real Anthropic API directly
)

# Set model default based on mode if not explicitly provided
if ($Model -eq "") {
    $Model = if ($Direct) { "claude-sonnet-4-6" } else { "qwen2.5-coder" }
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

$env:ANTHROPIC_BASE_URL = $LiteLLMUrl
$env:ANTHROPIC_API_KEY  = $ApiKey

claude --model $Model
