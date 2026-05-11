# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

A Docker-based runtime for local LLMs on Linux + NVIDIA. Targets MSI EdgeXpert and NVIDIA DGX Spark but works on any Ubuntu+NVIDIA machine. Core services (Ollama + Open WebUI) plus optional profiles for LiteLLM cloud proxy, OpenHands web IDE, vLLM, and PyTorch training.

## Non-negotiable invariants

1. **Models live on the host**, never inside container layers. The bind mount `${AI_DATA_ROOT}/ollama → /root/.ollama` is the entire reason this stack works. Do not replace it with named volumes. Do not add a second mount for "models" elsewhere.
2. **Rebuilds must not re-download models.** Test any compose change with: `docker compose down && docker compose up -d` — `ollama list` afterwards must show the same models.
3. **Four cleanup tiers are deliberate** — do not collapse them:
   - `02-stop.sh` — containers only (models + images intact)
   - `10-cleanup-docker.sh` — containers + images (models intact)
   - `11-remove-host-tools.sh` — host wrappers + MCP registrations + npm globals (manifest-driven)
   - `20-wipe-models.sh` — everything, requires typed `DELETE ALL` phrase
   - `17-uninstall-systemd.sh` belongs to tier 1x (host config, not Docker)
4. **No `chmod 777`.** Use `u+rwX,g+rwX,o-rwx`.
5. **No `latest` or `main` tags in `.env.versions`** for production. Pinned tags only.
6. **New heavy services are opt-in via Compose profiles.** Do not add them to the default `compose up` path, and do not pull them in `00-install.sh`.

## Development commands

```bash
make lint          # shellcheck all scripts
make test          # compose render + safety invariants (chmod 777, unpinned tags, DELETE ALL guard)
make quick-check   # lint + test together (use before committing)
make format        # normalize execute bits on scripts/*.sh and bin/emr
make hooks-install # install commit-msg and pre-commit hooks
```

CI runs these same checks: `shellcheck`, `docker compose config`, and the invariant checks from `make test`. See `.github/workflows/ci.yml`.

After any compose or script change:
```bash
bash scripts/02-stop.sh
bash scripts/01-start.sh
bash scripts/03-verify.sh
bash scripts/05-list-models.sh   # must still show pre-existing models
```

## Where things live

| Concern | File |
|---|---|
| Service definitions | `docker-compose.yml` |
| Runtime config (paths, ports, tunables, secrets) | `.env` (from `.env.example`) |
| Pinned image tags | `.env.versions` |
| LiteLLM cloud/local model registry | `litellm/config.yaml` |
| Declarative model registry | `models.txt` (parsed by `scripts/lib/models.sh`) |
| Shared bash helpers | `scripts/lib/common.sh` |
| Host-artifact manifest | `${AI_DATA_ROOT}/.manifest.list` (managed by `scripts/lib/manifest.sh`) |
| Operations | `scripts/NN-*.sh` (numbered by lifecycle stage) |
| Unified CLI dispatcher | `bin/emr` |
| Architecture rationale | `docs/ARCHITECTURE.md` |
| AI coding options (A–F) | `docs/AI-CODING-SETUP.md` |
| User-facing fixes | `docs/TROUBLESHOOTING.md` |

## Unified CLI — `bin/emr`

`bin/emr` is a façade that maps named subcommands to the numbered scripts. After `scripts/00-install.sh` installs the symlink, all operations are available as `emr <subcommand>`. Key subcommands:

```
emr install          →  scripts/00-install.sh
emr start / up       →  scripts/01-start.sh
emr stop  / down     →  scripts/02-stop.sh
emr status           →  scripts/03-verify.sh
emr pull <model>     →  scripts/04-pull-model.sh
emr sync             →  scripts/04b-sync-models.sh   (sync all models in models.txt)
emr models           →  scripts/05-list-models.sh
emr disk             →  scripts/08-disk-report.sh
emr cleanup [--full] →  scripts/10-cleanup-docker.sh (--full also runs 11)
emr wipe             →  scripts/20-wipe-models.sh
emr setup <profile>  →  scripts/3x-setup-*.sh
emr apply-patch <f>  →  scripts/35-apply-web-patch.sh
```

`emr help` prints the full list. `emr help <subcommand>` shows subcommand-specific help.

## Script numbering convention

Scripts are numbered by lifecycle stage. Multiple scripts can share the same numeric prefix:

| Range | Stage |
|---|---|
| `00–09` | Install / start / day-to-day operations |
| `10–19` | Cleanup (reversible; models preserved) |
| `20–29` | Destructive (model data at risk) |
| `30–39` | One-time setup / AI coding profiles |

## AI coding setup profiles (`emr setup <profile>`)

Each profile is a one-time wizard that installs host wrappers and/or MCP servers. Every artifact it installs is registered in the manifest so `emr cleanup --full` / `11-remove-host-tools.sh` can undo it.

| Profile | Script | What it installs |
|---|---|---|
| `opencode` | `30-setup-opencode.sh` | `opencode` npm global, `opencode.json` wired to Ollama/LiteLLM |
| `claude-code` | `31-setup-claude-code.sh` | MCP server (Ollama) registered with `claude mcp add` |
| `cloud-models` | `32-setup-cloud-models.sh` | Sets `ANTHROPIC_API_KEY`, `LITELLM_MASTER_KEY`, starts `--profile cloud` |
| `claude-local` | `33-setup-claude-local.sh` | `claude-local` wrapper pointing at LiteLLM → Ollama |
| `coding-web` | `36-setup-coding-web.sh` | Starts OpenHands (`--profile coding-web`) |
| `lmstudio` | `37-setup-lmstudio.sh` | Wires host LM Studio into LiteLLM config |
| `claude-lmstudio` | `38-setup-claude-lmstudio.sh` | `claude-lmstudio` wrapper pointing at LM Studio directly |
| `hooks` | `34-install-hooks.sh` | `commit-msg` + `pre-commit` hooks from `.githooks/` |

## Shared library functions (scripts/lib/)

**`common.sh`** — sourced by every script. Key helpers beyond the obvious:
- `compose <args>` — always passes `--env-file .env --env-file .env.versions`; use this wrapper, never raw `docker compose`
- `env_get KEY` / `env_set KEY VALUE` — read/write `.env` safely (preserves comments, deduplicates)
- `pick_install_dir` / `install_wrapper NAME SRC` — install a host wrapper to `/usr/local/bin` or `~/.local/bin` (sudo only when needed)
- `wait_url URL [TIMEOUT] [--any]` — poll a URL until 2xx (or any HTTP code)

**`manifest.sh`** — tracks every host-side artifact created by setup scripts (wrapper paths, `claude mcp` names, npm globals). `manifest_add KIND VALUE` / `manifest_drain` / `manifest_clear`. Cleanup tier 1x reads and drains the manifest.

**`models.sh`** — parses `models.txt`. `models_list_enabled` returns one Ollama model spec per line. `!` prefix disables a model without deleting it.

## Compose profiles

```bash
compose up -d                              # core: ollama + open-webui only
compose --profile cloud up -d litellm      # adds LiteLLM proxy (cloud LLMs)
compose --profile coding-web up -d openhands  # adds OpenHands web IDE
compose --profile vllm up -d vllm         # adds vLLM (large, opt-in)
compose --profile training run --rm training bash  # one-shot training shell
```

Always use the `compose` wrapper from `common.sh` — it always passes both env files.

## LiteLLM model config (`litellm/config.yaml`)

Add a model by appending an entry under `model_list`. The `model_name` is the public ID clients see; `litellm_params.model` tells LiteLLM which backend to call:
- Cloud: `anthropic/claude-sonnet-4-6` (needs `ANTHROPIC_API_KEY` in `.env`)
- Local via Ollama: `ollama_chat/qwen2.5-coder:7b` with `api_base: http://ollama:11434`

After editing: `compose --profile cloud up -d --force-recreate litellm`

## Web Codex patch flow

```bash
# Apply a unified diff produced by a model in Open WebUI:
bash scripts/35-apply-web-patch.sh <patch-file>            # apply only
bash scripts/35-apply-web-patch.sh <patch-file> --commit   # apply + commit
bash scripts/35-apply-web-patch.sh <patch-file> --commit --push --pr
# Via make:
make apply-patch P=/tmp/x.patch COMMIT=1 PUSH=1 PR=1 MSG="fix: handle empty config"
```

The script refuses a dirty working tree by default; pass `--force-dirty` or stash first.

## aider coding CLI

```bash
# Local mode (Ollama, no outbound AI calls):
cd /your/project && bash /path/to/edge-model-runtime/scripts/06-coding-cli.sh

# Cloud mode (LiteLLM → Anthropic):
bash scripts/06-coding-cli.sh --cloud

# One-shot (non-interactive):
bash scripts/06-coding-cli.sh -- --message "add type hints" --yes-always
```

Runs `paulgauthier/aider` in Docker on `edge-ai-net`, bind-mounts `$(pwd)` as `/workspace` with host UID:GID. Persistent config at `${AI_DATA_ROOT}/coding-cli/`.

## Systemd auto-start

```bash
bash scripts/07-install-systemd.sh --enable   # install + enable on boot
bash scripts/07-install-systemd.sh --reinstall # overwrite existing unit
bash scripts/17-uninstall-systemd.sh           # tier-1x removal
```

The unit uses `ExecStop=compose stop` (not `down`) so containers are stopped but not removed. COMPOSE_PROFILES is read from `.env` at install time and baked into the unit.

## Secrets backup

```bash
bash scripts/19-backup-secrets.sh              # plain copy to ${AI_DATA_ROOT}/backups/env/<ts>/
bash scripts/19-backup-secrets.sh --gpg <id>   # GPG-encrypt for recipient
```

Refuses to run if `ANTHROPIC_API_KEY` is still a placeholder.

## Common requests and how to handle them

- **"Add a new model"** → don't edit code; run `bash scripts/04-pull-model.sh <name>` or add to `models.txt` and run `bash scripts/04b-sync-models.sh`.
- **"Add a new service"** → add to `docker-compose.yml` under a Compose profile if heavy. Bind-mount persistent data under `${AI_DATA_ROOT}/<service>`. Update `08-disk-report.sh` and `10-cleanup-docker.sh` image lists. Register the image tag in `.env.versions`.
- **"Update images"** → edit `.env.versions`, then run `bash scripts/09-update-images.sh`.
- **"Reset everything"** → `bash scripts/20-wipe-models.sh` then `bash scripts/00-install.sh`.
- **"Add a cloud model"** → edit `litellm/config.yaml`, force-recreate litellm container.

## Claude Code permissions (`.claude/settings.json`)

The allow-list covers read-only Docker commands, safe scripts, and writes to `scripts/`, `docs/`, `bin/`, `docker-compose.yml`, `.env.example`, `.env.versions`, and `.claude/`. The deny-list blocks `20-wipe-models.sh`, `docker volume rm`, `sudo rm -rf`, `docker system prune`, and edits to `.env`.

## Things to push back on

- Switching to Docker named volumes (loses host visibility, harder backup)
- Adding `chmod 777` "to fix permissions" (wrong fix; check ownership instead)
- Pinning to `latest` or `main` (breaks reproducibility)
- Auto-pulling vLLM/training images in `00-install.sh` (large download, opt-in is intentional)
- Collapsing cleanup tiers into one script (loses the safety ladder)
- Running `docker compose` directly without the `compose` wrapper (skips env files)
