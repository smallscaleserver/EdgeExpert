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
#   C:\Edge\edgeexpert\EdgeExpert\scripts\win-claude-local.ps1
#
# Or from the EdgeExpert repo:
#   make win-claude
# =============================================================================

param(
    [string]$Model = "qwen2.5-coder",
    [string]$LiteLLMUrl = "http://localhost:4000",
    [string]$ApiKey = "sk-changeme"
)

# Read LITELLM_MASTER_KEY and model from .env.windows if present
$envFile = Join-Path $PSScriptRoot "..\env.windows" -Resolve -ErrorAction SilentlyContinue
if (-not $envFile) {
    $envFile = Join-Path $PSScriptRoot "..\.env.windows"
}
if (Test-Path $envFile) {
    foreach ($line in Get-Content $envFile) {
        if ($line -match "^LITELLM_MASTER_KEY=(.+)") { $ApiKey  = $matches[1].Trim() }
        if ($line -match "^LITELLM_PORT=(\d+)")       { $LiteLLMUrl = "http://localhost:$($matches[1].Trim())" }
    }
}

# Check LiteLLM is reachable
try {
    $null = Invoke-RestMethod -Uri "$LiteLLMUrl/health/liveliness" -TimeoutSec 3
} catch {
    Write-Host "[ERROR] LiteLLM is not running at $LiteLLMUrl" -ForegroundColor Red
    Write-Host "  Start it first:  make win-cloud" -ForegroundColor Yellow
    Write-Host "  Or from repo root:" -ForegroundColor Yellow
    Write-Host "  docker compose -f docker-compose.windows.yml --env-file .env.windows --env-file .env.versions --profile cloud up -d" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "  Claude Code  →  LiteLLM ($LiteLLMUrl)  →  Ollama (local)" -ForegroundColor Cyan
Write-Host "  Model: $Model" -ForegroundColor Cyan
Write-Host "  Press Ctrl+C to exit" -ForegroundColor DarkGray
Write-Host ""

# Launch claude pointed at LiteLLM
$env:ANTHROPIC_BASE_URL = $LiteLLMUrl
$env:ANTHROPIC_API_KEY  = $ApiKey

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
claude --model $Model
