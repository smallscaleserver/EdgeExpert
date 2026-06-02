#!/usr/bin/env python3
"""
finetune_thai_novel.py — LoRA fine-tune Qwen3-14B base for Thai novel writing
Uses vanilla transformers + PEFT (not unsloth) for full control on GB10.

Usage:
  python finetune_thai_novel.py                        # train + save LoRA
  python finetune_thai_novel.py --export-gguf q8_0    # train + export GGUF
  python finetune_thai_novel.py --resume               # resume from checkpoint
"""

import argparse, os, sys

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
_HF_SNAPSHOT = "/root/.cache/huggingface/models--Qwen--Qwen3-14B/snapshots/40c069824f4251a91eefaf281ebe4c544efd3e18"
BASE_MODEL   = os.getenv("BASE_MODEL", _HF_SNAPSHOT if os.path.isdir(_HF_SNAPSHOT) else "Qwen/Qwen3-14B")
DATASET_PATH = os.getenv("DATASET_PATH", "/workspace/training/dataset/train.jsonl")
OUTPUT_DIR   = os.getenv("OUTPUT_DIR",   "/workspace/training/output/qwen3-14b-thai-novel")
HF_TOKEN     = os.getenv("HF_TOKEN",     None)

MAX_SEQ_LEN  = int(os.getenv("MAX_SEQ_LEN",  "8192"))
LORA_RANK    = int(os.getenv("LORA_RANK",    "64"))
BATCH_SIZE   = int(os.getenv("BATCH_SIZE",   "2"))
GRAD_ACCUM   = int(os.getenv("GRAD_ACCUM",   "16"))
EPOCHS       = int(os.getenv("EPOCHS",       "3"))
LR           = float(os.getenv("LR",         "2e-4"))
SAVE_STEPS   = int(os.getenv("SAVE_STEPS",   "50"))


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--export-gguf", metavar="QUANT",
                   help="After training, export GGUF (e.g. q8_0, q4_k_m)")
    p.add_argument("--resume", action="store_true")
    p.add_argument("--merge-only", action="store_true")
    return p.parse_args()


def load_dataset(path):
    from datasets import load_dataset
    if not os.path.exists(path):
        sys.exit(f"[ERROR] Dataset not found: {path}")
    ds = load_dataset("json", data_files=path, split="train")
    print(f"[dataset] {len(ds)} examples from {path}")
    return ds


def main():
    import torch
    from transformers import (
        AutoModelForCausalLM, AutoTokenizer,
        Trainer, TrainingArguments,
        DataCollatorForLanguageModeling,
    )
    from peft import LoraConfig, get_peft_model, TaskType

    args = parse_args()

    # ------------------------------------------------------------------
    # 1. Load tokenizer
    # ------------------------------------------------------------------
    print(f"[model] loading tokenizer from {BASE_MODEL} ...")
    tokenizer = AutoTokenizer.from_pretrained(
        BASE_MODEL, trust_remote_code=True, token=HF_TOKEN
    )
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token

    # ------------------------------------------------------------------
    # 2. Load model — bf16, all on GPU (GB10 has 121 GB)
    # ------------------------------------------------------------------
    print(f"[model] loading weights in bf16 ...")
    model = AutoModelForCausalLM.from_pretrained(
        BASE_MODEL,
        torch_dtype=torch.bfloat16,
        device_map={"": 0},          # all layers on cuda:0
        trust_remote_code=True,
        token=HF_TOKEN,
    )
    model.config.use_cache = False
    model.enable_input_require_grads()

    if args.merge_only:
        _export_gguf(model, tokenizer, args.export_gguf or "q8_0")
        return

    # ------------------------------------------------------------------
    # 3. Attach LoRA
    # ------------------------------------------------------------------
    lora_cfg = LoraConfig(
        task_type=TaskType.CAUSAL_LM,
        r=LORA_RANK,
        lora_alpha=LORA_RANK * 2,
        lora_dropout=0.05,
        target_modules=[
            "q_proj", "k_proj", "v_proj", "o_proj",
            "gate_proj", "up_proj", "down_proj",
        ],
        bias="none",
    )
    model = get_peft_model(model, lora_cfg)
    model.print_trainable_parameters()
    print(f"[lora] rank={LORA_RANK}, alpha={LORA_RANK*2}")

    # ------------------------------------------------------------------
    # 4. Dataset
    # ------------------------------------------------------------------
    raw_ds = load_dataset(DATASET_PATH)

    # Tokenize — convert ChatML messages → token ids
    def tokenize(examples):
        texts = [
            tokenizer.apply_chat_template(
                m, tokenize=False, add_generation_prompt=False
            )
            for m in examples["messages"]
        ]
        out = tokenizer(
            texts,
            truncation=True,
            max_length=MAX_SEQ_LEN,
            padding=False,
        )
        out["labels"] = out["input_ids"].copy()
        return out

    dataset = raw_ds.map(tokenize, batched=True, remove_columns=raw_ds.column_names)

    collator = DataCollatorForLanguageModeling(tokenizer, mlm=False)

    # ------------------------------------------------------------------
    # 5. Train — vanilla Trainer (no trl API quirks)
    # ------------------------------------------------------------------
    resume = args.resume and os.path.isdir(OUTPUT_DIR)

    trainer = Trainer(
        model=model,
        args=TrainingArguments(
            output_dir=OUTPUT_DIR,
            num_train_epochs=EPOCHS,
            per_device_train_batch_size=BATCH_SIZE,
            gradient_accumulation_steps=GRAD_ACCUM,
            learning_rate=LR,
            lr_scheduler_type="cosine",
            warmup_steps=10,
            max_grad_norm=0.3,
            bf16=True,
            logging_steps=5,
            save_steps=SAVE_STEPS,
            save_total_limit=3,
            report_to="none",
            gradient_checkpointing=True,
            remove_unused_columns=False,
        ),
        train_dataset=dataset,
        data_collator=collator,
        processing_class=tokenizer,
    )

    print(f"[train] epochs={EPOCHS}, eff_batch={BATCH_SIZE*GRAD_ACCUM}, lr={LR}, seq={MAX_SEQ_LEN}")
    trainer.train(resume_from_checkpoint=resume)

    # ------------------------------------------------------------------
    # 6. Save LoRA
    # ------------------------------------------------------------------
    lora_dir = os.path.join(OUTPUT_DIR, "lora-final")
    model.save_pretrained(lora_dir)
    tokenizer.save_pretrained(lora_dir)
    print(f"[saved] LoRA → {lora_dir}")

    if args.export_gguf:
        _export_gguf(model, tokenizer, args.export_gguf)


def _export_gguf(model, tokenizer, quant):
    """Merge LoRA → full model → GGUF via unsloth's built-in exporter."""
    import os
    gguf_dir = os.path.join(OUTPUT_DIR, "gguf")
    os.makedirs(gguf_dir, exist_ok=True)

    # Try unsloth exporter first; fall back to save merged model
    try:
        from unsloth import FastLanguageModel
        model.save_pretrained_gguf(gguf_dir, tokenizer, quantization_method=quant)
        print(f"[gguf] saved → {gguf_dir}")
    except Exception as e:
        print(f"[gguf] unsloth exporter failed ({e}), saving merged model instead")
        merged_dir = os.path.join(OUTPUT_DIR, "merged")
        model = model.merge_and_unload()
        model.save_pretrained(merged_dir)
        tokenizer.save_pretrained(merged_dir)
        print(f"[merged] saved → {merged_dir}")
        print("Convert to GGUF manually with llama.cpp convert_hf_to_gguf.py")

    print("\nNext: ollama create thai-novel-14b -f <Modelfile>")


if __name__ == "__main__":
    main()
