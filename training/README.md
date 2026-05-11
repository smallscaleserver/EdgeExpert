# Training

Optional fine-tuning workflows. **Not pulled by default** — the PyTorch image is large (~10 GB).

## Quick start

```bash
# 1. Pull the training image (one-time, ~10 GB download)
docker compose --env-file ../.env --env-file ../.env.versions \
  --profile training pull training

# 2. Open an interactive shell
docker compose --env-file ../.env --env-file ../.env.versions \
  --profile training run --rm training bash

# 3. Inside container:
cd /workspace/training            # persistent (host-mounted)
ls /workspace/scripts             # this folder, read-only
pip install -r /workspace/scripts/requirements.txt
python /workspace/scripts/examples/lora-finetune.py
```

## Volume layout

| Container path | Host path | Notes |
|---|---|---|
| `/workspace/training` | `${AI_DATA_ROOT}/training` | persistent, read-write |
| `/workspace/scripts`  | `./training` (this folder) | read-only |
| `/root/.cache/huggingface` | `${AI_DATA_ROOT}/hf-cache` | shared with vLLM |

## TensorBoard

```bash
# Inside training container:
tensorboard --logdir /workspace/training/runs --bind_all
```

Then open http://localhost:6006 on host.

## Jupyter

```bash
# Inside training container:
jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --allow-root
```

Then open http://localhost:8888 on host.
