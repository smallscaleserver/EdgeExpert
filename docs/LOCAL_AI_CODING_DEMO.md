# Local AI Coding Demo

วิธีใช้ local AI แก้ไฟล์จริงใน repo บนสแตกนี้

---

## ตัวเลือกหลัก: Roo (VS Code)

ดู `docs/AI-CODING-SETUP.md` Option G — เชื่อมตรงกับ Ollama บน server:
- Base URL: `http://10.88.1.254:11434`
- Model: `qwen3-coder-next:latest` หรือ `qwen3.6:27b`

---

## ตัวเลือกรอง: `emr aider` (terminal)

Model ที่ใช้งานได้ปัจจุบัน (qwen2.5-coder:14b/32b ถูกลบออกแล้ว):

```bash
./bin/emr models         # ดู model ที่มี
./bin/emr aider          # interactive session (default: qwen2.5-coder:7b)
```

ระบุ model อื่น:
```bash
./bin/emr aider --model qwen3-coder:30b README.md -- \
  --message "Improve the README. Commit the change." --yes-always
```

One-shot:
```bash
./bin/emr aider path/to/file.go -- \
  --message "Fix bugs in this file. Keep changes minimal. Commit." --yes-always
```

> **Tip:** ถ้าใช้ model ขนาดใหญ่ (`qwen3-coder-next`) ผ่าน Roo จะเร็วและแม่นยำกว่า aider มาก เพราะ Roo ส่ง tool call ไปยัง Ollama โดยตรงโดยไม่ผ่าน LiteLLM

---

## ตรวจผลทุกครั้งหลัง AI แก้

```bash
git diff           # ดูการเปลี่ยนแปลง
git log --oneline  # ดู commit ที่ AI สร้าง
bash scripts/03-verify.sh   # ตรวจ stack
make quick-check            # lint + invariants (ถ้า Makefile มี)
```
