#!/usr/bin/env python3
# =============================================================================
# ollama-mcp-server.py — minimal MCP stdio server that proxies a local Ollama
# =============================================================================
# Exposes the local Ollama instance as MCP tools so an MCP-aware client
# (Claude Code, OpenCode, Cline, ...) can offload local-friendly work
# (summarising long files, generating boilerplate, computing embeddings)
# without any data leaving the host.
#
# Transport:  stdio, newline-delimited JSON-RPC 2.0 (MCP spec).
# Deps:       Python 3 stdlib only — no pip install needed.
#
# Env:
#   OLLAMA_URL            default http://localhost:11434
#   OLLAMA_DEFAULT_MODEL  default qwen2.5-coder:7b
#   OLLAMA_EMBED_MODEL    default nomic-embed-text
# =============================================================================
import json
import os
import sys
import urllib.error
import urllib.request

OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://localhost:11434").rstrip("/")
DEFAULT_MODEL = os.environ.get("OLLAMA_DEFAULT_MODEL", "qwen2.5-coder:7b")
EMBED_MODEL = os.environ.get("OLLAMA_EMBED_MODEL", "nomic-embed-text")

PROTOCOL_VERSION = "2024-11-05"
SERVER_NAME = "ollama-worker"
SERVER_VERSION = "0.1.0"


def _http_json(path, payload=None, method="POST", timeout=600):
    url = OLLAMA_URL + path
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={"Content-Type": "application/json"} if data else {},
    )
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())


TOOLS = [
    {
        "name": "ollama_generate",
        "description": (
            "Generate text using the local Ollama model. Use for code "
            "completion, drafting boilerplate, quick rewrites, and "
            "brainstorming. Runs entirely on the host — no data leaves the "
            "machine. Prefer this for bulk/repetitive work; reserve the "
            "calling agent's main model for hard reasoning."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "prompt": {"type": "string", "description": "Prompt to send"},
                "model": {
                    "type": "string",
                    "description": f"Ollama tag (default: {DEFAULT_MODEL})",
                },
                "system": {"type": "string", "description": "Optional system prompt"},
            },
            "required": ["prompt"],
        },
    },
    {
        "name": "ollama_summarize",
        "description": (
            "Summarise a long block of text or file contents using the local "
            "model. Useful to compress logs/files before passing context "
            "back to a more expensive model."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "text": {"type": "string"},
                "model": {"type": "string"},
                "instruction": {
                    "type": "string",
                    "description": "Optional extra instruction (e.g. 'focus on errors')",
                },
            },
            "required": ["text"],
        },
    },
    {
        "name": "ollama_embed",
        "description": "Compute a vector embedding for text using the local embed model.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "text": {"type": "string"},
                "model": {"type": "string"},
            },
            "required": ["text"],
        },
    },
    {
        "name": "ollama_list_models",
        "description": "List models currently installed in the local Ollama instance.",
        "inputSchema": {"type": "object", "properties": {}},
    },
]


def _generate(model, prompt, system=None):
    payload = {"model": model, "prompt": prompt, "stream": False}
    if system:
        payload["system"] = system
    r = _http_json("/api/generate", payload)
    return r.get("response", "")


def call_tool(name, args):
    if name == "ollama_generate":
        return _generate(
            args.get("model") or DEFAULT_MODEL,
            args["prompt"],
            args.get("system"),
        )
    if name == "ollama_summarize":
        instruction = args.get("instruction") or "Summarise the following concisely."
        prompt = f"{instruction}\n\n---\n{args['text']}"
        return _generate(args.get("model") or DEFAULT_MODEL, prompt)
    if name == "ollama_embed":
        r = _http_json(
            "/api/embeddings",
            {"model": args.get("model") or EMBED_MODEL, "prompt": args["text"]},
        )
        return json.dumps(r.get("embedding", []))
    if name == "ollama_list_models":
        r = _http_json("/api/tags", method="GET", timeout=10)
        names = [m.get("name", "?") for m in r.get("models", [])]
        return "\n".join(names) if names else "(no models installed)"
    raise ValueError(f"Unknown tool: {name}")


def _send(msg):
    sys.stdout.write(json.dumps(msg) + "\n")
    sys.stdout.flush()


def _handle(msg):
    method = msg.get("method")
    mid = msg.get("id")

    if method == "initialize":
        return {
            "jsonrpc": "2.0",
            "id": mid,
            "result": {
                "protocolVersion": PROTOCOL_VERSION,
                "capabilities": {"tools": {"listChanged": False}},
                "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
            },
        }

    if method == "tools/list":
        return {"jsonrpc": "2.0", "id": mid, "result": {"tools": TOOLS}}

    if method == "tools/call":
        params = msg.get("params") or {}
        try:
            text = call_tool(params.get("name"), params.get("arguments") or {})
            return {
                "jsonrpc": "2.0",
                "id": mid,
                "result": {"content": [{"type": "text", "text": text}]},
            }
        except urllib.error.URLError as e:
            return {
                "jsonrpc": "2.0",
                "id": mid,
                "result": {
                    "content": [
                        {
                            "type": "text",
                            "text": (
                                f"Ollama unreachable at {OLLAMA_URL}: {e}. "
                                "Is the edge-ollama container running? "
                                "Try: bash scripts/01-start.sh"
                            ),
                        }
                    ],
                    "isError": True,
                },
            }
        except Exception as e:  # noqa: BLE001 — surface tool errors to the client
            return {
                "jsonrpc": "2.0",
                "id": mid,
                "result": {
                    "content": [{"type": "text", "text": f"Error: {e}"}],
                    "isError": True,
                },
            }

    if method and method.startswith("notifications/"):
        return None

    if mid is not None:
        return {
            "jsonrpc": "2.0",
            "id": mid,
            "error": {"code": -32601, "message": f"Method not found: {method}"},
        }
    return None


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        resp = _handle(msg)
        if resp is not None:
            _send(resp)


if __name__ == "__main__":
    main()
