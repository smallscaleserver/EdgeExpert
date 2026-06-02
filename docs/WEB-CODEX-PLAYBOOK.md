# Local "Codex-style" coding workflow ผ่านเว็บ (Web)

คู่มือนี้ทำให้คุณใช้งาน **local model** ให้ฟีลใกล้เคียง Claude Code / ChatGPT Codex แต่ทำทั้งหมดผ่านเบราว์เซอร์บนสแตกนี้ (Open WebUI + Ollama)

## เป้าหมาย

- ใช้ผ่านเว็บ 100% (ไม่ต้องเปิด TUI)
- ให้โมเดลตอบแบบ agentic coding: วางแผน → แก้โค้ด → สรุปเทสต์
- รักษาความเป็น local-first (งาน inference อยู่ที่ Ollama ในเครื่อง)

## 1) เตรียมระบบ

```bash
bash scripts/01-start.sh
bash scripts/04-pull-model.sh qwen3-coder:30b
bash scripts/03-verify.sh
```

จากนั้นเปิด `http://localhost:3000`

> ถ้าต้องการ model เล็กลง ให้ใช้ `qwen2.5-coder:7b`

## 2) ตั้งค่า Model Preset ใน Open WebUI

1. เข้า **Workspace → Models**
2. เลือก `qwen3-coder:30b` หรือ `qwen3-coder-next:latest`
3. ตั้ง **System Prompt** เป็น template ด้านล่าง
4. ตั้ง Temperature = `0.1` ถึง `0.2`
5. เปิดใช้งาน model เป็นค่า default สำหรับงานโค้ด

### System Prompt (Codex-style)

คัดลอกไปวางทั้งก้อน:

```text
You are a senior software engineer working in a local git repository.

Operating mode:
1) Start with a short plan (3-7 bullets).
2) Make minimal, safe changes focused on the request.
3) After edits, provide a concise diff-style summary by file.
4) Propose exact test commands, expected outcomes, and rollback steps.
5) If requirements are ambiguous, state assumptions explicitly before changes.

Code quality bar:
- Prefer small composable functions.
- Keep backward compatibility unless user approves breaking changes.
- Add or update docs when behavior changes.
- Never fabricate command results; clearly mark unverified steps.

Output format:
- Summary
- Files Changed
- Test Commands
- Risks / Rollback
```

## 3) Workflow ที่แนะนำ (เหมือน Codex/Claude Code)

ใช้ pattern นี้ทุกครั้งในแชต:

```text
Context:
- Repo: <ชื่อโปรเจกต์>
- Goal: <สิ่งที่ต้องการ>
- Constraints: <ห้ามเปลี่ยนอะไร/ต้องรองรับอะไร>

Tasks:
1) วิเคราะห์ไฟล์ที่เกี่ยวข้อง
2) เสนอแผนแก้ไขแบบสั้น
3) สร้าง patch รายไฟล์ (unified diff)
4) ระบุคำสั่งทดสอบ
5) สรุปผลลัพธ์และความเสี่ยง
```

### โหมดใช้งานที่ใกล้ Codex ที่สุด (แนะนำ)

เพื่อให้ได้ผลลัพธ์เหมือน "agent coding" มากขึ้น ให้แยกเป็น 2 รอบ:

- **รอบ A (Plan):** ให้โมเดลวิเคราะห์ไฟล์ที่ต้องแก้ + เสนอแผนสั้น ๆ
- **รอบ B (Patch):** ให้โมเดลส่งเฉพาะ `unified diff` ที่ apply ได้ทันที

Prompt สำหรับรอบ B:

```text
Now output ONLY a unified diff patch.
Rules:
- No explanation text outside the diff.
- Keep changes minimal.
- Include file paths relative to repo root.
```

## 4) ขั้นตอน apply patch กลับเข้า git repo (นอกเบราว์เซอร์)

แม้จะทำงานหลักผ่านเว็บ แต่การแก้ไฟล์จริงยังต้อง apply ใน repo ของคุณ

### วิธีลัด (แนะนำ) — `make apply-patch`

วาง diff จากหน้าเว็บลง `/tmp/web.patch` แล้วเรียก:

```bash
# แค่ apply เพื่อ review ก่อน commit
make apply-patch P=/tmp/web.patch

# apply + commit (เว้นวรรคใน MSG ใช้ได้)
make apply-patch P=/tmp/web.patch COMMIT=1 MSG="fix: handle empty config"

# apply + commit + push + เปิด PR (ต้องเคย gh auth login แล้ว)
make apply-patch P=/tmp/web.patch COMMIT=1 PUSH=1 PR=1

# กรณีตั้งใจ apply ทับ WIP ที่ค้างใน tree
make apply-patch P=/tmp/web.patch FORCE=1
```

เบื้องหลังคือ `scripts/35-apply-web-patch.sh` ทำสามขั้น:
1. ปฏิเสธถ้า working tree สกปรก เพื่อกัน WIP โดน sweep รวม commit (ใช้ `FORCE=1` ข้าม)
2. `git apply --check` ก่อน — ถ้าไม่ผ่านจะพิมพ์ error ให้วางกลับเข้า WebUI
3. apply แล้ว commit / push / เปิด PR ตามแฟล็ก

### วิธีแมนนวล (ทำเองทีละขั้น)

```bash
cat > /tmp/web-codex.patch       # วาง diff จากเว็บ
git apply --check /tmp/web-codex.patch
git apply /tmp/web-codex.patch
bash scripts/03-verify.sh
git status --short && git diff
```

> ถ้า `git apply --check` ไม่ผ่าน ให้ส่ง error กลับไปในแชต แล้วขอให้โมเดล regenerate patch เฉพาะจุดที่พัง

## 5) เพิ่ม cloud model ใน dropdown เดียวกัน (optional)

ถ้าต้องการสลับ local/cloud แบบหน้าเว็บเดียว:

```bash
bash scripts/32-setup-cloud-models.sh
```

แล้ว refresh หน้าเว็บ จะเลือก local Ollama และ Claude/GPT/Gemini ได้ใน model dropdown เดียวกัน

## 6) Prompt พร้อมใช้งาน (copy/paste)

### A) Refactor แบบปลอดภัย

```text
Refactor function <name> in <file>.
Constraints:
- keep function signature
- no behavior change
- add tests for edge cases
Return:
- plan
- unified diff
- test commands
```

### B) แก้บั๊กพร้อม root cause

```text
Investigate bug:
<อาการ>

Deliverables:
1) root cause hypothesis
2) minimal patch
3) regression test
4) rollback plan
```

### C) ทำเอกสารประกอบ PR

```text
From the proposed patch, draft a PR description with:
- problem
- solution
- risks
- test evidence
```

### D) Prompt สไตล์ "ลงมือแก้เลย"

```text
Act as a coding agent for this repository.
First: list assumptions.
Second: provide a 3-7 bullet plan.
Third: output a minimal unified diff patch.
Fourth: provide exact test commands and expected results.
Fifth: provide rollback steps.
```

## 7) ข้อจำกัดที่ควรรู้

- ผ่านเว็บจะไม่สามารถแก้ไฟล์ในเครื่องได้อัตโนมัติเท่า CLI agent
- แนวทางที่เหมาะคือ: ให้โมเดลสร้าง patch/diff แล้วคุณ apply จริงด้วย git
- ถ้าต้องการ agent แก้ไฟล์อัตโนมัติ ให้ใช้ Option A/B/D ใน `docs/AI-CODING-SETUP.md`

## 8) แนะนำโมเดลสำหรับงานโค้ด

- แม่นและคุ้ม: `qwen2.5-coder:14b`
- เครื่องเล็ก: `qwen2.5-coder:7b`
- งานยาก/ไฟล์ใหญ่: `qwen2.5-coder:32b`

ดูรายละเอียดเพิ่มใน `docs/MODEL-RECOMMENDATIONS.md`

## 9) Checklist ก่อนส่ง PR

- รันเทสต์ที่เกี่ยวข้องจริงในเครื่อง (`bash scripts/03-verify.sh` อย่างน้อย)
- แนบผลลัพธ์คำสั่งที่สำคัญ (pass/fail) ในคำอธิบาย PR
- ถ้าเป็น patch ใหญ่ ให้แยก commit เป็นก้อนเล็ก ๆ ที่รีวิวง่าย
