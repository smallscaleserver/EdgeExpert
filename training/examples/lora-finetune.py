"""
LoRA fine-tuning example — minimal, runnable scaffold.

Run from inside the training container:
    cd /workspace/training
    pip install -r /workspace/scripts/requirements.txt
    python /workspace/scripts/examples/lora-finetune.py

Customize MODEL_ID, DATASET, and hyperparameters for your use case.
"""

import os

import torch
from datasets import load_dataset
from peft import LoraConfig, get_peft_model, prepare_model_for_kbit_training
from transformers import (
    AutoModelForCausalLM,
    AutoTokenizer,
    BitsAndBytesConfig,
    Trainer,
    TrainingArguments,
)

# --- Config ----------------------------------------------------------------
MODEL_ID = os.environ.get("MODEL_ID", "Qwen/Qwen2.5-Coder-1.5B-Instruct")
DATASET = os.environ.get("DATASET", "tatsu-lab/alpaca")
OUTPUT_DIR = os.environ.get("OUTPUT_DIR", "/workspace/training/output/lora-demo")

# --- Quantization (optional, saves VRAM) ----------------------------------
bnb_config = BitsAndBytesConfig(
    load_in_4bit=True,
    bnb_4bit_quant_type="nf4",
    bnb_4bit_compute_dtype=torch.bfloat16,
)

# --- Model + tokenizer -----------------------------------------------------
print(f"Loading model: {MODEL_ID}")
tokenizer = AutoTokenizer.from_pretrained(MODEL_ID, trust_remote_code=True)
if tokenizer.pad_token is None:
    tokenizer.pad_token = tokenizer.eos_token

model = AutoModelForCausalLM.from_pretrained(
    MODEL_ID,
    quantization_config=bnb_config,
    device_map="auto",
    trust_remote_code=True,
)
model = prepare_model_for_kbit_training(model)

# --- LoRA ------------------------------------------------------------------
lora = LoraConfig(
    r=16,
    lora_alpha=32,
    target_modules=["q_proj", "k_proj", "v_proj", "o_proj"],
    lora_dropout=0.05,
    bias="none",
    task_type="CAUSAL_LM",
)
model = get_peft_model(model, lora)
model.print_trainable_parameters()

# --- Data ------------------------------------------------------------------
print(f"Loading dataset: {DATASET}")
ds = load_dataset(DATASET, split="train[:1000]")  # tiny slice for demo


def fmt(ex):
    text = (
        f"### Instruction:\n{ex['instruction']}\n\n"
        f"### Input:\n{ex.get('input', '')}\n\n"
        f"### Response:\n{ex['output']}"
    )
    return tokenizer(text, truncation=True, max_length=512, padding="max_length")


ds = ds.map(fmt, remove_columns=ds.column_names)

# --- Train -----------------------------------------------------------------
args = TrainingArguments(
    output_dir=OUTPUT_DIR,
    per_device_train_batch_size=4,
    gradient_accumulation_steps=4,
    num_train_epochs=1,
    learning_rate=2e-4,
    bf16=True,
    logging_steps=10,
    save_strategy="epoch",
    report_to="none",  # set "wandb" if WANDB_API_KEY is configured
)

trainer = Trainer(model=model, args=args, train_dataset=ds)
trainer.train()
trainer.save_model(OUTPUT_DIR)
print(f"✓ Saved adapter to {OUTPUT_DIR}")
