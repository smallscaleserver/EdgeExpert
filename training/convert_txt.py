#!/usr/bin/env python3
"""
convert_txt.py — แปลงไฟล์ .txt ใน raw/ ให้เป็น ChatML JSONL สำหรับ fine-tune

Usage:
  python convert_txt.py                        # raw/ → dataset/train.jsonl
  python convert_txt.py --chunk-size 800       # ตัดทุก 800 chars
  python convert_txt.py --merge                # ผสมกับ dataset เดิม (ไม่ทับ)
  python convert_txt.py --preview              # แสดงตัวอย่างโดยไม่บันทึก

Run inside container:
  docker compose --profile finetune run --rm finetune \
    python /workspace/scripts/convert_txt.py

โครงสร้างโฟลเดอร์:
  /workspace/training/raw/        ← วาง .txt ที่นี่
  /workspace/training/dataset/    ← output train.jsonl
"""

import argparse
import json
import os
import re

RAW_DIR    = os.getenv("RAW_DIR",    "/workspace/training/raw")
OUTPUT     = os.getenv("OUTPUT",     "/workspace/training/dataset/train.jsonl")
CHUNK_SIZE = int(os.getenv("CHUNK_SIZE", "1000"))  # chars per example

SYSTEM_PROMPT = (
    "คุณเป็นนักเขียนนิยายไทยมืออาชีพ เชี่ยวชาญด้านนิยายผู้ใหญ่ที่มีเนื้อหาตรงไปตรงมา "
    "เขียนภาษาไทยที่สวยงาม มีชีวิตชีวา บรรยายอารมณ์และความรู้สึกได้ลึกซึ้ง "
    "ตัวละครทุกตัวในเรื่องมีอายุ 18 ปีขึ้นไป"
)

# Prompts ที่ใช้สลับกันเพื่อให้ dataset หลากหลาย
PROMPTS = [
    "เขียนฉากต่อไปนี้ให้สมบูรณ์",
    "เขียนเนื้อหาตอนนี้ของนิยาย",
    "เขียนฉากนี้ในสไตล์นิยายไทยผู้ใหญ่",
    "เขียนต่อจากจุดนี้ของเรื่อง",
    "บรรยายฉากและอารมณ์ตัวละครในตอนนี้",
]


def clean_text(text: str) -> str:
    """ลบบรรทัดว่างซ้ำ ช่องว่างส่วนเกิน"""
    text = re.sub(r'\r\n', '\n', text)
    text = re.sub(r'\n{3,}', '\n\n', text)
    text = re.sub(r'[ \t]+', ' ', text)
    return text.strip()


def chunk_text(text: str, size: int) -> list[str]:
    """ตัด text เป็น chunks ตาม paragraph boundaries"""
    paragraphs = [p.strip() for p in text.split('\n\n') if p.strip()]
    chunks, current = [], ""

    for para in paragraphs:
        if len(current) + len(para) + 2 > size and current:
            chunks.append(current.strip())
            current = para
        else:
            current = (current + "\n\n" + para).strip() if current else para

    if current:
        chunks.append(current.strip())

    # ถ้า paragraph ยาวมากให้ตัดด้วยจำนวน chars
    result = []
    for chunk in chunks:
        if len(chunk) <= size * 1.5:
            result.append(chunk)
        else:
            for i in range(0, len(chunk), size):
                part = chunk[i:i + size].strip()
                if len(part) > 100:
                    result.append(part)
    return result


def to_chatml(chunk: str, prompt_idx: int) -> dict:
    prompt = PROMPTS[prompt_idx % len(PROMPTS)]
    return {
        "messages": [
            {"role": "system",    "content": SYSTEM_PROMPT},
            {"role": "user",      "content": prompt},
            {"role": "assistant", "content": chunk},
        ]
    }


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--raw-dir",    default=RAW_DIR)
    p.add_argument("--output",     default=OUTPUT)
    p.add_argument("--chunk-size", type=int, default=CHUNK_SIZE)
    p.add_argument("--merge",      action="store_true",
                   help="เพิ่มต่อจากไฟล์เดิมแทนการทับ")
    p.add_argument("--preview",    action="store_true",
                   help="แสดงตัวอย่าง 3 ชิ้นโดยไม่บันทึก")
    args = p.parse_args()

    if not os.path.isdir(args.raw_dir):
        print(f"[error] ไม่พบโฟลเดอร์: {args.raw_dir}")
        print(f"  สร้างโฟลเดอร์แล้ววาง .txt ที่นี่:")
        print(f"  mkdir -p {args.raw_dir}")
        return

    txt_files = sorted(
        f for f in os.listdir(args.raw_dir) if f.endswith(".txt")
    )

    if not txt_files:
        print(f"[error] ไม่พบไฟล์ .txt ใน {args.raw_dir}")
        return

    print(f"[convert] พบ {len(txt_files)} ไฟล์ใน {args.raw_dir}")
    print(f"[convert] chunk size = {args.chunk_size} chars")
    print()

    examples, prompt_idx = [], 0
    for fname in txt_files:
        path = os.path.join(args.raw_dir, fname)
        raw = open(path, encoding="utf-8", errors="replace").read()
        text = clean_text(raw)
        chunks = chunk_text(text, args.chunk_size)

        print(f"  {fname}: {len(raw):,} chars → {len(chunks)} chunks")

        for chunk in chunks:
            examples.append(to_chatml(chunk, prompt_idx))
            prompt_idx += 1

    print()
    print(f"[total] {len(examples)} examples จาก {len(txt_files)} ไฟล์")

    if args.preview:
        print("\n=== ตัวอย่าง 3 ชิ้นแรก ===")
        for i, ex in enumerate(examples[:3]):
            print(f"\n--- chunk {i+1} ---")
            print("USER:", ex["messages"][1]["content"])
            print("ASST:", ex["messages"][2]["content"][:300], "...")
        return

    os.makedirs(os.path.dirname(args.output), exist_ok=True)
    mode = "a" if args.merge else "w"

    existing = 0
    if args.merge and os.path.exists(args.output):
        with open(args.output) as f:
            existing = sum(1 for _ in f)

    with open(args.output, mode, encoding="utf-8") as f:
        for ex in examples:
            f.write(json.dumps(ex, ensure_ascii=False) + "\n")

    total = existing + len(examples) if args.merge else len(examples)
    print(f"[saved] {args.output} ({total} examples total)")
    print()
    print("ขั้นตอนถัดไป:")
    print(f"  python /workspace/scripts/finetune_thai_novel.py --export-gguf q8_0")


if __name__ == "__main__":
    main()
