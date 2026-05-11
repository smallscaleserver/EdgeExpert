#!/usr/bin/env bash
# =============================================================================
# 00-install.sh — first-time setup
# =============================================================================
# - Creates host data directories with safe permissions
# - Generates .env from .env.example and a fresh WEBUI_SECRET_KEY
# - Pulls core Docker images (Ollama + Open WebUI)
# - Tests GPU access
# - Starts core services
# - Idempotent: safe to re-run
# =============================================================================

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"
# shellcheck source=lib/manifest.sh
source "$(dirname "$0")/lib/manifest.sh"

# --no-cli-symlink — skip the optional /usr/local/bin/emr install step.
INSTALL_EMR_SYMLINK=1
for arg in "$@"; do
  case "$arg" in
    --no-cli-symlink) INSTALL_EMR_SYMLINK=0 ;;
  esac
done

section "🚀 edge-model-runtime — install"

# --- 1. Preflight ------------------------------------------------------------
check_docker
check_compose_v2
ok "Docker $(docker --version | awk '{print $3}' | tr -d ',')"
ok "Compose $(docker compose version --short)"

# --- 2. .env -----------------------------------------------------------------
if [[ ! -f "$REPO_ROOT/.env" ]]; then
  info "Creating .env from .env.example"
  cp "$REPO_ROOT/.env.example" "$REPO_ROOT/.env"
  ok ".env created"
else
  ok ".env already exists (keeping it)"
fi

# --- 3. WEBUI_SECRET_KEY -----------------------------------------------------
if grep -qE '^WEBUI_SECRET_KEY=$' "$REPO_ROOT/.env" 2>/dev/null; then
  info "Generating WEBUI_SECRET_KEY"
  SECRET="$(openssl rand -hex 32)"
  # macOS-safe sed in-place
  if sed --version >/dev/null 2>&1; then
    sed -i "s|^WEBUI_SECRET_KEY=$|WEBUI_SECRET_KEY=${SECRET}|" "$REPO_ROOT/.env"
  else
    sed -i '' "s|^WEBUI_SECRET_KEY=$|WEBUI_SECRET_KEY=${SECRET}|" "$REPO_ROOT/.env"
  fi
  ok "WEBUI_SECRET_KEY generated"
else
  ok "WEBUI_SECRET_KEY already set"
fi

# --- 4. Load env -------------------------------------------------------------
load_env
: "${AI_DATA_ROOT:?AI_DATA_ROOT must be set in .env}"

# --- 5. Data directories -----------------------------------------------------
section "📁 Preparing data directories"
info "AI_DATA_ROOT = $AI_DATA_ROOT"

# Use sudo only if needed (parent dir not owned by current user)
parent_dir="$(dirname "$AI_DATA_ROOT")"
if [[ ! -d "$AI_DATA_ROOT" ]]; then
  if [[ -w "$parent_dir" ]]; then
    mkdir -p "$AI_DATA_ROOT"
  else
    info "Parent directory needs sudo to create $AI_DATA_ROOT"
    sudo mkdir -p "$AI_DATA_ROOT"
    sudo chown "$USER:$USER" "$AI_DATA_ROOT"
  fi
fi

# Subdirs
for d in ollama open-webui hf-cache training logs; do
  mkdir -p "$AI_DATA_ROOT/$d"
done

# Tighten permissions (no chmod 777!)
chmod -R u+rwX,g+rwX,o-rwx "$AI_DATA_ROOT" 2>/dev/null || \
  warn "Could not chmod some files (may be owned by root from container). Continuing."

ok "Data directories ready under $AI_DATA_ROOT"

# --- 6. Pull core images -----------------------------------------------------
section "📦 Pulling core Docker images"
: "${OLLAMA_IMAGE:?OLLAMA_IMAGE missing in .env.versions}"
: "${OPEN_WEBUI_IMAGE:?OPEN_WEBUI_IMAGE missing in .env.versions}"

# For Intel GPU mode, pull the ipex-llm image instead of stock Ollama.
# For NVIDIA mode, also pull the CUDA test image for the GPU sanity check.
GPU_DRIVER="${GPU_DRIVER:-cpu}"
case "$GPU_DRIVER" in
  nvidia)
    : "${CUDA_TEST_IMAGE:?CUDA_TEST_IMAGE missing in .env.versions}"
    docker pull "$OLLAMA_IMAGE"
    docker pull "$CUDA_TEST_IMAGE"
    ;;
  intel)
    : "${OLLAMA_INTEL_IMAGE:?OLLAMA_INTEL_IMAGE missing in .env.versions}"
    docker pull "$OLLAMA_INTEL_IMAGE"
    ;;
  cpu|*)
    docker pull "$OLLAMA_IMAGE"
    ;;
esac
docker pull "$OPEN_WEBUI_IMAGE"
ok "Images pulled"

info "vLLM and training images are NOT pulled here (large). Pull on demand:"
info "  docker compose --profile vllm pull vllm"
info "  docker compose --profile training pull training"

# --- 7. GPU sanity check -----------------------------------------------------
section "🎮 GPU check (GPU_DRIVER=${GPU_DRIVER})"
case "$GPU_DRIVER" in
  nvidia)
    if docker run --rm --gpus all "$CUDA_TEST_IMAGE" nvidia-smi >/dev/null 2>&1; then
      gpu_count="$(docker run --rm --gpus all "$CUDA_TEST_IMAGE" nvidia-smi -L | wc -l)"
      ok "NVIDIA GPU OK — $gpu_count device(s) visible"
    else
      warn "NVIDIA GPU not accessible from Docker. Check NVIDIA Container Toolkit:"
      warn "  https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html"
      warn "Containers will fall back to CPU (much slower)."
    fi
    ;;
  intel)
    if ls /dev/dri/renderD128 >/dev/null 2>&1; then
      ok "Intel GPU device found: /dev/dri/renderD128"
    else
      warn "/dev/dri/renderD128 not found."
      warn "On WSL2: ensure GPU-PV is enabled (Windows 11 + Intel Arc driver 31.0.101.x+)"
      warn "  and run 'wsl --update' to get a recent WSL2 kernel."
      warn "Ollama will run CPU-only until the device is accessible."
    fi
    ;;
  cpu)
    ok "CPU-only mode — no GPU acceleration (expected for GPU_DRIVER=cpu)"
    ;;
  *)
    warn "Unknown GPU_DRIVER='$GPU_DRIVER'. Valid values: cpu | nvidia | intel"
    ;;
esac

# --- 8. Start core stack -----------------------------------------------------
section "🐳 Starting core services"
compose up -d ollama open-webui

# --- 9. Wait for Ollama ------------------------------------------------------
info "Waiting for Ollama to be ready..."
for i in $(seq 1 30); do
  if curl -sf "http://localhost:${OLLAMA_PORT:-11434}/api/tags" >/dev/null 2>&1; then
    ok "Ollama is responding"
    break
  fi
  if [[ $i -eq 30 ]]; then
    warn "Ollama did not respond within 60s. Check: docker compose logs ollama"
  fi
  sleep 2
done

# --- 10. Optional: install the `emr` CLI dispatcher --------------------------
# Symlink bin/emr into /usr/local/bin so users can type `emr <cmd>` from any
# directory (Claude Code / Codex feel). Falls back to ~/.local/bin if neither
# /usr/local/bin nor sudo are available. Tracked in the manifest so a Tier 3
# uninstall removes it.
install_emr_symlink() {
  local src="$REPO_ROOT/bin/emr" target dir sudo_cmd=""
  [[ -x "$src" ]] || { warn "bin/emr is not executable in this checkout — skipping symlink"; return; }

  if [[ -w /usr/local/bin ]]; then
    dir="/usr/local/bin"
  elif command -v sudo >/dev/null 2>&1; then
    dir="/usr/local/bin"
    sudo_cmd="sudo"
  else
    dir="$HOME/.local/bin"
    mkdir -p "$dir"
  fi
  target="$dir/emr"

  if [[ -L "$target" && "$(readlink -f "$target")" == "$(readlink -f "$src")" ]]; then
    ok "emr already linked: $target"
  else
    if [[ -e "$target" || -L "$target" ]]; then
      info "Replacing existing $target"
      if [[ -n "$sudo_cmd" ]]; then $sudo_cmd rm -f "$target"; else rm -f "$target"; fi
    fi
    if [[ -n "$sudo_cmd" ]]; then
      $sudo_cmd ln -s "$src" "$target"
    else
      ln -s "$src" "$target"
    fi
    ok "emr installed: $target  →  $src"
  fi
  manifest_add_path "$target"
  warn_if_not_on_path "$dir"
}

if (( INSTALL_EMR_SYMLINK )); then
  section "🔗 Installing emr CLI"
  install_emr_symlink
fi

# --- 11. Done ----------------------------------------------------------------
section "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ok "Installation complete"
section "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cat <<EOF

🌐 Open WebUI:  http://localhost:${WEBUI_PORT:-3000}
🔌 Ollama API:  http://localhost:${OLLAMA_PORT:-11434}

Next steps:
  emr pull qwen2.5-coder:7b      (or: bash scripts/04-pull-model.sh ...)
  emr models                     (or: bash scripts/05-list-models.sh)
  emr status                     (or: bash scripts/03-verify.sh)
  emr help                       (full subcommand list)

EOF
