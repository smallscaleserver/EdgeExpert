# Troubleshooting

## GPU not visible inside container

```bash
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi
```

If this fails, NVIDIA Container Toolkit is not configured:

```bash
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

Verify:
```bash
docker info | grep -i runtime
# Should show: nvidia
```

## "permission denied" on `/mnt/edge-backup/ai-data`

This usually means files inside were created by root from a prior container run.

```bash
sudo chown -R "$USER:$USER" /mnt/edge-backup/ai-data
chmod -R u+rwX,g+rwX,o-rwx /mnt/edge-backup/ai-data
```

## Models disappeared after rebuild

This **should not** happen with this stack — models are bind-mounted from the host. If it did, check:

```bash
ls -la /mnt/edge-backup/ai-data/ollama/models/
docker inspect edge-ollama | jq '.[0].Mounts'
```

The mount source must be `/mnt/edge-backup/ai-data/ollama` and the destination `/root/.ollama`. If you see a Docker named volume instead, your `.env` was not loaded — make sure you start with `bash scripts/01-start.sh`, not raw `docker compose up`.

## Open WebUI shows "Could not connect to Ollama"

Inside the WebUI container, `ollama` resolves via Docker's DNS — not `localhost`.

Check:
```bash
docker exec edge-open-webui curl -sf http://ollama:11434/api/tags
```

If that fails:
1. Confirm Ollama is healthy: `docker compose ps`
2. Confirm both containers are on `edge-ai-net`: `docker network inspect edge-ai-net`

## Out of memory loading a model

Reduce concurrent models in `.env`:
```bash
OLLAMA_MAX_LOADED_MODELS=1
OLLAMA_NUM_PARALLEL=1
```

Or pick a smaller quantization (e.g. `qwen2.5-coder:7b-instruct-q4_K_M`).

Restart:
```bash
bash scripts/02-stop.sh && bash scripts/01-start.sh
```

## Pull is very slow

Ollama pulls from registry.ollama.ai. If you're behind a proxy, set Docker daemon proxy in `/etc/systemd/system/docker.service.d/http-proxy.conf`. Restart Docker.

## Disk is full

```bash
bash scripts/08-disk-report.sh
```

Reclaim, in order of safety:
```bash
docker system prune -f                            # safe
bash scripts/06-remove-model.sh <unused-model>    # safe, surgical
bash scripts/10-cleanup-docker.sh                 # safe (keeps models)
bash scripts/20-wipe-models.sh                    # nuclear
```

## "No such file" for `.env` or `.env.versions`

You probably ran a script with raw `docker compose` instead of through the wrapper.

Always use the scripts under `scripts/`, or pass both env files manually:
```bash
docker compose --env-file .env --env-file .env.versions <command>
```

## Container exits immediately

```bash
docker compose logs ollama --tail=100
docker compose logs open-webui --tail=100
```

Common causes:
- Port already in use → change `OLLAMA_PORT` / `WEBUI_PORT` in `.env`
- Bad `WEBUI_SECRET_KEY` → re-run `bash scripts/00-install.sh`
- Missing GPU driver → install/upgrade NVIDIA driver, reboot

## aider: 401 / "Unauthorized" from LiteLLM

aider passes `OPENAI_API_KEY` as the bearer token. In cloud mode this must match `LITELLM_MASTER_KEY` in `.env`. Verify:

```bash
grep LITELLM_MASTER_KEY .env
curl -s -H "Authorization: Bearer <key>" http://localhost:4000/health/liveliness
```

If the key is wrong, update `.env` and rerun `scripts/06-coding-cli.sh`.

## aider: "No such model" / 404

For local mode, the model must be pulled into Ollama:

```bash
docker exec edge-ollama ollama list   # check available models
bash scripts/04-pull-model.sh qwen2.5-coder:7b
```

For cloud mode, check that the model name matches an entry in `litellm/config.yaml`:

```bash
grep model_name litellm/config.yaml
```

## aider: "Tool-calling unsupported"

aider requires function-calling support. Not all models support it:

- ✅ Local: `qwen2.5-coder:7b`, `qwen2.5-coder:14b`, `qwen2.5-coder:32b`
- ✅ Cloud: `claude-sonnet-4-6`, `claude-opus-4-7`
- ❌ `nemotron` (instruct only, no tool-calling schema)

Switch model with `--model <name>`.

## Weekly disk report (cron suggestion)

Add to `crontab -e` — not installed automatically:

```cron
# Weekly disk report → log file
# 0 3 * * 0  cd /home/expert/edge-model-runtime && bash scripts/08-disk-report.sh >> /mnt/edge-backup/ai-data/logs/disk-report.log 2>&1
```

## How to fully reset

```bash
bash scripts/20-wipe-models.sh   # confirm with 'DELETE ALL'
bash scripts/00-install.sh
```
