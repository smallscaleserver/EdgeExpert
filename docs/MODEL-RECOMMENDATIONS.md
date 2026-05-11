# Model recommendations

Pick based on your VRAM and use case. All examples assume Ollama; any model from the [Ollama library](https://ollama.com/library) works.

## Nemotron family

NVIDIA's Nemotron line is a first-class option on this stack. Use the helper script to pick the right variant for your VRAM:

```bash
bash scripts/0a-pull-nemotron.sh nano   # default
```

| Variant | Ollama tag | Active params | VRAM (rough) | Notes |
|---|---|---|---|---|
| `mini` | `nemotron-mini` | 4B | ~6 GB | Assistant. Function calling, RAG, edge deployment. |
| `nano` | `nemotron-3-nano` | 3.5B active / 30B MoE | ~20 GB | **Reasoning.** Unified reasoning + non-reasoning agent. |
| `nano-omni` | `nemotron3:33b` | 33B multimodal | ~24 GB | Multimodal (video + audio + image + text). Requires a multimodal-capable Ollama build. |
| `super` | `nemotron-3-super` | 12B active / 120B MoE | ~80 GB | **Reasoning.** Strong agent / IT automation. |
| `cascade` | `nemotron-cascade-2` | 3B active / 30B MoE | ~20 GB | Agentic, low active-param footprint. |
| `70b` | `nemotron` | 70B (Llama-3.1-Nemotron) | ~48 GB (q4) | Assistant. RLHF-tuned for helpfulness. |

Reasoning variants: **Nano**, **Super**. Assistant variants: **Mini**, **70B**.

Links: [NVIDIA Nemotron hub](https://developer.nvidia.com/nemotron) · [NVIDIA Open Model License](https://developer.download.nvidia.com/licenses/nvidia-open-model-license-agreement.pdf)

## By VRAM

### 4–8 GB VRAM

| Model | Size | Use case |
|---|---|---|
| `qwen2.5-coder:7b` | ~4.7 GB | coding |
| `llama3.2:3b` | ~2 GB | general chat |
| `phi3.5:3.8b` | ~2.2 GB | reasoning |
| `mistral:7b` | ~4.1 GB | general |
| `gemma2:2b` | ~1.6 GB | tiny / fast |

### 12–16 GB VRAM

| Model | Size | Use case |
|---|---|---|
| `qwen2.5-coder:14b` | ~8.7 GB | strong coding |
| `llama3.1:8b-instruct-q8_0` | ~8.5 GB | high-quality general |
| `mistral-nemo:12b` | ~7 GB | long context |
| `deepseek-coder-v2:16b` | ~9 GB | coding (MoE) |
| `gpt-oss:20b` | ~13 GB | OpenAI open-weights — same model the LM Studio [video](https://www.youtube.com/watch?v=Cyn_Dm05_eU) uses; works well with Claude Code via Option D (`claude-local-gpt-oss`) |

### 24+ GB VRAM

| Model | Size | Use case |
|---|---|---|
| `qwen2.5-coder:32b` | ~19 GB | top-tier coding |
| `llama3.3:70b-instruct-q4_K_M` | ~42 GB | top-tier general |
| `mixtral:8x7b` | ~26 GB | MoE general |

## By task

**Coding:** `qwen2.5-coder:*`, `deepseek-coder-v2:*`, `codestral:*`
**General chat:** `llama3.1:*`, `llama3.2:*`, `mistral:*`
**Long context:** `mistral-nemo:12b`, `qwen2.5:7b-instruct-q5_K_M` (128k)
**Function calling:** `qwen2.5:*-instruct`, `llama3.1:*-instruct`
**Vision:** `llava:*`, `llama3.2-vision:*`

## Quantization quick guide

Tag suffix → quality vs size:

- `q8_0` — near-FP16 quality, largest
- `q5_K_M` — sweet spot, recommended default
- `q4_K_M` — smaller, slight quality drop
- `q3_K_M` — small, noticeable quality drop
- `q2_K` — tiny, often broken

Default tag (e.g. `qwen2.5-coder:7b`) is usually `q4_K_M` — fine for most uses.

## Pulling

```bash
bash scripts/04-pull-model.sh qwen2.5-coder:7b
bash scripts/04-pull-model.sh llama3.1:8b-instruct-q5_K_M
```

## Disk planning

Rough disk usage at common quantizations:

| Param count | q4_K_M | q5_K_M | q8_0 |
|---|---|---|---|
| 3B | ~2 GB | ~2.5 GB | ~3.5 GB |
| 7B | ~4.5 GB | ~5.5 GB | ~7.5 GB |
| 8B | ~5 GB | ~6 GB | ~8.5 GB |
| 14B | ~9 GB | ~10 GB | ~15 GB |
| 32B | ~20 GB | ~23 GB | ~34 GB |
| 70B | ~42 GB | ~50 GB | ~75 GB |
