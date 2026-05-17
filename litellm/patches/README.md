# LiteLLM patches

Patches applied inside the running LiteLLM container to fix bugs not yet merged upstream.

## ollama_chat_array_content.patch

**Affects:** `litellm/llms/ollama_chat.py` — `get_ollama_response()` message loop  
**LiteLLM version tested:** 1.44.2  
**Status:** Apply after every container restart until upstream fix is released

### Problem

Claude Code (and the Anthropic Messages API) sends `content` as an array of typed blocks:
```json
{"role": "user", "content": [{"type": "text", "text": "..."}]}
```

`ollama_chat/` provider passes this array to Ollama's `/api/chat` as-is, which returns:
```
json: cannot unmarshal array into Go struct field ChatRequest.messages.content of type string
```

### Fix

Flatten array content to a plain string before sending to Ollama.

### Apply

```powershell
# Run after: docker restart edge-litellm
$f = "/usr/local/lib/python3.11/site-packages/litellm/llms/ollama_chat.py"
docker cp litellm/patches/ollama_chat_patched.py edge-litellm:$f
docker restart edge-litellm
```

Or use the patch file:
```bash
patch /usr/local/lib/python3.11/site-packages/litellm/llms/ollama_chat.py \
  < litellm/patches/ollama_chat_array_content.patch
```

### Why this matters

The `ollama_chat/` provider + `tool_call_parser: hermes` is the only path that converts
plain `{"name":...,"arguments":...}` JSON text → proper OpenAI `tool_calls` API format.
Models like qwen2.5-coder output plain JSON tool calls; without this parser they return
as `content` text and Claude Code ignores them.

The `openai/` provider (Ollama's `/v1` endpoint) handles array content correctly but
does not support `tool_call_parser`, so tool calls never get parsed.
