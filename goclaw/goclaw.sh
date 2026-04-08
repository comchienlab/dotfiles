#!/usr/bin/env bash

# ══════════════════════════════════════════════════════════════════
#  GoClaw Manager — Local SSH wrapper
#  Chạy trên máy LOCAL, quản lý GoClaw VPS qua SSH
#  Usage: bash goclaw.sh [--host user@ip]
# ══════════════════════════════════════════════════════════════════

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
B='\033[0;34m'; C='\033[0;36m'; W='\033[1m'; N='\033[0m'

ok()  { echo -e "${G}[✔]${N} $*"; }
inf() { echo -e "${B}[→]${N} $*"; }
wrn() { echo -e "${Y}[!]${N} $*"; }
die() { echo -e "${R}[✘]${N} $*" >&2; exit 1; }
hr()  { echo -e "${C}──────────────────────────────────────────${N}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="${HOME}/.goclaw.conf"

# ── Defaults ───────────────────────────────────────────────────────
VPS_USER="root"
VPS_HOST=""
VPS_SSH_KEY=""

# ── Load config ────────────────────────────────────────────────────
load_config() {
  [[ -f "$CONF_FILE" ]] && { source "$CONF_FILE" 2>/dev/null || true; }
}

save_config() {
  cat > "$CONF_FILE" << EOF
# GoClaw manager config — $(date '+%Y-%m-%d')
VPS_USER="${VPS_USER}"
VPS_HOST="${VPS_HOST}"
VPS_SSH_KEY="${VPS_SSH_KEY}"
EOF
  chmod 600 "$CONF_FILE"
}

# ── SSH helper ─────────────────────────────────────────────────────
ssh_args() {
  local args=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)
  [[ -n "$VPS_SSH_KEY" ]] && args+=(-i "$VPS_SSH_KEY")
  echo "${args[@]}"
}

vps_ssh() {
  # shellcheck disable=SC2046
  ssh $(ssh_args) "${VPS_USER}@${VPS_HOST}" "$@"
}

check_ssh() {
  inf "Kiểm tra SSH đến ${VPS_USER}@${VPS_HOST}..."
  # shellcheck disable=SC2046
  if ! ssh $(ssh_args) -o BatchMode=yes "${VPS_USER}@${VPS_HOST}" "echo ok" &>/dev/null; then
    wrn "SSH không kết nối được. Kiểm tra lại host/key."
    read -rp "  Tiếp tục? [y/N] " _c
    [[ "${_c:-N}" =~ ^[Yy]$ ]] || return 1
  else
    ok "SSH OK"
  fi
}

# ── Parse CLI args ─────────────────────────────────────────────────
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --host) VPS_HOST="$2"; shift 2 ;;
      --user) VPS_USER="$2"; shift 2 ;;
      --key)  VPS_SSH_KEY="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
}

# ── Setup connection ───────────────────────────────────────────────
setup_connection() {
  if [[ -z "$VPS_HOST" ]]; then
    echo ""
    echo -e "${W}Cấu hình kết nối VPS${N}"
    hr

    echo -e "\n${W}VPS Host (IP hoặc hostname):${N}"
    read -rp "  → Host: " VPS_HOST
    [[ -z "$VPS_HOST" ]] && die "VPS host không được để trống"

    echo -e "\n${W}VPS User [${VPS_USER}]:${N}"
    read -rp "  → User (Enter = ${VPS_USER}): " _u
    VPS_USER="${_u:-$VPS_USER}"

    echo -e "\n${W}SSH Key (Enter để dùng SSH agent):${N}"
    echo -e "  ${B}Ví dụ: ~/.ssh/id_rsa${N}"
    read -rp "  → Key path: " _k
    if [[ -n "$_k" ]]; then
      _k="${_k/#\~/$HOME}"
      [[ -f "$_k" ]] || wrn "Key không tồn tại: ${_k}"
      VPS_SSH_KEY="$_k"
    fi

    save_config
    echo ""
  fi
}

# ══════════════════════════════════════════════════════════════════
#  Menu actions
# ══════════════════════════════════════════════════════════════════

cmd_setup() {
  echo ""
  echo -e "${W}Setup VPS — copy & chạy goclaw-setup.sh${N}"
  hr

  local setup_script="${SCRIPT_DIR}/goclaw-setup.sh"
  [[ -f "$setup_script" ]] || die "Không tìm thấy: ${setup_script}"

  check_ssh || return 1

  inf "Upload goclaw-setup.sh lên /tmp/goclaw-setup.sh..."
  # shellcheck disable=SC2046
  scp $(ssh_args) "$setup_script" "${VPS_USER}@${VPS_HOST}:/tmp/goclaw-setup.sh" \
    || die "Upload thất bại"
  ok "Uploaded"

  echo ""
  echo -e "${Y}Chạy setup script trên VPS — bạn sẽ cần nhập thông tin cấu hình...${N}"
  echo ""
  # Run interactive — forward stdin/stdout
  # shellcheck disable=SC2046
  ssh $(ssh_args) -t "${VPS_USER}@${VPS_HOST}" "bash /tmp/goclaw-setup.sh && rm -f /tmp/goclaw-setup.sh"
}

cmd_deploy() {
  echo ""
  echo -e "${W}Deploy — Build local + copy lên VPS${N}"
  hr

  local deploy_script="${SCRIPT_DIR}/goclaw-deploy.sh"
  [[ -f "$deploy_script" ]] || die "Không tìm thấy: ${deploy_script}"

  # Pass VPS connection info to deploy script
  local extra_args=()
  [[ -n "$VPS_HOST" ]] && extra_args+=(--host "$VPS_HOST")
  [[ -n "$VPS_USER" ]] && extra_args+=(--user "$VPS_USER")
  [[ -n "$VPS_SSH_KEY" ]] && extra_args+=(--key "$VPS_SSH_KEY")

  bash "$deploy_script" "${extra_args[@]}"
}

cmd_status() {
  echo ""
  echo -e "${W}Service status${N}"
  hr
  check_ssh || return 1
  vps_ssh "systemctl status goclaw --no-pager -l 2>/dev/null || echo 'Service goclaw không tìm thấy'"
}

cmd_logs() {
  echo ""
  echo -e "${W}GoClaw logs${N} ${B}(Ctrl+C để thoát)${N}"
  hr
  check_ssh || return 1
  echo -e "  ${B}journalctl -u goclaw -f --no-hostname${N}"
  echo ""
  # shellcheck disable=SC2046
  ssh $(ssh_args) -t "${VPS_USER}@${VPS_HOST}" "journalctl -u goclaw -f --no-hostname"
}

cmd_restart() {
  echo ""
  echo -e "${W}Restart GoClaw${N}"
  hr
  check_ssh || return 1
  inf "Restarting..."
  vps_ssh "systemctl restart goclaw && sleep 2 && systemctl status goclaw --no-pager | head -20"
  ok "Done"
}

cmd_db_status() {
  echo ""
  echo -e "${W}Database status${N}"
  hr
  check_ssh || return 1
  vps_ssh "
    echo '─── PostgreSQL ───'
    systemctl is-active postgresql 2>/dev/null && systemctl status postgresql --no-pager | head -10 || echo 'PostgreSQL không chạy (có thể dùng external DB)'
    echo ''
    echo '─── GoClaw DB URL ───'
    grep 'DATABASE_URL' /etc/goclaw.env 2>/dev/null | sed 's/:\/\/[^:]*:[^@]*@/:\/\/***:***@/' || echo 'Không tìm thấy /etc/goclaw.env'
  "
}

cmd_edit_config() {
  echo ""
  echo -e "${W}Edit config trên VPS${N}"
  hr
  check_ssh || return 1
  # shellcheck disable=SC2046
  ssh $(ssh_args) -t "${VPS_USER}@${VPS_HOST}" \
    "nano /etc/goclaw.env && systemctl restart goclaw && echo 'Restarted.' && systemctl status goclaw --no-pager | head -10"
}

cmd_info() {
  echo ""
  echo -e "${W}GoClaw info trên VPS${N}"
  hr
  check_ssh || return 1
  vps_ssh "
    echo '─── Service ───'
    systemctl is-active goclaw 2>/dev/null && echo 'Status: RUNNING' || echo 'Status: STOPPED'
    echo ''
    echo '─── Binary ───'
    ls -lh /usr/local/bin/goclaw 2>/dev/null || echo 'Binary chưa cài'
    /usr/local/bin/goclaw --version 2>/dev/null || true
    echo ''
    echo '─── Config ───'
    grep -E '^(PORT|HOST|DOMAIN|DB_MODE|TZ|INTERNAL_PORT|EXTERNAL_PORT)=' /etc/goclaw.env 2>/dev/null || echo 'Không tìm thấy config'
    echo ''
    echo '─── Ports ───'
    ss -tlnp 2>/dev/null | grep -E 'goclaw|:3000|:8080|:443|:80' || netstat -tlnp 2>/dev/null | grep -E 'goclaw|:3000|:8080' || true
    echo ''
    echo '─── Memory ───'
    free -h
    echo ''
    echo '─── Disk ───'
    df -h /
  "
}

cmd_ssh() {
  echo ""
  echo -e "${W}SSH vào VPS${N}"
  hr
  check_ssh || return 1
  echo -e "  ${B}Kết nối đến ${VPS_USER}@${VPS_HOST}...${N}"
  echo ""
  # shellcheck disable=SC2046
  exec ssh $(ssh_args) -t "${VPS_USER}@${VPS_HOST}"
}

cmd_change_host() {
  echo ""
  echo -e "${W}Đổi VPS host${N}"
  hr
  echo -e "  Host hiện tại: ${Y}${VPS_USER}@${VPS_HOST}${N}"
  echo ""
  VPS_HOST=""
  VPS_USER="root"
  VPS_SSH_KEY=""
  setup_connection
  ok "Đã cập nhật kết nối: ${VPS_USER}@${VPS_HOST}"
}

# ══════════════════════════════════════════════════════════════════
#  Main menu loop
# ══════════════════════════════════════════════════════════════════
show_menu() {
  clear
  echo -e "${C}${W}"
  cat << 'BANNER'
   ██████╗  ██████╗  ██████╗██╗      █████╗ ██╗    ██╗
  ██╔════╝ ██╔═══██╗██╔════╝██║     ██╔══██╗██║    ██║
  ██║  ███╗██║   ██║██║     ██║     ███████║██║ █╗ ██║
  ██║   ██║██║   ██║██║     ██║     ██╔══██║██║███╗██║
  ╚██████╔╝╚██████╔╝╚██████╗███████╗██║  ██║╚███╔███╔╝
   ╚═════╝  ╚═════╝  ╚═════╝╚══════╝╚═╝  ╚═╝ ╚══╝╚══╝
BANNER
  echo -e "${N}"
  hr
  if [[ -n "$VPS_HOST" ]]; then
    echo -e "  VPS  : ${G}${W}${VPS_USER}@${VPS_HOST}${N}"
  else
    echo -e "  VPS  : ${Y}(chưa cấu hình)${N}"
  fi
  hr
  echo ""
  echo -e "  ${W}1${N}) Setup VPS      — cài GoClaw lần đầu hoặc update"
  echo -e "  ${W}2${N}) Deploy         — build local + copy lên VPS"
  echo -e "  ${W}3${N}) Status         — xem trạng thái service"
  echo -e "  ${W}4${N}) Logs           — xem logs realtime"
  echo -e "  ${W}5${N}) Restart        — restart service"
  echo -e "  ${W}6${N}) Info           — thông tin hệ thống VPS"
  echo -e "  ${W}7${N}) Database       — trạng thái database"
  echo -e "  ${W}8${N}) Edit config    — sửa /etc/goclaw.env trên VPS"
  echo -e "  ${W}9${N}) SSH            — mở SSH session vào VPS"
  echo -e "  ${W}c${N}) Đổi VPS host"
  echo -e "  ${W}0${N}) Thoát"
  echo ""
  hr
}

main() {
  load_config
  parse_args "$@"

  # Ensure VPS connection is configured
  setup_connection

  while true; do
    show_menu
    read -rp "  → Chọn: " _choice

    case "$_choice" in
      1) cmd_setup ;;
      2) cmd_deploy ;;
      3) cmd_status ;;
      4) cmd_logs ;;
      5) cmd_restart ;;
      6) cmd_info ;;
      7) cmd_db_status ;;
      8) cmd_edit_config ;;
      9) cmd_ssh ;;
      c|C) cmd_change_host ;;
      0|q|Q) echo ""; echo "Tạm biệt!"; exit 0 ;;
      *) wrn "Lựa chọn không hợp lệ: ${_choice}" ;;
    esac

    echo ""
    read -rp "  Nhấn Enter để quay lại menu..." _
  done
}

main "$@"
