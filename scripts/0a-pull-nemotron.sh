#!/usr/bin/env bash
# =============================================================================
# 0a-pull-nemotron.sh — pull an NVIDIA Nemotron model via Ollama
# =============================================================================
# Usage: bash scripts/0a-pull-nemotron.sh [variant]
#   variant ∈ {mini, nano, nano-omni, super, cascade, 70b}  (default: nano)
# =============================================================================

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

VARIANT="${1:-nano}"

print_table() {
  cat <<'EOF'
Variant      Ollama tag             Active params       VRAM (rough)   Best for
-----------  ---------------------  ------------------  -------------  -----------------------------------
mini         nemotron-mini          4B                  ~6 GB          edge, function calling, low VRAM
nano         nemotron-3-nano        3.5B / 30B MoE      ~20 GB         default agent / reasoning
nano-omni    nemotron3:33b          multimodal 33B      ~24 GB         OCR, video+audio+image+text
super        nemotron-3-super       12B / 120B MoE      ~80 GB         strong reasoning, IT automation
cascade      nemotron-cascade-2     3B / 30B MoE        ~20 GB         agentic, low active params
70b          nemotron               70B (Llama-3.1)     ~48 GB (q4)    RLHF helpfulness, big GPU

Model cards: https://ollama.com/library  (search "nemotron")
NVIDIA hub:  https://developer.nvidia.com/nemotron
EOF
}

case "$VARIANT" in
  mini)       TAG="nemotron-mini";       VRAM="~6 GB" ;;
  nano)       TAG="nemotron-3-nano";     VRAM="~20 GB" ;;
  nano-omni)  TAG="nemotron3:33b";       VRAM="~24 GB" ;;
  super)      TAG="nemotron-3-super";    VRAM="~80 GB" ;;
  cascade)    TAG="nemotron-cascade-2";  VRAM="~20 GB" ;;
  70b)        TAG="nemotron";            VRAM="~48 GB (q4)" ;;
  -h|--help|help)
    print_table
    exit 0 ;;
  *)
    err "Unknown variant: $VARIANT"
    log ""
    print_table
    exit 1 ;;
esac

section "📥 Pulling Nemotron variant: $VARIANT  →  $TAG"
info "Expected VRAM: $VRAM"
info "Model card:    https://ollama.com/library/$(printf '%s' "$TAG" | cut -d: -f1)"

bash "$(dirname "$0")/04-pull-model.sh" "$TAG"

log ""
ok "Done. Run interactively with:  bash scripts/07-run-model.sh $TAG"
