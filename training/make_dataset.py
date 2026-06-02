#!/usr/bin/env python3
"""
make_dataset.py — Generate synthetic Thai explicit fiction dataset via Ollama
Saves to /workspace/training/dataset/train.jsonl (ChatML format)

Usage:
  python make_dataset.py                      # generate 500 examples
  python make_dataset.py --count 2000         # generate 2000 examples
  python make_dataset.py --resume             # append to existing file
  python make_dataset.py --ollama-url http://edge-ollama:11434
Run inside edge-finetune container:
  docker compose --profile finetune run --rm finetune python /workspace/scripts/make_dataset.py
"""

import argparse
import json
import os
import random
import sys
import time
import requests

OLLAMA_URL   = os.getenv("OLLAMA_URL",   "http://edge-ollama:11434")
GEN_MODEL    = os.getenv("GEN_MODEL",    "qwen3-coder-next:latest")
OUTPUT_FILE  = os.getenv("OUTPUT_FILE",  "/workspace/training/dataset/train.jsonl")
DEFAULT_N    = int(os.getenv("DATASET_COUNT", "500"))

SYSTEM_PROMPT = (
    "คุณเป็นนักเขียนนิยายไทยมืออาชีพ เชี่ยวชาญด้านนิยายผู้ใหญ่ที่มีเนื้อหาตรงไปตรงมา "
    "เขียนภาษาไทยที่สวยงาม มีชีวิตชีวา บรรยายอารมณ์และความรู้สึกได้ลึกซึ้ง "
    "ตัวละครทุกตัวในเรื่องมีอายุ 18 ปีขึ้นไป"
)

# ---------------------------------------------------------------------------
# Prompt seeds — varied scene types and writing angles
# ---------------------------------------------------------------------------
SCENE_TEMPLATES = [
    "เขียนฉากพบกันครั้งแรกระหว่าง {char_a} และ {char_b} ในบรรยากาศ{setting} ประมาณ 400-600 คำ",
    "เขียนฉากความตึงเครียดทางอารมณ์ระหว่าง {char_a} กับ {char_b} ที่สะสมมานาน นำไปสู่การ{action} ประมาณ 500-700 คำ",
    "เขียนฉากหลัง{event} ของ {char_a} และ {char_b} บรรยายความรู้สึกและความผูกพัน ประมาณ 400-600 คำ",
    "เขียนบทสนทนาและฉากใกล้ชิดระหว่าง {char_a} กับ {char_b} ใน{setting} ประมาณ 600-800 คำ",
    "เขียนฉากที่ {char_a} แสดงความรู้สึกที่ซ่อนไว้ต่อ {char_b} อย่างตรงไปตรงมา ประมาณ 400-600 คำ",
]

CHARACTERS = [
    ("นาย", "นางสาว"), ("ดร.พิชัย", "คุณปราง"), ("ลิน", "มาร์ค"),
    ("ผู้หญิงในชุดแดง", "ชายหนุ่มนักธุรกิจ"), ("ครูสาว", "นักศึกษาปริญญาโท"),
    ("แพทย์หญิง", "คนไข้"), ("นักเขียน", "บรรณาธิการสาว"),
    ("พี่สาวเพื่อน", "หนุ่มหล่อ"), ("ทนายหญิง", "ลูกความ"),
]

SETTINGS = [
    "ห้องพักโรงแรมหรู", "คืนฝนตกในคอนโด", "ออฟฟิศหลังเวลางาน",
    "งานเลี้ยงค็อกเทล", "ชายหาดยามค่ำคืน", "ร้านกาแฟในซอยเงียบ",
    "รถไฟความเร็วสูง", "บ้านพักตากอากาศ",
]

EVENTS = [
    "วันเกิด", "งานแต่งงานที่ถูกยกเลิก", "การพลัดพรากนาน 5 ปี",
    "การกลับมาพบกันโดยบังเอิญ", "ข้อตกลงทางธุรกิจ",
]

ACTIONS = [
    "สารภาพรัก", "จูบครั้งแรก", "ตัดสินใจอยู่ด้วยกัน", "เปิดใจ",
]


def random_prompt() -> str:
    template = random.choice(SCENE_TEMPLATES)
    char_a, char_b = random.choice(CHARACTERS)
    return template.format(
        char_a=char_a,
        char_b=char_b,
        setting=random.choice(SETTINGS),
        event=random.choice(EVENTS),
        action=random.choice(ACTIONS),
    )


def generate_one(prompt: str, session: requests.Session) -> str | None:
    payload = {
        "model": GEN_MODEL,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user",   "content": prompt},
        ],
        "stream": False,
        "options": {"temperature": 0.9, "top_p": 0.95, "num_predict": 1024},
    }
    try:
        r = session.post(f"{OLLAMA_URL}/api/chat", json=payload, timeout=300)
        r.raise_for_status()
        return r.json()["message"]["content"].strip()
    except Exception as e:
        print(f"  [warn] generation failed: {e}", file=sys.stderr)
        return None


def to_chatml(prompt: str, response: str) -> dict:
    return {
        "messages": [
            {"role": "system",    "content": SYSTEM_PROMPT},
            {"role": "user",      "content": prompt},
            {"role": "assistant", "content": response},
        ]
    }


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--count", type=int, default=DEFAULT_N)
    p.add_argument("--resume", action="store_true")
    p.add_argument("--ollama-url", default=OLLAMA_URL)
    p.add_argument("--model", default=GEN_MODEL)
    p.add_argument("--output", default=OUTPUT_FILE)
    args = p.parse_args()

    global OLLAMA_URL, GEN_MODEL
    OLLAMA_URL = args.ollama_url
    GEN_MODEL  = args.model

    os.makedirs(os.path.dirname(args.output), exist_ok=True)

    existing = 0
    if args.resume and os.path.exists(args.output):
        with open(args.output) as f:
            existing = sum(1 for _ in f)
        print(f"[resume] {existing} existing examples — generating {args.count - existing} more")
        if existing >= args.count:
            print("[done] target already reached")
            return
        mode = "a"
    else:
        mode = "w"
        existing = 0

    target = args.count
    session = requests.Session()

    print(f"[dataset] generating {target - existing} examples → {args.output}")
    print(f"[model]   {GEN_MODEL} @ {OLLAMA_URL}")

    with open(args.output, mode) as f:
        for i in range(existing, target):
            prompt = random_prompt()
            print(f"  [{i+1}/{target}] {prompt[:60]}...", end=" ", flush=True)
            t0 = time.time()
            response = generate_one(prompt, session)
            if response is None:
                print("SKIP")
                continue
            elapsed = time.time() - t0
            words = len(response)
            print(f"{words} chars, {elapsed:.1f}s")
            f.write(json.dumps({"messages": [
                {"role": "system",    "content": SYSTEM_PROMPT},
                {"role": "user",      "content": prompt},
                {"role": "assistant", "content": response},
            ]}, ensure_ascii=False) + "\n")
            f.flush()

    print(f"[done] saved {target} examples to {args.output}")


if __name__ == "__main__":
    main()
