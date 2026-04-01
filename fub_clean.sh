#!/usr/bin/env bash
# ================================================
# Ubuntu Cleanup Assistant PRO v2.7
# Arrow menu ↑ ↓ Enter Esc • Fix pipe + sudo • Pure Bash
# ================================================

set -euo pipefail

VERSION="2.7"

# ==================== COLORS ====================
if command -v tput >/dev/null 2>&1; then
  BOLD="$(tput bold)"
  DIM="$(tput dim)"
  RED="$(tput setaf 1)"
  GREEN="$(tput setaf 2)"
  YELLOW="$(tput setaf 3)"
  BLUE="$(tput setaf 4)"
  MAGENTA="$(tput setaf 5)"
  CYAN="$(tput setaf 6)"
  RESET="$(tput sgr0)"
else
  BOLD="" DIM="" RED="" GREEN="" YELLOW="" BLUE="" MAGENTA="" CYAN="" RESET=""
fi

print_line() { printf "%b\n" "${DIM}────────────────────────────────────────────────────────${RESET}"; }

title() {
  clear
  print_line
  printf "%b\n" "${BOLD}${CYAN}🧹 Ubuntu Cleanup Assistant PRO v${VERSION}${RESET}"
  print_line
}

# ==================== ROOT CHECK ====================
if [[ $EUID -ne 0 ]]; then
  echo -e "${YELLOW}→ Cần sudo để chạy${RESET}"
  echo -e "${CYAN}Dùng lệnh này:${RESET}"
  echo -e "   curl -fsSL https://raw.githubusercontent.com/comchienlab/dotfiles/main/fub_clean.sh | sudo bash"
  exit 1
fi

# ==================== ROBUST ARROW MENU (fix crash) ====================
select_option() {
  local options=("$@")
  local num_options=${#options[@]}
  local selected=0
  local key key2

  # Lưu và set terminal raw mode
  local old_stty
  old_stty=$(stty -g)
  stty raw -echo
  trap 'stty "$old_stty"' EXIT

  while true; do
    # Vẽ menu
    for i in "${!options[@]}"; do
      if [ "$i" -eq "$selected" ]; then
        printf " ${GREEN}❯ %s${RESET}\n" "${options[$i]}"
      else
        printf "   %s\n" "${options[$i]}"
      fi
    done

    # Đọc phím từ /dev/tty (fix pipe crash)
    IFS= read -rsn1 key < /dev/tty
    case "$key" in
      $'\e')
        IFS= read -rsn2 -t 0.1 key2 < /dev/tty 2>/dev/null
        case "$key2" in
          '[A') selected=$(( (selected - 1 + num_options) % num_options )) ;;
          '[B') selected=$(( (selected + 1) % num_options )) ;;
        esac
        ;;
      "") 
        stty "$old_stty" 2>/dev/null
        trap - EXIT
        return "$selected" 
        ;;
      "q"|"Q") 
        stty "$old_stty" 2>/dev/null
        trap - EXIT
        return 255 
        ;;
    esac

    # Xóa menu cũ
    printf "\033[%dA\033[J" "$num_options"
  done
}

ask() {
  read -r -p "$(printf "%b" "${CYAN}❯ $1 [y/N]: ${RESET}")" answer < /dev/tty
  [[ "${answer:-N}" =~ ^[Yy]$ ]]
}

ok() { printf "%b\n" "${GREEN}✔ $1${RESET}"; }
warn() { printf "%b\n" "${YELLOW}⚠ $1${RESET}"; }
fail() { printf "%b\n" "${RED}✖ $1${RESET}"; }

run_cmd() {
  local label="$1"
  shift
  printf "%b\n" "${DIM}→ $label${RESET}"
  if "$@"; then ok "$label"; else fail "$label"; fi
}

get_free_space() { df -h / | awk 'NR==2 {print $4}'; }

progress() {
  local percent=$((CURRENT_STEP * 100 / TOTAL_STEPS))
  local done=$((percent / 5))
  local left=$((20 - done))
  fill=$(printf "%0.s█" $(seq 1 $done 2>/dev/null || true))
  empty=$(printf "%0.s░" $(seq 1 $left 2>/dev/null || true))
  printf "%b\n" "${BOLD}${BLUE}Progress${RESET} [${GREEN}${fill}${DIM}${empty}${RESET}] ${percent}%"
}

step() {
  CURRENT_STEP=$((CURRENT_STEP + 1))
  printf "\n%b\n" "${BOLD}${MAGENTA}[$CURRENT_STEP/$TOTAL_STEPS] $1${RESET}"
  progress
}

choose_mode() {
  echo -e "\n${BOLD}${BLUE}Chọn chế độ dọn dẹp:${RESET}\n"
  local options=(
    "Light      - Chỉ dọn cơ bản (APT, logs, trash)"
    "Deep       - Khuyến nghị (nên chọn)"
    "Aggressive - Dọn mạnh nhất (tất cả)"
  )
  select_option "${options[@]}"
  local choice=$?
  case $choice in
    0) MODE="light" ;;
    1) MODE="deep" ;;
    2) MODE="aggressive" ;;
    *) MODE="deep" ;;
  esac
  echo -e "${GREEN}→ Chế độ: ${MODE^}${RESET}\n"
}

# ==================== CLEANUP FUNCTIONS (giữ nguyên) ====================
cleanup_apt() { step "APT"; run_cmd "Update & Upgrade" sudo apt update && sudo apt upgrade -y; run_cmd "Autoremove" sudo apt autoremove --purge -y; run_cmd "Clean" sudo apt clean; }

cleanup_logs() { step "Logs"; run_cmd "Vacuum journal" sudo journalctl --vacuum-time=7d --vacuum-size=300M; }

cleanup_trash() { step "Trash"; run_cmd "Clear trash & temp" rm -rf "${HOME}/.local/share/Trash/"* 2>/dev/null || true && sudo find /tmp -mindepth 1 -mtime +7 -delete 2>/dev/null || true; }

cleanup_basic_cache() { step "Basic Cache"; run_cmd "Thumbnails" rm -rf "${HOME}/.cache/thumbnails/"* 2>/dev/null || true; }

cleanup_browser_cache() { step "Browser Cache"; run_cmd "Clear" rm -rf "${HOME}/.cache/mozilla/"* "${HOME}/.cache/google-chrome/"* "${HOME}/.cache/chromium/"* 2>/dev/null || true; }

cleanup_dev_cache() { step "Dev Cache"; command -v npm >/dev/null && run_cmd "npm" npm cache clean --force; command -v pip >/dev/null && run_cmd "pip" pip cache purge; rm -rf "${HOME}/.gradle/caches/"* 2>/dev/null || true; }

cleanup_snap() { step "Snap"; if command -v snap >/dev/null; then sudo snap set system refresh.retain=2; LANG=C snap list --all | awk '/disabled/{print $1,$3}' | while read -r n r; do [ -n "$n" ] && run_cmd "Remove $n" sudo snap remove "$n" --revision="$r"; done; fi; }

cleanup_flatpak() { step "Flatpak"; command -v flatpak >/dev/null && run_cmd "Unused" flatpak uninstall -y --unused; }

cleanup_docker() { step "Docker"; if command -v docker >/dev/null; then run_cmd "Prune" docker system prune -a -f; fi; }

purge_old_apps() { step "Purge old apps"; if ask "Muốn xóa app cũ?"; then echo; apt-mark showmanual | sort; echo; read -r -p "${CYAN}Nhập tên gói (cách space): ${RESET}" pkgs < /dev/tty; [ -n "$pkgs" ] && sudo apt purge -y $pkgs && sudo apt autoremove --purge -y; fi; }

summary() {
  print_line
  printf "%b\n" "${BOLD}${GREEN}✅ Hoàn tất!${RESET}"
  printf "📊 Dung lượng trống sau: ${BLUE}%s${RESET}\n" "$(get_free_space)"
  print_line
}

main() {
  title
  choose_mode
  echo -e "${DIM}Dung lượng trước: $(get_free_space)${RESET}\n"

  ask "Bật Dry-run (chỉ xem, không xóa)?" && DRY_RUN=true || DRY_RUN=false
  if ! ask "🚀 BẮT ĐẦU DỌN NGAY?"; then warn "Hủy"; exit 0; fi

  CURRENT_STEP=0
  TOTAL_STEPS=9

  cleanup_apt
  cleanup_logs
  cleanup_trash
  cleanup_basic_cache

  if [[ "$MODE" != "light" ]]; then
    ask "Dọn browser cache?" && cleanup_browser_cache || { CURRENT_STEP=$((CURRENT_STEP+1)); progress; }
    ask "Dọn dev cache?" && cleanup_dev_cache || { CURRENT_STEP=$((CURRENT_STEP+1)); progress; }
  else
    CURRENT_STEP=$((CURRENT_STEP+2)); progress
  fi

  ask "Dọn Snap?" && cleanup_snap || { CURRENT_STEP=$((CURRENT_STEP+1)); progress; }
  ask "Dọn Flatpak?" && cleanup_flatpak || { CURRENT_STEP=$((CURRENT_STEP+1)); progress; }
  ask "Dọn Docker?" && cleanup_docker || { CURRENT_STEP=$((CURRENT_STEP+1)); progress; }
  purge_old_apps

  summary
}

main
