# LiteLLM Patch Maintenance

Operational guide for the four patches applied to **LiteLLM 1.44.2**
(`edge-litellm` container) to make Claude Code tool-use work with local
Ollama models.

---

## Overview

LiteLLM 1.44.2 ships with several bugs in its `ollama_chat/` adapter that
collectively prevent Claude Code from using tools with local models. The
patches live in [`litellm/patches/`](../litellm/patches/) and are applied
with `docker cp` after each container start — no image rebuild required.

**Critical path detail:** LiteLLM runs from `/app/litellm/` inside the
container, **not** from `/usr/local/lib/python3.11/site-packages/litellm/`.
All `docker cp` targets must use `/app/litellm/` or the patch is silently
ignored.

Verify which path is active:
```powershell
docker exec edge-litellm python3 -c "import litellm.llms.ollama_chat as m; print(m.__file__)"
# must print: /app/litellm/llms/ollama_chat.py
```

---

## Modified files and why each patch exists

### 1. `ollama_chat_patched.py` → `/app/litellm/llms/ollama_chat.py`

**Three bugs fixed in this file:**

#### Bug 1 — Array content crash
Claude Code sends `content` as an array of typed blocks:
```json
[{"type": "text", "text": "..."}, {"type": "tool_result", "content": [...]}]
```
The unpatched code passes this array to Ollama's `/api/chat` as-is. Ollama
returns `json: cannot unmarshal array` and the request fails.

**Fix:** In `get_ollama_response`, before building the request payload, flatten
any `content` array to a plain string by concatenating all `text` parts and
extracting text from nested `tool_result` blocks.

#### Bug 2 — Multi-tool JSON not converted to tool\_use
When 2+ tools are passed, LiteLLM sets `format=json` and injects a
`function_call_prompt` into the system message telling the model to return
`{"name": "...", "arguments": {...}}`. The model returns this as text content.

The original parser only converted the JSON to a `tool_calls` block when
`function_name is not None` — which is only true for single-tool requests.
Multi-tool requests always had `function_name=None`, so the JSON was passed
through as plain text. Claude Code received no tool\_use block and failed.

**Fix:** Remove the `function_name is not None` condition. Parse the JSON to
`tool_calls` whenever `format=json`, regardless of `function_name`. Applied
in both the sync (`get_ollama_response`) and async (`ollama_acompletion`) paths.

Extended key aliases are also accepted because 7B models sometimes generate
non-standard key names:
- `command`, `tool`, `action` are accepted as aliases for `name`
- `params`, `parameters` are accepted as aliases for `arguments`
- When no `arguments` key is found, non-name keys at the top level are
  collected as the argument dict

#### Bug 3 — `token_counter` crash on tool\_call messages
After a tool call, the message history contains a `tool_calls` entry with
`arguments` as a dict (not a string). The `token_counter` fallback in
`ollama_acompletion` tried to concatenate dict to str → `TypeError`.

Original:
```python
prompt_tokens = response_json.get(
    "prompt_eval_count",
    litellm.token_counter(messages=data["messages"])  # crashes
)
```

**Fix:** Use `0` as the fallback. Ollama always returns `prompt_eval_count`
and `eval_count` in its response JSON, so the fallback is never needed in
practice.

---

### 2. `litellm_main_patched.py` → `/app/litellm/main.py`

**One bug fixed — streaming response type mismatch in `aadapter_completion`.**

Claude Code sends `stream=true`. Inside `aadapter_completion`, the Anthropic
→ OpenAI translation layer calls `acompletion(stream=True)`, which returns an
`async_generator` instead of a `ModelResponse`. The subsequent
`isinstance(response, ModelResponse)` check fails, `translated_response`
stays `None`, and all SSE chunks come back empty.

**Fix:** Force `new_kwargs['stream'] = False` before calling `acompletion()`.
The SSE stream is then built by `async_data_generator_anthropic` in
`proxy_server.py` (patch 3) from the complete `ModelResponse`.

---

### 3. `proxy_server_patched.py` → `/app/litellm/proxy/proxy_server.py`

**One bug fixed — non-iterable `AnthropicResponse` in `async_data_generator_anthropic`.**

After the `stream=False` fix in patch 2, the response is an `AnthropicResponse`
object, not an async iterable. The existing `async for chunk in response` loop
raises `TypeError: 'AnthropicResponse' object is not iterable`.

**Fix — two changes:**

1. Add `_anthropic_response_to_sse_chunks(response)` — a function that converts
   a completed `AnthropicResponse` into a sequence of Anthropic SSE event dicts
   (`message_start`, `content_block_start`, `content_block_delta`,
   `content_block_stop`, `message_delta`, `message_stop`).

2. Patch `async_data_generator_anthropic()` to detect when `response` is not
   an async iterable and route it through `_anthropic_response_to_sse_chunks`
   instead.

---

### 4. `factory_patched.py` → `/app/litellm/llms/prompt_templates/factory.py`

**One improvement — stronger function\_call\_prompt for small models.**

The default `function_prompt` is vague: `"Produce JSON OUTPUT ONLY! Adhere to this format..."`.
Small models (7B) frequently ignore it and invent their own tool names.

**Fix:** Replace with an explicit prompt:
```
TOOL CALL MODE - Output ONE JSON object ONLY, no text, no explanation.
REQUIRED FORMAT: {"name": "FUNCTION_NAME", "arguments": {"param": "value"}}.
FUNCTION_NAME must be one of the listed function names.
```

This reduces (but does not eliminate) invented tool names on 7B models.
14B+ models follow it reliably.

---

## Apply all patches

Run after every container start (or after `docker restart edge-litellm`):

```powershell
$patches = "C:\Edge\edgeexpert\EdgeExpert\litellm\patches"
docker cp "$patches\ollama_chat_patched.py"   edge-litellm:/app/litellm/llms/ollama_chat.py
docker cp "$patches\litellm_main_patched.py"  edge-litellm:/app/litellm/main.py
docker cp "$patches\proxy_server_patched.py"  edge-litellm:/app/litellm/proxy/proxy_server.py
docker cp "$patches\factory_patched.py"       edge-litellm:/app/litellm/llms/prompt_templates/factory.py

# Clear pyc cache (required on first apply; harmless to repeat)
docker exec edge-litellm python3 -c "
import glob, os
for pat in ['/app/litellm/__pycache__/main*',
            '/app/litellm/llms/__pycache__/ollama_chat*',
            '/app/litellm/proxy/__pycache__/proxy_server*',
            '/app/litellm/llms/prompt_templates/__pycache__/factory*']:
    [os.remove(f) for f in glob.glob(pat)]
print('pyc cleared')
"
```

No container restart needed — Python loads the patched `.py` files on the
next request once the stale `.pyc` files are removed.

---

## How to validate patches are active

### Check 1 — Confirm correct file path

```powershell
docker exec edge-litellm python3 -c "
import litellm.llms.ollama_chat as oc
import litellm.main as m
import litellm.proxy.proxy_server as ps
import litellm.llms.prompt_templates.factory as f
print('ollama_chat:', oc.__file__)
print('main:       ', m.__file__)
print('proxy:      ', ps.__file__)
print('factory:    ', f.__file__)
"
# All four must show /app/litellm/... (not /usr/local/lib/...)
```

### Check 2 — Confirm patch content is present

```powershell
# ollama_chat patch: look for the key-alias extension
docker exec edge-litellm grep -n "_name_keys" /app/litellm/llms/ollama_chat.py
# should print: line number with {"name", "function", "command", "tool", "action"}

# main patch: look for forced stream=False
docker exec edge-litellm grep -n "stream.*False" /app/litellm/main.py | head -5

# proxy patch: look for the SSE converter function
docker exec edge-litellm grep -n "_anthropic_response_to_sse_chunks" /app/litellm/proxy/proxy_server.py

# factory patch: look for TOOL CALL MODE
docker exec edge-litellm grep -n "TOOL CALL MODE" /app/litellm/llms/prompt_templates/factory.py
```

### Check 3 — Live multi-tool smoke test

Send a 2-tool request; `stop_reason` must be `tool_use`:

```powershell
$body = @{
  model    = "qwen2.5-coder-cpu-hermes"
  messages = @(@{ role = "user"; content = "What files are in the root of this repo?" })
  tools    = @(
    @{ name = "Read"; description = "Read a file"
       input_schema = @{ type = "object"
                         properties = @{ file_path = @{ type = "string" } }
                         required = @("file_path") } },
    @{ name = "Glob"; description = "Find files by glob pattern"
       input_schema = @{ type = "object"
                         properties = @{ pattern = @{ type = "string" } }
                         required = @("pattern") } }
  )
  max_tokens = 256
} | ConvertTo-Json -Depth 10

$r = Invoke-RestMethod http://localhost:4000/v1/messages `
  -Method POST `
  -Headers @{ "x-api-key" = "sk-changeme"; "anthropic-version" = "2023-06-01" } `
  -ContentType "application/json" -Body $body -TimeoutSec 300

$r.stop_reason   # must be "tool_use"
$r.content | ConvertTo-Json -Depth 5
```

Expected response structure:
```json
{
  "stop_reason": "tool_use",
  "content": [
    {"type": "tool_use", "name": "Glob", "input": {"pattern": "*"}}
  ]
}
```

---

## How to test with a small repo

Use any small git repo (e.g. `C:\testlab\testgo\testgo`) to run a
full end-to-end agentic test.

```powershell
# 1. Apply patches (Step 2 above)

# 2. Set environment
$env:ANTHROPIC_BASE_URL = "http://localhost:4000"
$env:ANTHROPIC_API_KEY  = "sk-changeme"

# 3. Run a one-shot Claude Code task
cd C:\testlab\testgo\testgo
claude --model qwen2.5-coder-14b-hermes --print `
  "In main.go change the formula from a*b to a+b*a and update the printf format string."

# 4. Check the result
git diff main.go
```

A successful run means:
- Claude Code made tool calls (`Read`, `Edit` or `Write`)
- `stop_reason` was `tool_use` for each tool call
- The file was actually modified
- Claude Code reached a natural end (`stop_reason=end_turn`)

If the model makes tool calls but the file is unchanged, check the debug log:
```powershell
docker exec edge-litellm cat /tmp/ollama_debug.log | Select-Object -Last 40
```

---

## Model recommendations

### For agentic coding (Claude Code sessions)

| Model | Config name | VRAM / RAM | Tok/s (CPU) | Recommendation |
|---|---|---|---|---|
| `devstral` | `devstral-cpu` | ~15 GB RAM | ~2–4 | **Best** — purpose-built for agentic coding, highest tool compliance |
| `qwen2.5-coder:32b` | `qwen2.5-coder-cpu-hermes` | ~20 GB RAM | ~1–2 | Near-Claude quality on hard tasks; slow on CPU |
| `qwen2.5-coder:14b` | `qwen2.5-coder-cpu-hermes` | ~9 GB RAM | ~3–5 | **Recommended minimum** — reliable tool schema compliance |
| `deepseek-coder-v2:16b` | `deepseek-coder-v2-cpu` | ~10 GB RAM | ~5–8 | MoE architecture — fast for size, good compliance |
| `qwen2.5-coder:7b` | `qwen2.5-coder-cpu-hermes` | ~5 GB RAM | ~4 | Simple completions only; **fails complex agentic tasks** |

### Why qwen2.5-coder:7b fails complex agentic tasks

The 7B model does not reliably follow Claude Code's tool schema. Observed failure modes:

1. **Invented tool names** — generates `change_formula`, `EditFile`, `UpdateCode`
   which are not in Claude Code's schema. Claude Code returns an error; the model
   cannot recover and loops.

2. **Wrong key names** — generates `{"command": "Read", "file_path": "..."}` instead
   of `{"name": "Read", "input": {"file_path": "..."}}`. The `ollama_chat_patched.py`
   handles `command`/`tool`/`action` aliases, but cannot handle entirely invented
   tool names.

3. **Argument format errors** — puts arguments at the top level of the JSON object
   instead of inside `"arguments"`. The extended parser in `ollama_chat_patched.py`
   recovers from this, but combined with wrong key names the model still fails.

4. **Confusion loops** — after receiving a tool error from Claude Code, the 7B model
   re-generates the same invalid tool call rather than switching strategy. 64+ tool
   calls have been observed with no progress.

**The `ollama_chat_patched.py` extended parser helps** but is not a substitute for
a larger model. The parser handles aliased key names; it cannot invent the correct
tool name when the model fabricates one.

### Intel Arc 140T GPU status

| Variant | GPU layers | Vulkan stable? | Recommendation |
|---|---|---|---|
| `qwen2.5-coder-8k-hermes` | 28/28 (full GPU) | No — crashes after ~7 min | Do not use for Claude Code sessions |
| `qwen2.5-coder-partial-hermes` | 20/28 | No — crashes on complex requests | Not reliable |
| `qwen2.5-coder-stable` | 14/28 | Marginal | Test only; may work for short sessions |
| `qwen2.5-coder-cpu-hermes` | 0 (CPU only) | N/A | **Use this** — no Vulkan, fully stable |
| `devstral-cpu` | 0 (CPU only) | N/A | **Use this** — best for agentic coding |

Root cause: Intel Arc 140T Vulkan runner has memory instability under sustained
load (15+ sequential completions). The crash is in Ollama's Vulkan backend, not
in LiteLLM or the patches.

**NPU note:** Intel Arc NPU is not supported by Ollama (no OpenVINO backend).
To use the NPU, run models via OpenVINO + LM Studio and wire LM Studio into
LiteLLM using `scripts/37-setup-lmstudio.sh` (Option F in `docs/AI-CODING-SETUP.md`).

---

## Troubleshooting

### Patches appear not to take effect

Check the path:
```powershell
docker exec edge-litellm python3 -c "import litellm.llms.ollama_chat as m; print(m.__file__)"
```
If this prints a path under `/usr/local/lib/...`, Python is loading site-packages
instead of `/app/litellm/`. This should not happen on the standard image but can
occur if the image was rebuilt. Re-apply patches to `/app/litellm/`.

Check pyc cache:
```powershell
docker exec edge-litellm ls -la /app/litellm/llms/__pycache__/ollama_chat*
```
If the `.pyc` file is newer than the `.py` file, Python uses the cache.
Delete it and try again.

### `stop_reason` is `end_turn` instead of `tool_use` on a 2-tool request

Most likely cause: patches are not applied, or `ollama_chat_patched.py` is
not at `/app/litellm/llms/ollama_chat.py`.

Run Check 2 from the validation section above to confirm the key-alias code
is present.

If patches are confirmed applied: the model returned something that is not
valid JSON (e.g. a sentence with JSON embedded). Check the debug log:
```powershell
docker exec edge-litellm cat /tmp/ollama_debug.log | Select-Object -Last 20
```

### Router cooldown: "No deployments available — try again in 60 seconds"

After a crash (e.g. `token_counter` TypeError), LiteLLM's router puts the
model on a 60-second cooldown. The cooldown is stored in memory, not disk.

Fix: restart the container to clear it:
```powershell
docker restart edge-litellm
# Wait ~2–3 minutes for Ollama to reload the model
# Then re-apply patches
```

### First request after restart times out

Ollama re-loads the model from disk on the first request. For a 14B model
this takes ~2 minutes. The default LiteLLM timeout (120s) may expire.

Warm up manually:
```powershell
# Send a simple no-tool request with a long timeout
$body = '{"model":"qwen2.5-coder-cpu-hermes","messages":[{"role":"user","content":"hi"}],"max_tokens":5}' | Out-String
Invoke-RestMethod http://localhost:4000/v1/messages `
  -Method POST `
  -Headers @{ "x-api-key" = "sk-changeme"; "anthropic-version" = "2023-06-01" } `
  -ContentType "application/json" -Body $body -TimeoutSec 600
```

### Debug log location

The patched files write a lightweight debug log inside the container:
```powershell
docker exec edge-litellm cat /tmp/ollama_debug.log
```

Each request appends one line from `get_ollama_response` and one from
`ollama_acompletion`. Use this to verify format, stream flag, and parsed
content during a live Claude Code session:
```powershell
# Follow the log in real time while running Claude Code
docker exec edge-litellm tail -f /tmp/ollama_debug.log
```

---

## Safe rollback

Rollback restores the unpatched LiteLLM files from the running container image.
This does **not** delete any Ollama models, Open WebUI data, or `.env` secrets.

### Option A — Restart the container (recommended)

A container restart resets `/app/litellm/` to the image baseline:
```powershell
docker restart edge-litellm
# Patches are now gone. Do NOT re-apply if you want to stay unpatched.
```

Verify the original file is restored:
```powershell
docker exec edge-litellm grep -c "_name_keys" /app/litellm/llms/ollama_chat.py
# must print 0 (not found)
```

### Option B — Restore individual files from the image

If you only want to roll back one patch:
```powershell
# Extract the original file from a fresh container without starting the full stack
$orig = docker run --rm ghcr.io/berriai/litellm:main-v1.44.2 cat /app/litellm/llms/ollama_chat.py
$orig | Set-Content "C:\Edge\edgeexpert\EdgeExpert\litellm\patches\ollama_chat_original.py" -Encoding utf8

# Then copy back into the running container
docker cp "C:\Edge\edgeexpert\EdgeExpert\litellm\patches\ollama_chat_original.py" `
  edge-litellm:/app/litellm/llms/ollama_chat.py
docker exec edge-litellm python3 -c "
import glob, os
[os.remove(f) for f in glob.glob('/app/litellm/llms/__pycache__/ollama_chat*')]
"
```

### What rollback does NOT affect

- Ollama model files at `C:\ai-data\ollama\models\` — untouched
- Open WebUI database at `C:\ai-data\open-webui\` — untouched
- `.env.windows` secrets — untouched
- `litellm/config.windows.yaml` model entries — untouched
- `litellm/patches/*.py` patch source files — still on disk, can re-apply

---

## Patch source files reference

| Source file | Applied to (container path) | LiteLLM version |
|---|---|---|
| `litellm/patches/ollama_chat_patched.py` | `/app/litellm/llms/ollama_chat.py` | 1.44.2 |
| `litellm/patches/litellm_main_patched.py` | `/app/litellm/main.py` | 1.44.2 |
| `litellm/patches/proxy_server_patched.py` | `/app/litellm/proxy/proxy_server.py` | 1.44.2 |
| `litellm/patches/factory_patched.py` | `/app/litellm/llms/prompt_templates/factory.py` | 1.44.2 |

If upgrading LiteLLM to a newer version, the patches may need to be regenerated.
Check whether each bug listed in this document is fixed upstream before applying
old patches to a new version.
