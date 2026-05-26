#!/usr/bin/env bash
# =============================================================================
# 01-public.sh — start/stop the no-login public Open WebUI (port PUBLIC_WEBUI_PORT)
# =============================================================================
# Usage:
#   bash scripts/01-public.sh start   (or: make public)
#   bash scripts/01-public.sh stop    (or: make public-stop)
#
# The public instance runs at http://<HOST>:${PUBLIC_WEBUI_PORT:-3001}/
# No login is required — anyone with the URL can use it immediately.
# To disable access permanently, run: bash scripts/01-public.sh stop
# =============================================================================

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

ACTION="${1:-start}"
load_env

PORT="${PUBLIC_WEBUI_PORT:-3001}"

case "$ACTION" in
  start|up)
    section "▶️  Starting public Open WebUI (no-login) on port ${PORT}"
    check_docker
    check_compose_v2
    check_data_root || die "Run scripts/00-install.sh first"

    compose --profile public up -d --build public-auth public-nginx open-webui-public

    sleep 2
    ok "Public WebUI stack starting"
    log ""
    log "  เพิ่ม user และรับ URL ส่วนตัว:"
    log "    bash scripts/40-public-users.sh add \"ผู้ใหญ่ A\""
    log "    bash scripts/40-public-users.sh add \"ผู้ใหญ่ B\""
    log ""
    log "  แสดงรายชื่อ user ทั้งหมด:"
    log "    bash scripts/40-public-users.sh list"
    log ""
    log "  ปิดการใช้งาน: bash scripts/01-public.sh stop"
    ;;

  stop|down)
    section "⏹  Stopping public Open WebUI"
    check_docker
    compose --profile public stop public-auth public-nginx open-webui-public
    ok "Public WebUI stopped. Main WebUI at port ${WEBUI_PORT:-3000} is unaffected."
    ;;

  *)
    die "Usage: $0 {start|stop}"
    ;;
esac
