# =============================================================================
# win-setup.ps1 - One-shot setup for EdgeExpert (Windows-native Ollama mode)
# =============================================================================
# Usage (open PowerShell as Administrator):
#   cd C:\Edge\edgeexpert\EdgeExpert
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
#   .\scripts\win-setup.ps1
#
# What this script does:
#   1. Verify Ollama and Docker Desktop are installed and running
#   2. Set OLLAMA_HOST=0.0.0.0 (Machine-level)
#   3. Set OLLAMA_MODELS=C:\ai-data\ollama\models (move models off C:\Users)
#   4. Create folders C:\ai-data\open-webui and C:\ai-data\ollama\models
#   5. Verify .env.windows exists
#   6. Restart Ollama (so env vars take effect)
#   7. docker compose up -d (Open WebUI)
#   8. ollama pull qwen2.5-coder:7b
# =============================================================================

$ErrorActionPreference = "Stop"

function Write-Step($msg) {
    Write-Host ""
    Write-Host "==> $msg" -ForegroundColor Cyan
}

function Write-Ok($msg) {
    Write-Host "    [OK] $msg" -ForegroundColor Green
}

function Write-Warn($msg) {
    Write-Host "    [WARN] $msg" -ForegroundColor Yellow
}

function Write-Err($msg) {
    Write-Host "    [ERROR] $msg" -ForegroundColor Red
}

# --- 0. Must be Admin ------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
    [Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Err "Please run PowerShell as Administrator and re-run this script."
    exit 1
}
Write-Ok "Running as Administrator"

# --- 1. Check Ollama -------------------------------------------------------
Write-Step "Checking Ollama"
$ollama = Get-Command ollama -ErrorAction SilentlyContinue
if (-not $ollama) {
    Write-Err "ollama.exe not found. Install from https://ollama.com/download/windows first."
    Write-Host "    After installing, re-run this script."
    exit 1
}
Write-Ok "Ollama installed: $($ollama.Source)"

# --- 2. Check Docker Desktop -----------------------------------------------
Write-Step "Checking Docker Desktop"
$docker = Get-Command docker -ErrorAction SilentlyContinue
if (-not $docker) {
    Write-Err "docker not found. Install Docker Desktop from https://www.docker.com/products/docker-desktop first."
    exit 1
}
try {
    docker info 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Docker engine not running. Open Docker Desktop, wait for the whale icon to be steady, then re-run."
        exit 1
    }
} catch {
    Write-Err "Docker engine not responding: $_"
    exit 1
}
Write-Ok "Docker Desktop is running"

# --- 3. Set Environment Variables ------------------------------------------
Write-Step "Setting OLLAMA_HOST=0.0.0.0 (Machine)"
[System.Environment]::SetEnvironmentVariable("OLLAMA_HOST", "0.0.0.0", "Machine")
Write-Ok "OLLAMA_HOST=0.0.0.0"

Write-Step "Setting OLLAMA_MODELS=C:\ai-data\ollama\models (models off C:\Users)"
[System.Environment]::SetEnvironmentVariable("OLLAMA_MODELS", "C:\ai-data\ollama\models", "Machine")
Write-Ok "OLLAMA_MODELS=C:\ai-data\ollama\models"

# --- 4. Create data folders ------------------------------------------------
Write-Step "Creating C:\ai-data\open-webui and C:\ai-data\ollama\models"
New-Item -ItemType Directory -Force "C:\ai-data\open-webui"      | Out-Null
New-Item -ItemType Directory -Force "C:\ai-data\ollama\models"   | Out-Null
Write-Ok "Folders created"

# --- 5. Verify .env.windows ------------------------------------------------
Write-Step "Verifying .env.windows"
$envFile = Join-Path $PSScriptRoot "..\.env.windows"
if (-not (Test-Path $envFile)) {
    Write-Warn ".env.windows not found - copying from .env.windows.example"
    Copy-Item (Join-Path $PSScriptRoot "..\.env.windows.example") $envFile
}
Write-Ok ".env.windows OK"

# --- 6. Restart Ollama -----------------------------------------------------
Write-Step "Restarting Ollama so env vars take effect"
Get-Process -Name "ollama","ollama app" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Find ollama app.exe to restart
$ollamaApp = @(
    "$env:LOCALAPPDATA\Programs\Ollama\ollama app.exe",
    "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe",
    "$env:ProgramFiles\Ollama\ollama app.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($ollamaApp) {
    Start-Process -FilePath $ollamaApp -WindowStyle Hidden
    Start-Sleep -Seconds 5
    Write-Ok "Ollama restarted"
} else {
    Write-Warn "ollama app.exe not found - please start Ollama from the Start Menu manually."
}

# --- 7. Verify Ollama API --------------------------------------------------
Write-Step "Checking Ollama API at http://localhost:11434"
$ok = $false
for ($i = 0; $i -lt 15; $i++) {
    try {
        $r = Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        if ($r.StatusCode -eq 200) { $ok = $true; break }
    } catch { Start-Sleep -Seconds 2 }
}
if ($ok) { Write-Ok "Ollama API ready" } else { Write-Warn "Ollama API not responding - start Ollama from Start Menu and re-run if compose fails." }

# --- 8. Start Open WebUI ---------------------------------------------------
Write-Step "Starting Open WebUI via docker compose"
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    docker compose -f docker-compose.windows.yml --env-file .env.windows --env-file .env.versions up -d
    if ($LASTEXITCODE -ne 0) {
        Pop-Location
        Write-Err "docker compose failed"
        exit 1
    }
    Write-Ok "Open WebUI started - http://localhost:3000"
} catch {
    Pop-Location
    Write-Err "docker compose failed: $_"
    exit 1
}
Pop-Location

# --- 9. Pull model ---------------------------------------------------------
Write-Step "Pulling qwen2.5-coder:7b (~4.7 GB) - this takes 5-15 minutes"
ollama pull qwen2.5-coder:7b
if ($LASTEXITCODE -eq 0) {
    Write-Ok "qwen2.5-coder:7b ready"
} else {
    Write-Warn "Model pull failed - try running 'ollama pull qwen2.5-coder:7b' manually."
}

# --- 10. Summary -----------------------------------------------------------
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  Setup complete!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Open in your browser:  http://localhost:3000"
Write-Host "  Create the first admin account (email/password is stored locally)."
Write-Host ""
Write-Host "  Daily commands:"
Write-Host "    docker compose -f docker-compose.windows.yml --env-file .env.windows --env-file .env.versions ps    # status"
Write-Host "    docker compose -f docker-compose.windows.yml --env-file .env.windows --env-file .env.versions down  # stop"
Write-Host "    ollama list                                                                                          # list models"
Write-Host "    ollama pull qwen2.5-coder:14b                                                                        # bigger model"
Write-Host ""
