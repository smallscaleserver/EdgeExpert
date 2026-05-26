#!/usr/bin/env bash
# =============================================================================
# 40-public-users.sh — manage devices for the public Open WebUI
# =============================================================================
# Accounts are created automatically on first visit (no tokens needed).
# Use this script to monitor, rename, or block specific devices.
#
# Usage:
#   bash scripts/40-public-users.sh list
#   bash scripts/40-public-users.sh revoke  FINGERPRINT
#   bash scripts/40-public-users.sh enable  FINGERPRINT
#   bash scripts/40-public-users.sh rename  FINGERPRINT "ชื่อใหม่"
# =============================================================================

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"
load_env

DEVICES_FILE="${REPO_ROOT}/public-proxy/devices.json"
ACTION="${1:-list}"

# ---------------------------------------------------------------------------
case "$ACTION" in

  # ── List all known devices ─────────────────────────────────────────────────
  list)
    python3 -c "
import json, sys

try:
    devices = json.load(open('${DEVICES_FILE}'))
except Exception:
    devices = {}

if not devices:
    print('ยังไม่มี device เชื่อมต่อเลย')
    print('แค่เปิด http://\$(hostname -I | awk \"{print \$1}\"):\${PUBLIC_WEBUI_PORT:-3001}/ จากอุปกรณ์ใดก็ได้')
    sys.exit(0)

for fp, d in devices.items():
    status = 'active' if d.get('enabled', True) else 'BLOCKED'
    dev    = d.get('device', {})
    ua     = dev.get('user_agent', '-')
    if len(ua) > 70: ua = ua[:67] + '...'
    print(f'FP      : {fp}  [{status}]')
    print(f'Last    : {d.get(\"last_seen\", \"-\")}  (first: {d.get(\"first_seen\", \"-\")})')
    print(f'Browser : {ua}')
    print(f'TZ      : {dev.get(\"timezone\",\"-\")}  |  Screen: {dev.get(\"screen\",\"-\")}')
    print('-' * 65)
"
    ;;

  # ── Block a device ─────────────────────────────────────────────────────────
  revoke|block)
    FP="${2:-}"
    [[ -n "$FP" ]] || die "Usage: $0 revoke FINGERPRINT"
    python3 -c "
import json, sys
with open('${DEVICES_FILE}') as f: d = json.load(f)
if '${FP}' not in d:
    print('ไม่พบ fingerprint: ${FP}', file=sys.stderr); sys.exit(1)
d['${FP}']['enabled'] = False
with open('${DEVICES_FILE}', 'w') as f: json.dump(d, f, ensure_ascii=False, indent=2); f.write('\n')
"
    ok "Blocked ${FP} — มีผลทันที ไม่ต้อง restart"
    ;;

  # ── Unblock a device ───────────────────────────────────────────────────────
  enable|unblock)
    FP="${2:-}"
    [[ -n "$FP" ]] || die "Usage: $0 enable FINGERPRINT"
    python3 -c "
import json, sys
with open('${DEVICES_FILE}') as f: d = json.load(f)
if '${FP}' not in d:
    print('ไม่พบ fingerprint: ${FP}', file=sys.stderr); sys.exit(1)
d['${FP}']['enabled'] = True
with open('${DEVICES_FILE}', 'w') as f: json.dump(d, f, ensure_ascii=False, indent=2); f.write('\n')
"
    ok "Unblocked ${FP}"
    ;;

  *)
    die "Usage: $0 {list | revoke FP | enable FP}"
    ;;
esac
