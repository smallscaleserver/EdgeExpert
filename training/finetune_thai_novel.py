#!/usr/bin/env python3
"""
finetune_thai_novel.py — QLoRA fine-tune Qwen3-14B base for Thai novel writing
Usage:
  python finetune_thai_novel.py                        # train + save LoRA
  python finetune_thai_novel.py --export-gguf q8_0    # train + export GGUF
  python finetune_thai_novel.py --resume               # resume from checkpoint
Run inside edge-finetune container:
  docker compose --profile finetune run --rm finetune python /workspace/scripts/finetune_thai_novel.py
"""

import argparse
import os
import sys

# ---------------------------------------------------------------------------
# Config — override via env vars or edit here
# ---------------------------------------------------------------------------
BASE_MODEL   = os.getenv("BASE_MODEL",   "Qwen/Qwen3-14B")
DATASET_PATH = os.getenv("DATASET_PATH", "/workspace/training/dataset/train.jsonl")
OUTPUT_DIR   = os.getenv("OUTPUT_DIR",   "/workspace/training/output/qwen3-14b-thai-novel")
HF_TOKEN     = os.getenv("HF_TOKEN",     None)

MAX_SEQ_LEN  = int(os.getenv("MAX_SEQ_LEN",  "16384"))
LORA_RANK    = int(os.getenv("LORA_RANK",    "64"))
BATCH_SIZE   = int(os.getenv("BATCH_SIZE",   "2"))
GRAD_ACCUM   = int(os.getenv("GRAD_ACCUM",   "16"))   # effective batch = 32
EPOCHS       = int(os.getenv("EPOCHS",       "3"))
LR           = float(os.getenv("LR",         "2e-4"))
SAVE_STEPS   = int(os.getenv("SAVE_STEPS",   "50"))


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--export-gguf", metavar="QUANT",
                   help="After training, export GGUF (e.g. q8_0, q4_k_m, f16)")
    p.add_argument("--resume", action="store_true",
                   help="Resume from latest checkpoint in OUTPUT_DIR")
    p.add_argument("--merge-only", action="store_true",
                   help="Skip training — just merge existing LoRA adapter and export")
    return p.parse_args()


def load_dataset_jsonl(path: str):
    """Load ChatML JSONL: each line = {"messages": [...]}"""
    from datasets import load_dataset
    if not os.path.exists(path):
        sys.exit(f"[ERROR] Dataset not found: {path}\n"
                 f"Generate it first: python /workspace/scripts/make_dataset.py")
    ds = load_dataset("json", data_files=path, split="train")
    print(f"[dataset] {len(ds)} examples loaded from {path}")
    return ds


def main():
    args = parse_args()

    from unsloth import FastLanguageModel
    from unsloth.chat_templates import get_chat_template
    from trl import SFTTrainer, SFTConfig

    # ------------------------------------------------------------------
    # 1. Load base model + tokenizer
    # ------------------------------------------------------------------
    print(f"[model] loading {BASE_MODEL} ...")
    # GB10 has 128 GB unified memory — no need for 4-bit quantization.
    # bitsandbytes CUDA 13.2 binary is missing in the base image (forward compat),
    # so load_in_4bit=False; bf16 full LoRA is faster and higher quality anyway.
    model, tokenizer = FastLanguageModel.from_pretrained(
        model_name=BASE_MODEL,
        max_seq_length=MAX_SEQ_LEN,
        load_in_4bit=False,
        dtype=torch.bfloat16,
        token=HF_TOKEN,
    )

    # Qwen3 base doesn't have a chat template — set ChatML
    tokenizer = get_chat_template(tokenizer, chat_template="chatml")

    if args.merge_only:
        _merge_and_export(model, tokenizer, args)
        return

    # ------------------------------------------------------------------
    # 2. Attach LoRA adapter
    # ------------------------------------------------------------------
    model = FastLanguageModel.get_peft_model(
        model,
        r=LORA_RANK,
        lora_alpha=LORA_RANK * 2,
        lora_dropout=0.05,
        target_modules=[
            "q_proj", "k_proj", "v_proj", "o_proj",
            "gate_proj", "up_proj", "down_proj",
        ],
        bias="none",
        use_gradient_checkpointing="unsloth",
        random_state=42,
    )
    print(f"[lora] rank={LORA_RANK}, alpha={LORA_RANK * 2}")

    # ------------------------------------------------------------------
    # 3. Prepare dataset
    # ------------------------------------------------------------------
    dataset = load_dataset_jsonl(DATASET_PATH)

    def apply_template(examples):
        texts = [
            tokenizer.apply_chat_template(m, tokenize=False, add_generation_prompt=False)
            for m in examples["messages"]
        ]
        return {"text": texts}

    dataset = dataset.map(apply_template, batched=True)

    # ------------------------------------------------------------------
    # 4. Train
    # ------------------------------------------------------------------
    resume = args.resume and os.path.isdir(OUTPUT_DIR)
    trainer = SFTTrainer(
        model=model,
        tokenizer=tokenizer,
        train_dataset=dataset,
        args=SFTConfig(
            output_dir=OUTPUT_DIR,
            num_train_epochs=EPOCHS,
            per_device_train_batch_size=BATCH_SIZE,
            gradient_accumulation_steps=GRAD_ACCUM,
            learning_rate=LR,
            lr_scheduler_type="cosine",
            warmup_ratio=0.05,
            max_grad_norm=0.3,
            bf16=True,
            logging_steps=10,
            save_steps=SAVE_STEPS,
            save_total_limit=3,
            dataset_text_field="text",
            max_seq_length=MAX_SEQ_LEN,
            packing=True,
            report_to="none",
        ),
    )

    print(f"[train] epochs={EPOCHS}, effective_batch={BATCH_SIZE * GRAD_ACCUM}, lr={LR}")
    trainer.train(resume_from_checkpoint=resume)

    # ------------------------------------------------------------------
    # 5. Save LoRA adapter
    # ------------------------------------------------------------------
    lora_dir = os.path.join(OUTPUT_DIR, "lora-final")
    model.save_pretrained(lora_dir)
    tokenizer.save_pretrained(lora_dir)
    print(f"[saved] LoRA adapter → {lora_dir}")

    # ------------------------------------------------------------------
    # 6. Merge + GGUF export (optional)
    # ------------------------------------------------------------------
    if args.export_gguf:
        _merge_and_export(model, tokenizer, args)


def _merge_and_export(model, tokenizer, args):
    import os
    quant = args.export_gguf or "q8_0"
    gguf_dir = os.path.join(OUTPUT_DIR, "gguf")
    os.makedirs(gguf_dir, exist_ok=True)

    print(f"[gguf] merging LoRA and exporting {quant} ...")
    model.save_pretrained_gguf(gguf_dir, tokenizer, quantization_method=quant)
    print(f"[gguf] saved → {gguf_dir}")
    print()
    print("Next steps:")
    print(f"  ollama create thai-novel-14b-{quant} -f <Modelfile>")
    print("  (copy the .gguf file to the Ollama host first)")


if __name__ == "__main__":
    main()
