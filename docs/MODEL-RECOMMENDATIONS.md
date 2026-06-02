# Model recommendations

## DGX Spark GB10 (128 GB unified — primary server)

| Model | Size | Speed | Best for |
|---|---|---|---|
| `qwen3-coder-next:latest` | 51 GB | 49 tok/s | flagship agentic coding, 256K context |
| `qwen3.6:27b` | 17 GB | ~70 tok/s | reasoning + coding, SWE-bench 77.2% |
| `qwen3-coder:30b` | 18 GB | ~65 tok/s | agentic coding, smaller than next |
| `qwen3-coder-32k:latest` | 18 GB | ~65 tok/s | qwen3-coder custom 32K context |
| `gemma4-32k:latest` | 17 GB | ~60 tok/s | general + vision |
| `gpt-oss:20b` | 13 GB | ~80 tok/s | public WebUI default (port 3001) |
| `qwen2.5-coder:7b` | 4.7 GB | 66 tok/s | fast utility tasks |
| `localmodel26b:latest` | 17 GB | ~60 tok/s | custom fine-tune |
| `nomic-embed-text` | small | — | embeddings |

All models run **100% GPU** on GB10 after the nvidia-ctk runtime fix (2026-06-03).

## Intel Arc 140T Windows laptop (36 GB Vulkan VRAM shared)

Requires `OLLAMA_VULKAN=1` + `VK_ICD_FILENAMES` set. Use `num_batch=64` Modelfile to avoid Windows TDR crash. See `docs/WINDOWS-SETUP.md`.

| Model | Size | GPU layers | Speed | Notes |
|---|---|---|---|---|
| `qwen3-coder-32k` | 18 GB | full | ~5 tok/s | best for Claude Code tool-use |
| `qwen2.5-coder-14b-stable` | 9 GB | full | ~10 tok/s | stable num_batch=64 variant |
| `devstral-stable` | 14 GB | full | ~4 tok/s | agentic coding, num_batch=64 |
| `devstral-cpu-native` | 14 GB | CPU | ~2 tok/s | no Vulkan crash, reliable |
| `qwen2.5-coder-cpu` | 4.7 GB | CPU | ~4 tok/s | always stable fallback |

## By use case

**Roo / agentic coding (server):** `qwen3-coder-next` → `qwen3.6:27b` → `qwen3-coder`

**Claude Code local (Windows via LiteLLM):** `qwen3-coder-32k` or `devstral-stable`

**Open WebUI chat:** Any model — default public port 3001 uses `gpt-oss:20b`

**Embeddings:** `nomic-embed-text`

**Fine-tune base:** `Qwen/Qwen3-14B` base (HuggingFace) via `edge-finetune:v1.0` image

## Pulling models

```bash
# On server
docker exec edge-ollama ollama pull qwen3-coder-next:latest
bash scripts/04-pull-model.sh qwen3-coder-next:latest   # via emr

# On Windows (Ollama native)
ollama pull qwen3-coder-32k
```

## Quantization guide

| Suffix | Quality | Size |
|---|---|---|
| `q8_0` | near-FP16 | largest |
| `q5_K_M` | recommended | mid |
| `q4_K_M` | default Ollama | smaller |
| `q2_K` | avoid | tiny / broken |

## Disk planning

| Params | q4_K_M | q8_0 |
|---|---|---|
| 7B | ~4.5 GB | ~7.5 GB |
| 14B | ~9 GB | ~15 GB |
| 27–30B | ~17 GB | ~30 GB |
| 50B+ | ~30 GB | ~55 GB |
