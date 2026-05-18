# LiteLLM patches

Patches applied inside the running LiteLLM container to fix bugs not yet merged upstream.
All patches target **LiteLLM 1.44.2** (`ghcr.io/berriai/litellm:main-v1.44.2`).

**IMPORTANT:** LiteLLM runs from `/app/litellm/` — NOT from site-packages.
All `docker cp` targets must use `/app/litellm/`, not `/usr/local/lib/python3.11/site-packages/litellm/`.

Apply order matters: apply `ollama_chat` first, then `main`, then `proxy_server`.

---

## 1. ollama_chat_array_content.patch

**File:** `litellm/llms/ollama_chat.py`  
**Patched copy:** `ollama_chat_patched.py`

### Problems fixed

1. **Array content**: Claude Code sends `content` as an array of typed blocks. `ollama_chat/` passed this array to Ollama's `/api/chat` as-is → `json: cannot unmarshal array`. Fix: flatten array content to plain string.

2. **Multi-tool JSON parsing**: When the model doesn't support native tool calling (2+ tools), LiteLLM sets `format=json` and the model returns `{"name":"...","arguments":{...}}` text. The original code only parsed this when `function_name is not None` (single-tool). Fix: parse JSON to `tool_calls` whenever `format=json`, regardless of `function_name`.

3. **token_counter crash on tool_call messages**: After a tool_call response, the messages history contains `tool_calls` with dict-type `arguments`. The `token_counter` fallback in `ollama_acompletion` tried to concatenate dict to str → `TypeError`. Fix: use `0` as fallback instead of calling `token_counter` (Ollama always returns `prompt_eval_count` and `eval_count` anyway).

### Apply
```powershell
docker cp litellm/patches/ollama_chat_patched.py edge-litellm:/app/litellm/llms/ollama_chat.py
```

---

## 2. litellm_main_stream_false

**File:** `litellm/main.py` — `aadapter_completion()` function  
**Patched copy:** `litellm_main_patched.py`

### Problem
When a Claude Code request has `stream=true`, `acompletion()` inside `aadapter_completion()` returns an `async_generator` instead of a `ModelResponse`. The type check `isinstance(response, ModelResponse)` fails, so `translated_response` stays `None`. The Anthropic SSE generator then receives `None` → all SSE content is empty → Claude Code gets empty responses and fails to use any tools.

### Fix
Force `new_kwargs['stream'] = False` before calling `acompletion()`.

### Apply
```powershell
docker cp litellm/patches/litellm_main_patched.py edge-litellm:/app/litellm/main.py
```

---

## 3. proxy_server_anthropic_sse

**File:** `litellm/proxy/proxy_server.py`  
**Patched copy:** `proxy_server_patched.py`

### Problem
After the `stream=False` fix in patch 2, the response is an `AnthropicResponse` (non-iterable). The existing `async_data_generator_anthropic()` does `async for chunk in response` which fails with `TypeError`.

### Fix
1. Add `_anthropic_response_to_sse_chunks(response)` — converts a completed `AnthropicResponse` to Anthropic SSE event dicts.
2. Patch `async_data_generator_anthropic()` to detect non-async-iterable responses and route through `_anthropic_response_to_sse_chunks`.

### Apply
```powershell
docker cp litellm/patches/proxy_server_patched.py edge-litellm:/app/litellm/proxy/proxy_server.py
```

---

## 4. factory_function_prompt

**File:** `litellm/llms/prompt_templates/factory.py`  
**Patched copy:** `factory_patched.py`

### Problem
The default `function_prompt` is vague: "Produce JSON OUTPUT ONLY! Adhere to this format...". Small models (7B) ignore it and invent their own tool names.

### Fix
Stronger prompt: "TOOL CALL MODE - Output ONE JSON object ONLY, no text, no explanation. REQUIRED FORMAT: {"name": "FUNCTION_NAME", "arguments": {"param": "value"}}. FUNCTION_NAME must be one of the listed function names."

### Apply
```powershell
docker cp litellm/patches/factory_patched.py edge-litellm:/app/litellm/llms/prompt_templates/factory.py
```

---

## Apply all patches at once (after container start)

```powershell
$patches = "C:\Edge\edgeexpert\EdgeExpert\litellm\patches"
docker cp "$patches\ollama_chat_patched.py"   edge-litellm:/app/litellm/llms/ollama_chat.py
docker cp "$patches\litellm_main_patched.py"  edge-litellm:/app/litellm/main.py
docker cp "$patches\proxy_server_patched.py"  edge-litellm:/app/litellm/proxy/proxy_server.py
docker cp "$patches\factory_patched.py"       edge-litellm:/app/litellm/llms/prompt_templates/factory.py
```

**No container restart needed** — changes take effect on the next request (Python reloads on change since there's no pyc to conflict after the old pyc is cleared).

**Clear pyc cache after patching** (do once after first apply):
```powershell
docker exec edge-litellm python3 -c "
import glob, os
for pat in ['/app/litellm/__pycache__/main*', '/app/litellm/llms/__pycache__/ollama_chat*', '/app/litellm/proxy/__pycache__/proxy_server*']:
    [os.remove(f) for f in glob.glob(pat)]
print('done')
"
```

---

## Working model configs for Claude Code tool-use on Intel Arc 140T

| Model name | Provider | GPU layers | Status |
|---|---|---|---|
| `qwen2.5-coder-8k-hermes` | `ollama_chat/qwen2.5-coder-8k` | 28/28 (full GPU) | Crashes after ~7 min (Vulkan) |
| `qwen2.5-coder-partial-hermes` | `ollama_chat/qwen2.5-coder-partial` | 20/28 (partial GPU) | Crashes on complex requests |
| `qwen2.5-coder-cpu-hermes` | `ollama_chat/qwen2.5-coder-cpu` | 0 (CPU only) | **Working** — multi-tool fixed |
| `devstral-cpu` | `ollama_chat/devstral-cpu` | 0 (CPU only) | Confused by Claude Code system prompt |

**Recommended:** `qwen2.5-coder-cpu-hermes` — stable, no Vulkan crash, multi-tool works after patch.

## Intel Arc 140T GPU status

All GPU (Vulkan) variants crash on complex tool-use requests. Root cause: Intel Arc 140T Vulkan runner memory instability under sustained load. No fix yet. CPU is the only stable path for Claude Code agentic tasks on this hardware.

NPU: Intel Arc NPU is not supported by Ollama (no OpenVINO backend). Alternative: run via OpenVINO + LM Studio (separate setup).
