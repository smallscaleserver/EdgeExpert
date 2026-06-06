# Training

---

## ⚠️ MSI EDGEEXPERT — ต้องตั้งค่า GPU ก่อนทุกครั้ง

> ### ❌ อย่าลืม: EDGEEXPERT ตั้งค่าเริ่มต้นเป็น CPU — ต้องสลับเป็น GPU ก่อนรัน training
>
> ถ้ายังไม่ได้ตั้งค่า NVIDIA Container Toolkit ไว้ Docker จะรัน training บน **CPU** แทน GPU  
> ซึ่งทำให้ใช้เวลานานกว่าปกติหลาย 10 เท่า และ model อาจ OOM ได้
>
> **→ ดูวิธีตั้งค่า GPU ให้พร้อมใช้งานได้ที่:** [docs/TROUBLESHOOTING.md — "GPU not visible inside container"](../docs/TROUBLESHOOTING.md)
>
> ตรวจสอบว่า GPU ทำงานอยู่จริง **ก่อนรัน training ทุกครั้ง**:
>
> ```bash
> # วิธีที่ 1 — ดู Ollama (ต้องเห็น "100% GPU" ไม่ใช่ "100% CPU")
> docker exec edge-ollama ollama ps
>
> # วิธีที่ 2 — NVTOP: ดู GPU utilization + VRAM ขณะ training รันอยู่
> nvtop
>
> # วิธีที่ 3 — HTOP: ถ้า CPU usage พุ่งสูงแต่ NVTOP ไม่ขยับ = รันบน CPU อยู่!
> htop
> ```
>
> **สัญญาณบอกว่ารันบน CPU (ผิด):** HTOP เห็น CPU 100% / NVTOP ไม่ขยับเลย  
> **สัญญาณบอกว่ารันบน GPU (ถูก):** NVTOP เห็น GPU % และ VRAM ขึ้น / HTOP CPU ต่ำ

---

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
