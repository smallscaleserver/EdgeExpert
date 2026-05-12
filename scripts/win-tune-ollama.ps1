# =============================================================================
# scripts\win-tune-ollama.ps1 - Tune Ollama for Intel Arc + Core Ultra 7 265H
# =============================================================================
# 1. Sets Ollama env vars (flash attention, threads, keep-alive)
# 2. Restarts `ollama serve` so vars take effect immediately
# 3. Creates custom Modelfiles with num_ctx=32768 for coding models
#
# Context length cannot be set globally via env var - must be in a Modelfile
# or passed per-request via {"options": {"num_ctx": 32768}}.
#
# Intel Arc GPU: not supported in standard Ollama Windows build (CUDA/ROCm only).
# CPU-only with flash attention + 16 threads is the practical max here.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts\win-tune-ollama.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\win-tune-ollama.ps1 -Upgrade
# =============================================================================

param(
    [switch]$Upgrade
)

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

$ollamaExe = "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe"
if (-not (Test-Path $ollamaExe)) {
    Write-Host "[ERROR] Ollama not found at $ollamaExe" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "  Ollama tuning for Intel Arc 140T + Core Ultra 7 265H" -ForegroundColor Cyan
Write-Host ""

if ($Upgrade) {
    Write-Host "  Checking for Ollama update..." -ForegroundColor Cyan
    winget upgrade Ollama.Ollama --accept-source-agreements --accept-package-agreements 2>&1
    Write-Host ""
}

# --- Step 1: persist env vars to User registry (survives reboots) ----------
# Thread budget: 16 logical processors on Core Ultra 7 265H
#    8 for Ollama  -> model runs steadily
#    8 for Windows OS, UI, Docker, browser -> machine stays responsive
# RAM is not limited - user has 64GB and is fine using most of it.
$persistVars = @{
    OLLAMA_FLASH_ATTENTION   = "1"    # faster attention, less RAM usage
    OLLAMA_NUM_THREAD        = "8"    # 8 threads: inference runs, OS stays smooth
    OLLAMA_NUM_PARALLEL      = "1"    # one request at a time, all 8 threads to it
    OLLAMA_MAX_LOADED_MODELS = "1"    # one model resident, no thrashing
    OLLAMA_KEEP_ALIVE        = "60m"  # keep model warm 60 min
}

Write-Host "  Persisting env vars..." -ForegroundColor Yellow
foreach ($key in $persistVars.Keys) {
    [System.Environment]::SetEnvironmentVariable($key, $persistVars[$key], 'User')
    [System.Environment]::SetEnvironmentVariable($key, $persistVars[$key], 'Process')
    Write-Host "  $key = $($persistVars[$key])" -ForegroundColor Green
}

# --- Step 2: restart ollama serve with vars injected -----------------------
Write-Host ""
Write-Host "  Restarting ollama serve..." -ForegroundColor Yellow
Get-Process -Name "ollama*" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 3

# Detect where model blobs actually live and fix OLLAMA_MODELS if wrong.
# The registry may point to C:\ai-data\ollama\models (empty) while the real
# blobs are in the default ~/.ollama/models — correct it automatically.
$registryPath = [System.Environment]::GetEnvironmentVariable('OLLAMA_MODELS', 'User')
if (-not $registryPath) { $registryPath = [System.Environment]::GetEnvironmentVariable('OLLAMA_MODELS', 'Machine') }
$defaultPath  = "$env:USERPROFILE\.ollama\models"
$aiDataPath   = "C:\ai-data\ollama\models"

# Pick path where blobs actually exist
if (Test-Path "$defaultPath\blobs") {
    $actualPath = $defaultPath
} elseif ($registryPath -and (Test-Path "$registryPath\blobs")) {
    $actualPath = $registryPath
} else {
    $actualPath = $defaultPath  # fallback
}

if ($registryPath -ne $actualPath) {
    Write-Host "  Fixing OLLAMA_MODELS: $registryPath -> $actualPath" -ForegroundColor Yellow
    [System.Environment]::SetEnvironmentVariable('OLLAMA_MODELS', $actualPath, 'User')
    [System.Environment]::SetEnvironmentVariable('OLLAMA_MODELS', $actualPath, 'Machine')
}
[System.Environment]::SetEnvironmentVariable('OLLAMA_MODELS', $actualPath, 'Process')
Write-Host "  OLLAMA_MODELS = $actualPath" -ForegroundColor Green

# Start serve directly (not the tray app) so env vars are inherited
Start-Process -FilePath $ollamaExe -ArgumentList "serve" -WindowStyle Hidden
Start-Sleep -Seconds 5

try {
    $status = Invoke-RestMethod http://localhost:11434/ -TimeoutSec 5
    Write-Host "  Ollama serve: $status" -ForegroundColor Green
} catch {
    Write-Host "  [WARN] Ollama not responding yet, wait a few seconds" -ForegroundColor Yellow
}

# --- Step 3: create Modelfiles with 32k context ----------------------------
Write-Host ""
Write-Host "  Creating 32k-context Modelfiles..." -ForegroundColor Yellow

$models = @(
    @{ tag = "qwen2.5-coder:7b";  name = "qwen2.5-coder" },
    @{ tag = "qwen2.5-coder:14b"; name = "qwen2.5-coder:14b" },
    @{ tag = "qwen2.5-coder:32b"; name = "qwen2.5-coder:32b" },
    @{ tag = "devstral:latest";   name = "devstral" },
    @{ tag = "qwen3:14b";         name = "qwen3:14b" },
    @{ tag = "qwen3:32b";         name = "qwen3:32b" },
    @{ tag = "deepseek-coder-v2:16b"; name = "deepseek-coder-v2:16b" }
)

$tmpDir = "$env:TEMP\ollama-modelfiles"
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null

foreach ($m in $models) {
    # Check if base model exists locally
    $check = Invoke-RestMethod http://localhost:11434/api/tags -ErrorAction SilentlyContinue
    $exists = $check.models | Where-Object { $_.name -eq $m.tag }
    if (-not $exists) {
        Write-Host "  SKIP $($m.name) (not pulled yet)" -ForegroundColor DarkGray
        continue
    }

    # 32k context: full RAM budget (user has 64GB, RAM is not a concern)
    # num_thread=8: 8 threads for inference, 8 left for OS/UI
    $modelfile = "FROM $($m.tag)`nPARAMETER num_ctx 32768`nPARAMETER num_thread 8"
    $tmpFile = "$tmpDir\$($m.name -replace ':','-').modelfile"
    Set-Content -Path $tmpFile -Value $modelfile -Encoding UTF8

    Write-Host "  Creating $($m.name)-32k (32k ctx, 8 threads) ..." -ForegroundColor Cyan
    & $ollamaExe create "$($m.name)-32k" -f $tmpFile 2>&1 | Where-Object { $_ -match "success|error|Error" }
}

Write-Host ""
Write-Host "  Done. Use models with '-32k' suffix for 32k context:" -ForegroundColor Green
Write-Host "  powershell -File scripts\win-claude-local.ps1 -Model devstral-32k" -ForegroundColor White
Write-Host "  powershell -File scripts\win-claude-local.ps1 -Model qwen2.5-coder-32k" -ForegroundColor White
Write-Host ""
Write-Host "  Verify context after loading a model:" -ForegroundColor Cyan
Write-Host '  (Invoke-RestMethod http://localhost:11434/api/ps).models | Select name,context_length' -ForegroundColor DarkGray
Write-Host ""
