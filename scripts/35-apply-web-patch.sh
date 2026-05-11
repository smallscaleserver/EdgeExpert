#!/usr/bin/env bash
# =============================================================================
# 35-apply-web-patch.sh — apply a patch produced in Open WebUI (Web Codex flow)
# =============================================================================
# Bridges the gap between "model wrote a unified diff in the browser" and
# "the change is live in this git repo (and pushed / PR'd if asked)".
#
# Usage:
#   bash scripts/35-apply-web-patch.sh <patch-file>            # apply only
#   bash scripts/35-apply-web-patch.sh <patch-file> --commit   # apply + commit
#   bash scripts/35-apply-web-patch.sh <patch-file> --commit --push
#   bash scripts/35-apply-web-patch.sh <patch-file> --commit --push --pr
#   bash scripts/35-apply-web-patch.sh <patch-file> --force-dirty   # allow WIP
#   cat patch | bash scripts/35-apply-web-patch.sh -           # stdin
#
# Companion to docs/WEB-CODEX-PLAYBOOK.md.
# =============================================================================

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

PATCH_SRC="${1:-}"
shift || true

DO_COMMIT=0
DO_PUSH=0
DO_PR=0
FORCE_DIRTY=0
COMMIT_MSG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --commit)      DO_COMMIT=1 ;;
    --push)        DO_PUSH=1 ;;
    --pr)          DO_PR=1 ;;
    --force-dirty) FORCE_DIRTY=1 ;;
    -m)            COMMIT_MSG="${2:-}"; shift ;;
    *) die "Unknown flag: $1" ;;
  esac
  shift
done

[[ -n "$PATCH_SRC" ]] || die "usage: $0 <patch-file|-> [--commit] [--push] [--pr] [--force-dirty] [-m 'msg']"

cd "$REPO_ROOT"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Not in a git repo"

# Refuse to clobber WIP unless explicitly opted in. With --commit we'd
# otherwise sweep the user's unstaged work into the same commit silently.
if [[ $FORCE_DIRTY -eq 0 ]] && ! git diff --quiet HEAD -- 2>/dev/null; then
  err "Working tree has uncommitted changes."
  log "Re-run with --force-dirty to apply on top, or stash first:"
  log "  git stash push -u -m 'before web-codex'"
  exit 1
fi

# Stage the patch into a tmp file (handles stdin too)
PATCH_FILE="$(mktemp -t web-codex.XXXXXX.patch)"
ERR_FILE="$(mktemp -t web-codex.XXXXXX.err)"
trap 'rm -f "$PATCH_FILE" "$ERR_FILE"' EXIT
if [[ "$PATCH_SRC" == "-" ]]; then
  cat > "$PATCH_FILE"
else
  [[ -f "$PATCH_SRC" ]] || die "Patch not found: $PATCH_SRC"
  cp "$PATCH_SRC" "$PATCH_FILE"
fi

[[ -s "$PATCH_FILE" ]] || die "Patch is empty"

section "🔍 Checking patch applies cleanly"
if ! git apply --check "$PATCH_FILE" 2>"$ERR_FILE"; then
  err "git apply --check failed:"
  cat "$ERR_FILE" >&2
  log ""
  log "Paste this error back into the WebUI chat and ask the model to"
  log "regenerate ONLY the failing hunks as a fresh unified diff."
  exit 1
fi
ok "Patch applies cleanly"

section "✏️  Applying patch"
git apply "$PATCH_FILE"
ok "Applied — review with: git diff"

if [[ $DO_COMMIT -eq 0 ]]; then
  log ""
  log "Next:"
  log "  git diff                         # review"
  log "  bash scripts/03-verify.sh        # smoke test"
  log "  $0 $PATCH_SRC --commit           # re-run with --commit when happy"
  exit 0
fi

section "📦 Committing"
git add -A
if [[ -z "$COMMIT_MSG" ]]; then
  # Default subject pulled from first changed file
  FIRST="$(git diff --cached --name-only | head -1)"
  COMMIT_MSG="web-codex: update ${FIRST:-files}"
fi
git commit -m "$COMMIT_MSG"
ok "Committed"

if [[ $DO_PUSH -eq 1 ]]; then
  section "⬆️  Pushing"
  BRANCH="$(git rev-parse --abbrev-ref HEAD)"
  git push -u origin "$BRANCH"
  ok "Pushed $BRANCH"
fi

if [[ $DO_PR -eq 1 ]]; then
  section "🔀 Creating pull request"
  command -v gh >/dev/null 2>&1 || die "'gh' not installed — install GitHub CLI or open the PR via the web UI"
  gh pr create --fill || warn "gh pr create returned non-zero (PR may already exist)"
fi
