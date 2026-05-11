# Contributing

Thanks for your interest. A few rules to keep this stack reliable:

## Hard rules

1. **Never break model persistence.** Any change to `docker-compose.yml` or scripts must preserve the bind-mount `${AI_DATA_ROOT}/ollama → /root/.ollama`.
2. **Test the rebuild path.** Before submitting a PR:
   ```bash
   bash scripts/02-stop.sh
   bash scripts/01-start.sh
   bash scripts/05-list-models.sh   # must show pre-existing models
   ```
3. **No `latest` or `main` tags** in `.env.versions` for production. Pinned semver only.
4. **No `chmod 777`.** Use `u+rwX,g+rwX,o-rwx`.
5. **Heavy images stay opt-in.** vLLM and PyTorch training images must remain behind Compose profiles. `00-install.sh` only pulls Ollama, Open WebUI, and the small CUDA test image.

## Style

- Bash with `set -euo pipefail` (sourced from `scripts/lib/common.sh`).
- All scripts source `lib/common.sh` and use the `compose`, `load_env`, `confirm`, `info`/`ok`/`warn`/`err` helpers.
- Shell scripts pass `shellcheck -x`.
- Markdown wraps at a reasonable width.

## Adding a new service

1. Add to `docker-compose.yml` under a profile if heavy (`profiles: ["myservice"]`).
2. Use a bind-mount under `${AI_DATA_ROOT}/<service-name>` for any persistent data.
3. Update:
   - `08-disk-report.sh` (so the new path shows up)
   - `10-cleanup-docker.sh` (so its image is cleaned)
   - `20-wipe-models.sh` (so its data is wiped)
   - `docs/ARCHITECTURE.md` (mention it)
   - `README.md` (one-liner)

## Updating image versions

1. Verify the new tag exists upstream.
2. Edit `.env.versions`.
3. Run `bash scripts/09-update-images.sh` locally and verify with `bash scripts/03-verify.sh`.
4. Note the previous version in your PR description in case rollback is needed.

## PR checklist

- [ ] Shellcheck passes (`shellcheck -x scripts/**/*.sh`)
- [ ] `docker compose config` validates
- [ ] Rebuild test: models survive `02-stop.sh` → `01-start.sh`
- [ ] Updated relevant docs (`README.md`, `docs/`, `CLAUDE.md` if invariants changed)
- [ ] No `latest`/`main` tags introduced
- [ ] No `chmod 777`
