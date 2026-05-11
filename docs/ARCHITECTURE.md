# Architecture

## Design principles

1. **Host-resident data, ephemeral containers.** Containers are disposable; models on the host disk are not.
2. **No host pollution.** Nothing installed on the OS itself — only Docker images and a single data directory.
3. **Tiered destruction.** Three explicit cleanup levels prevent accidental data loss.
4. **Profiles for heavyweights.** vLLM and PyTorch images are large; both are opt-in.
5. **Versioned images.** No `latest`. Update is an explicit script.

## Bind-mount strategy

```
HOST                                    CONTAINER
/mnt/edge-backup/ai-data/ollama   ───►  /root/.ollama       (Ollama models)
/mnt/edge-backup/ai-data/open-webui ─►  /app/backend/data   (WebUI DB)
/mnt/edge-backup/ai-data/hf-cache  ──►  /root/.cache/huggingface
/mnt/edge-backup/ai-data/training  ──►  /workspace/training
```

Key fact: `docker compose down` removes containers but **never** touches host directories. `docker compose up` re-creates the container, which sees the same `/root/.ollama` and finds all models intact.

## Why not Docker named volumes?

Named volumes hide data under `/var/lib/docker/volumes/...`, which is:
- harder to back up
- often on the OS disk (smaller)
- easy to lose to `docker volume prune`

Bind-mounts to `/mnt/edge-backup/ai-data` give a single, predictable, large location.

## Why not `chmod 777`?

`777` permits any user on the system (including service accounts and other containers) to read or modify model files. We use `u+rwX,g+rwX,o-rwx` instead — owner and group only.

The Ollama and Open WebUI containers run as root inside the container, but with our bind-mount, the host directory is owned by the invoking user. New files written from inside the container will be owned by root on the host; the wipe scripts handle this with `sudo` only when needed.

## GPU passthrough

Two paths can coexist:

1. **Compose v2 native:** `deploy.resources.reservations.devices` — the documented way for Compose to request GPUs.
2. **NVIDIA env vars:** `NVIDIA_VISIBLE_DEVICES=all`, `NVIDIA_DRIVER_CAPABILITIES=compute,utility` — picked up by NVIDIA Container Toolkit.

We use both for redundancy. `count: all` requests every visible GPU; the env vars confirm visibility/capabilities at runtime.

## Network topology

A single user-defined bridge (`edge-ai-net`) with stable container names lets services talk by hostname:

```
open-webui ──http──► ollama:11434
training/vllm ──── (independent, GPU-bound)
```

WebUI uses `http://ollama:11434` (Docker DNS), not `localhost` — the latter would not resolve from inside the WebUI container.

## Profiles

Compose profiles let you keep optional services in the same `docker-compose.yml` without affecting `compose up` defaults:

```bash
compose up -d                            # only ollama + open-webui
compose --profile vllm up -d vllm        # adds vLLM
compose --profile training run --rm training bash   # one-shot training shell
```

## aider coding CLI

aider is an AI pair-programming CLI that can edit files, run shell commands, and make git commits. It is delivered as a **host launcher** (not a Compose service) for two reasons:

1. **No service lifecycle friction** — the user `cd`s into any repo and runs `bash scripts/06-coding-cli.sh`; no `compose up`, no network to join, no per-project config.
2. **Correct git identity** — `~/.gitconfig` and `~/.ssh` are bind-mounted read-only at `docker run` time, so commits always carry the calling user's identity regardless of which repo is being edited.

The image tag is pinned in `.env.versions` (`AIDER_CLI_IMAGE`). Local mode points at `edge-ollama:11434/v1` (zero outbound AI traffic). Cloud mode goes through `edge-litellm:4000/v1` → Anthropic, gated by `LITELLM_MASTER_KEY`.

```
bash scripts/06-coding-cli.sh          # local (Ollama, no outbound calls)
bash scripts/06-coding-cli.sh --cloud  # cloud (LiteLLM → Anthropic)
```

Persistent aider config lives under `${AI_DATA_ROOT}/coding-cli/`.

## Cleanup decision tree

```
Want to free RAM/GPU?            ──► 02-stop.sh
Want to free disk (keep models)? ──► 10-cleanup-docker.sh
Want a clean slate?              ──► 20-wipe-models.sh   (then 00-install.sh)
```
