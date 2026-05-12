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
$persistVars = @{
    OLLAMA_FLASH_ATTENTION   = "1"    # faster attention kernel
    OLLAMA_NUM_PARALLEL      = "1"    # one request at a time, all resources to it
    OLLAMA_MAX_LOADED_MODELS = "1"    # one model fully resident
    OLLAMA_KEEP_ALIVE        = "30m"  # keep model warm between requests
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

    $modelfile = "FROM $($m.tag)`nPARAMETER num_ctx 32768`nPARAMETER num_thread 16"
    $tmpFile = "$tmpDir\$($m.name -replace ':','-').modelfile"
    Set-Content -Path $tmpFile -Value $modelfile -Encoding UTF8

    Write-Host "  Creating $($m.name)-32k ..." -ForegroundColor Cyan
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
