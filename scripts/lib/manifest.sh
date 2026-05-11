#!/usr/bin/env bash
# =============================================================================
# scripts/lib/manifest.sh — track host-side artifacts created by setup scripts
# =============================================================================
# The bind-mount strategy keeps models on the host disk, but the AI-coding
# setup scripts (31/33/37/38, etc.) also drop wrappers in /usr/local/bin or
# ~/.local/bin and register MCP servers with `claude mcp add`. None of those
# live under $AI_DATA_ROOT, so a `docker compose down` + `rm -rf $AI_DATA_ROOT`
# would leave them behind as orphans.
#
# This file is a tiny manifest: a newline-delimited list of "kind\tvalue"
# tuples that describes what the setup scripts installed outside the repo.
# Cleanup tiers (10, 11, 20) read it and remove what's listed.
#
# Source AFTER common.sh so $REPO_ROOT and load_env are available:
#   source "$(dirname "$0")/lib/common.sh"
#   source "$(dirname "$0")/lib/manifest.sh"
#
# Manifest lives under $AI_DATA_ROOT (so it's removed by 20-wipe-models.sh as
# a side effect when the user opts to wipe everything). If $AI_DATA_ROOT
# isn't set yet (very early install path), the manifest is a no-op.
# =============================================================================

# Resolve the manifest path lazily — $AI_DATA_ROOT may not be loaded yet.
manifest_path() {
  if [[ -z "${AI_DATA_ROOT:-}" ]]; then
    return 1
  fi
  printf '%s/.manifest.list' "$AI_DATA_ROOT"
}

# Append "kind\tvalue" to the manifest, deduping. Returns 0 even if no
# manifest is configured (silently noop) so callers can be unconditional.
#   manifest_add KIND VALUE
manifest_add() {
  local kind="$1" value="$2" file
  file="$(manifest_path)" || return 0
  mkdir -p "$(dirname "$file")"
  touch "$file"
  if ! grep -Fxq -- "$kind"$'\t'"$value" "$file" 2>/dev/null; then
    printf '%s\t%s\n' "$kind" "$value" >> "$file"
  fi
}

# Convenience: register a host-side path (wrapper script, symlink, etc.)
manifest_add_path() {
  manifest_add path "$1"
}

# Convenience: register a Claude Code MCP server name (so `claude mcp remove`
# can be called on cleanup).
manifest_add_mcp() {
  manifest_add mcp "$1"
}

# Convenience: register an npm global package name.
manifest_add_npm() {
  manifest_add npm "$1"
}

# List entries of a given kind, one value per line.
manifest_list() {
  local kind="$1" file
  file="$(manifest_path)" || return 0
  [[ -f "$file" ]] || return 0
  awk -F'\t' -v k="$kind" '$1 == k { print $2 }' "$file"
}

# Drop a single entry (kind+value match).
manifest_remove() {
  local kind="$1" value="$2" file tmp
  file="$(manifest_path)" || return 0
  [[ -f "$file" ]] || return 0
  tmp="$(mktemp)"
  grep -vFx -- "$kind"$'\t'"$value" "$file" > "$tmp" || true
  install -m 0640 "$tmp" "$file"
  rm -f "$tmp"
}

# Print every entry, one per line, kind\tvalue.
manifest_dump() {
  local file
  file="$(manifest_path)" || return 0
  [[ -f "$file" ]] || return 0
  cat "$file"
}

# Best-effort removal of every artifact in the manifest, in the safe order
# (mcp regs, then files, then npm globals). Caller decides when to drain.
# Each step warns on failure but never aborts — partial cleanup is better
# than no cleanup.
manifest_drain() {
  local kind value
  while IFS=$'\t' read -r kind value; do
    [[ -z "$kind" ]] && continue
    case "$kind" in
      mcp)
        if command -v claude >/dev/null 2>&1; then
          if claude mcp remove "$value" --scope user >/dev/null 2>&1; then
            ok "removed MCP: $value"
          else
            warn "could not remove MCP '$value' (already gone?)"
          fi
        else
          warn "claude CLI missing — leaving MCP '$value' registration in place"
        fi
        ;;
      path)
        if [[ -e "$value" || -L "$value" ]]; then
          if [[ -w "$(dirname "$value")" ]]; then
            if rm -f -- "$value"; then ok "removed $value"; else warn "could not remove $value"; fi
          elif command -v sudo >/dev/null 2>&1; then
            if sudo rm -f -- "$value"; then ok "removed $value"; else warn "could not remove $value"; fi
          else
            warn "$value: no permission to remove (need sudo)"
          fi
        fi
        ;;
      npm)
        if command -v npm >/dev/null 2>&1; then
          if npm uninstall -g "$value" >/dev/null 2>&1; then
            ok "uninstalled npm global: $value"
          elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
            if sudo npm uninstall -g "$value" >/dev/null 2>&1; then
              ok "uninstalled npm global: $value"
            else
              warn "could not uninstall npm global '$value'"
            fi
          else
            warn "could not uninstall npm global '$value' (need sudo or npm prefix)"
          fi
        else
          warn "npm missing — leaving npm global '$value' in place"
        fi
        ;;
      *)
        warn "manifest: unknown kind '$kind' for value '$value'"
        ;;
    esac
  done < <(manifest_dump)
}

# Drop the manifest file itself (after a drain).
manifest_clear() {
  local file
  file="$(manifest_path)" || return 0
  rm -f "$file"
}
