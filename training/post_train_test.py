#!/usr/bin/env python3
"""
post_train_test.py — ทดสอบ model ที่เทรนแล้ว เขียนตอนต่อ บันทึกเป็น notebook

Usage:
  python post_train_test.py                  # เขียนต่อจากตอนสุดท้ายใน dataset
  python post_train_test.py --prompt "..."   # prompt เอง
  python post_train_test.py --chapters 3    # เขียน 3 ตอน

Output: /workspace/training/output/novel_output.md
"""

import argparse, json, os, datetime, requests

OLLAMA_URL   = os.getenv("OLLAMA_URL",   "http://edge-ollama:11434")
MODEL_NAME   = os.getenv("MODEL_NAME",   "thai-novel-14b")
DATASET_PATH = os.getenv("DATASET_PATH", "/workspace/training/dataset/train.jsonl")
OUTPUT_MD    = os.getenv("OUTPUT_MD",    "/workspace/training/output/novel_output.md")

SYSTEM = (
    "คุณเป็นนักเขียนนิยายไทยมืออาชีพ เชี่ยวชาญด้านนิยายผู้ใหญ่ที่มีเนื้อหาตรงไปตรงมา "
    "เขียนภาษาไทยที่สวยงาม มีชีวิตชีวา บรรยายอารมณ์และความรู้สึกได้ลึกซึ้ง "
    "ตัวละครทุกตัวในเรื่องมีอายุ 18 ปีขึ้นไป ให้แต่งยาวๆ ต่อเนื่อง ไม่ต้องหยุดกลางคัน"
)


def get_last_chapter() -> str:
    """ดึงตอนสุดท้ายจาก dataset เพื่อใช้เป็น context"""
    if not os.path.exists(DATASET_PATH):
        return ""
    with open(DATASET_PATH, encoding="utf-8") as f:
        lines = f.readlines()
    if not lines:
        return ""
    last = json.loads(lines[-1])
    for msg in reversed(last.get("messages", [])):
        if msg["role"] == "assistant":
            return msg["content"]
    return ""


def generate(prompt: str, context: str = "") -> str:
    full_prompt = f"{context}\n\n---\n\n{prompt}" if context else prompt
    payload = {
        "model": MODEL_NAME,
        "messages": [
            {"role": "system",  "content": SYSTEM},
            {"role": "user",    "content": full_prompt},
        ],
        "stream": False,
        "options": {
            "num_predict": -1,
            "num_ctx":     32768,
            "temperature": 0.9,
            "top_p":       0.95,
        },
    }
    r = requests.post(f"{OLLAMA_URL}/api/chat", json=payload, timeout=600)
    r.raise_for_status()
    return r.json()["message"]["content"]


def save_notebook(chapters: list[dict], path: str):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    lines = [
        f"# นิยายไทย — ออกจาก model `{MODEL_NAME}`",
        f"> สร้างเมื่อ {now}\n",
    ]
    for i, ch in enumerate(chapters, 1):
        lines += [
            f"---\n## ตอนที่ {i}",
            f"**Prompt:** {ch['prompt']}\n",
            ch["content"],
            "",
        ]
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print(f"[saved] {path}")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--prompt",   default="เขียนตอนต่อไป บรรยายฉากและอารมณ์ตัวละครให้ยาวและละเอียด")
    p.add_argument("--chapters", type=int, default=1)
    p.add_argument("--no-context", action="store_true", help="ไม่ใช้ context จาก dataset")
    args = p.parse_args()

    # ตรวจว่า model อยู่ใน Ollama
    try:
        r = requests.get(f"{OLLAMA_URL}/api/tags", timeout=5)
        models = [m["name"] for m in r.json().get("models", [])]
        if not any(MODEL_NAME in m for m in models):
            print(f"[warn] model '{MODEL_NAME}' ไม่พบใน Ollama")
            print(f"       models ที่มี: {models[:5]}")
            print(f"       ลอง register ก่อน: ollama create {MODEL_NAME} -f <Modelfile>")
            return
    except Exception as e:
        print(f"[error] ต่อ Ollama ไม่ได้: {e}")
        return

    context = "" if args.no_context else get_last_chapter()
    if context:
        print(f"[context] ใช้ตอนสุดท้ายจาก dataset ({len(context)} chars)")

    chapters = []
    for i in range(args.chapters):
        prompt = args.prompt if i == 0 else "เขียนต่อจากตอนที่แล้ว ให้ยาวและละเอียดขึ้น"
        print(f"\n[gen {i+1}/{args.chapters}] {prompt[:60]}...")

        # ส่ง context จากตอนก่อนหน้า
        ctx = context if i == 0 else (chapters[-1]["content"] if chapters else "")
        content = generate(prompt, ctx)

        print(f"  → {len(content):,} chars")
        chapters.append({"prompt": prompt, "content": content})

    save_notebook(chapters, OUTPUT_MD)
    print(f"\n[done] เปิดดูที่: {OUTPUT_MD}")


if __name__ == "__main__":
    main()
