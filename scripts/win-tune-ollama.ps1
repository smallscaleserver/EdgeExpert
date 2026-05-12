# =============================================================================
# scripts\win-tune-ollama.ps1 - Tune Ollama for Intel Arc + Core Ultra 7 265H
# =============================================================================
# Sets persistent User-scope env vars and optionally upgrades Ollama.
# Run once as the user who runs Ollama (no admin needed for User scope).
#
# What this does:
#   OLLAMA_FLASH_ATTENTION=1    faster attention, less memory usage
#   OLLAMA_NUM_THREAD=16        use all 16 logical processors
#   OLLAMA_CONTEXT_LENGTH=32768 long context for agentic coding (vs default 4096)
#   OLLAMA_INTEL_GPU=1          hint to enable Intel Arc GPU offload
#   OLLAMA_GPU_OVERHEAD=0       let Ollama use all detected VRAM
#
# After running: restart Ollama from Start Menu, then verify with:
#   Invoke-RestMethod http://localhost:11434/api/ps
#   (size_vram should be non-zero if GPU is being used)
# =============================================================================

param(
    [switch]$Upgrade   # also upgrade Ollama to latest version via winget
)

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

$vars = @{
    OLLAMA_FLASH_ATTENTION = "1"       # faster attention kernel
    OLLAMA_NUM_THREAD      = "16"      # all logical processors (Core Ultra 7 265H)
    OLLAMA_CONTEXT_LENGTH  = "32768"   # 32k context for multi-file agentic tasks
    OLLAMA_INTEL_GPU       = "1"       # enable Intel Arc GPU acceleration
    OLLAMA_GPU_OVERHEAD    = "0"       # use all available VRAM (Arc 140T 32GB shared)
    OLLAMA_MAX_LOADED_MODELS = "1"     # keep one model fully loaded, avoid thrashing
    OLLAMA_KEEP_ALIVE      = "30m"     # keep model warm between requests
}

Write-Host ""
Write-Host "  Ollama tuning for Intel Arc 140T + Core Ultra 7 265H" -ForegroundColor Cyan
Write-Host ""

foreach ($key in $vars.Keys) {
    $current = [System.Environment]::GetEnvironmentVariable($key, 'User')
    [System.Environment]::SetEnvironmentVariable($key, $vars[$key], 'User')
    if ($current -and $current -ne $vars[$key]) {
        Write-Host "  $key  $current -> $($vars[$key])" -ForegroundColor Yellow
    } else {
        Write-Host "  $key = $($vars[$key])" -ForegroundColor Green
    }
}

Write-Host ""

if ($Upgrade) {
    Write-Host "  Upgrading Ollama via winget..." -ForegroundColor Cyan
    winget upgrade Ollama.Ollama --accept-source-agreements --accept-package-agreements 2>&1
    Write-Host ""
}

Write-Host "  Done. Next steps:" -ForegroundColor Green
Write-Host "  1. Quit Ollama from system tray (right-click -> Quit)" -ForegroundColor White
Write-Host "  2. Reopen Ollama from Start Menu" -ForegroundColor White
Write-Host "  3. Verify GPU is used:" -ForegroundColor White
Write-Host "     Invoke-RestMethod http://localhost:11434/api/ps" -ForegroundColor DarkGray
Write-Host "     (size_vram > 0 means GPU is active)" -ForegroundColor DarkGray
Write-Host ""
