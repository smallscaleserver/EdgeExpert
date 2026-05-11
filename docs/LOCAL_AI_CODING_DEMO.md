# Local AI Coding Demo

เอกสารนี้สรุปวิธีใช้ `emr aider` ให้ **Local AI แก้ไฟล์จริงใน repo** (ไม่ใช่ตอบอธิบายอย่างเดียว) โดยแยกจาก README หลัก

## 1) ใช้ `emr aider` ให้ Local AI แก้ไฟล์จริง

เข้า repo ก่อน:

```bash
cd ~/edge-model-runtime
```

รันแบบ interactive:

```bash
./bin/emr aider
```

จากนั้นพิมพ์คำสั่งใน session เช่น:

```text
Edit README.md and add a short usage section for local AI coding.
```

รันแบบ one-shot:

```bash
./bin/emr aider README.md -- --message "Edit README.md. Add a short Local AI usage section. Commit the change." --yes-always
```

ถ้าจะแก้หลายไฟล์ ให้ระบุไฟล์ไปเลย:

```bash
./bin/emr aider README.md docs/LOCAL_AI_CODING_DEMO.md -- --message "Edit these files. Improve the local AI coding documentation. Commit the changes." --yes-always
```

## 2) ใช้ model อื่นแทน `qwen2.5-coder:7b`

ดู model ที่มี:

```bash
./bin/emr models
```

ดึง model ใหม่ (ใหญ่ขึ้น):

```bash
./bin/emr pull qwen2.5-coder:14b
./bin/emr pull qwen2.5-coder:32b
```

สั่ง `aider` ให้ใช้ model ที่ต้องการ:

```bash
./bin/emr aider --model qwen2.5-coder:14b README.md -- --message "Edit README.md. Add a short explanation of local AI coding. Commit the change." --yes-always
```

ถ้าใช้ 32B:

```bash
./bin/emr aider --model qwen2.5-coder:32b README.md -- --message "Refactor the documentation for clarity. Commit the change." --yes-always
```

## 3) คำสั่งแนะนำสำหรับแก้ code จริง

ตัวอย่างแก้ code แบบระบุไฟล์:

```bash
./bin/emr aider path/to/file.go -- --message "Fix bugs in this Go file. Keep changes minimal. Run formatting if needed. Commit the fix." --yes-always
```

ตัวอย่างให้แก้ทั้ง feature:

```bash
./bin/emr aider --model qwen2.5-coder:14b -- --message "Inspect the repo and add a --dry-run flag to the CLI. Keep changes minimal. Update tests if available. Commit the change." --yes-always
```

> ถ้าใช้ model เล็กอย่าง `qwen2.5-coder:7b` แนะนำให้ระบุไฟล์ให้ชัดเจน เพราะถ้าให้ค้นทั้ง repo เองอาจตอบเป็นคำอธิบายแทนการแก้จริง

## 4) ตรวจผลทุกครั้งหลัง AI แก้

```bash
git status
git diff HEAD~1
git log --oneline -3
```

ถ้ายังไม่ commit แต่ไฟล์ถูกแก้แล้ว:

```bash
git add .
git commit -m "docs: update local AI coding guide"
```

ถ้าจะ push:

```bash
git push origin main
```

## Model ที่ควรใช้

- RAM/VRAM ไม่เยอะ: `qwen2.5-coder:7b`
- แก้ repo/code ได้ดีขึ้น: `qwen2.5-coder:14b`
- งานยากหรือหลายไฟล์: `qwen2.5-coder:32b`

## สรุปจำง่าย

```bash
cd ~/edge-model-runtime
./bin/emr aider --model qwen2.5-coder:14b FILE_TO_EDIT -- --message "Edit this file. Do not only explain. Commit the change." --yes-always
```
