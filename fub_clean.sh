#!/usr/bin/env bash
# ================================================
# Ubuntu Cleanup Assistant PRO v4.2
# Banner mới theo yêu cầu của bạn
# ================================================

set -euo pipefail

VERSION="4.2"

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

# ==================== BANNER MỚI (bạn vừa gửi) ====================
show_banner() {
  printf "%b" "${BOLD}${CYAN}"
  echo "▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄"
  echo "█░▄▄░█░█▀█░██░█░▄▄▀███▀▄▀█░██░▄▄█░▄▄▀█░▄▄▀██"
  echo "█░▀▀░█░▄▀█░██░█░▄▄▀███░█▀█░██░▄▄█░▀▀░█░██░██"
  echo "████░█▄█▄██▄▄▄█▄▄▄▄████▄██▄▄█▄▄▄█▄██▄█▄██▄██"
  echo "▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀"
  printf "%b" "${RESET}"
}

title() {
  clear 2>/dev/null || printf "\033[2J\033[H"
  show_banner
  print_line
}

if [[ $EUID -ne 0 ]]; then
  echo -e "${YELLOW}→ Cần sudo để chạy${RESET}"
  echo -e "${CYAN}Lệnh mượt nhất:${RESET}"
  echo "   sudo bash <(curl -fsSL https://raw.githubusercontent.com/comchienlab/dotfiles/main/fub_clean.sh)"
  exit 1
fi

exec < /dev/tty > /dev/tty 2>&1

# ==================== YES/NO DỌC ====================
select_yes_no() {
  local prompt="$1"
  local selected=0
  local key key2

  while true; do
    printf "\033[2J\033[H"
    show_banner
    print_line
    echo -e "${BOLD}${BLUE}$prompt${RESET}\n"

    if [ "$selected" -eq 0 ]; then
      echo -e " ${GREEN}➤ Yes${RESET}"
      echo -e "   No"
    else
      echo -e "   Yes"
      echo -e " ${GREEN}➤ No${RESET}"
    fi

    echo -e "\n${DIM}↑↓ = di chuyển • Enter = chọn${RESET}"

    IFS= read -rsn1 key < /dev/tty
    case "$key" in
      $'\e')
        IFS= read -rsn2 -t 0.1 key2 < /dev/tty 2>/dev/null
        case "$key2" in
          '[A'|'[B') selected=$((1 - selected)) ;;
        esac
        ;;
      "") return "$selected" ;;
      "q"|"Q") echo -e "${YELLOW}Đã hủy.${RESET}"; exit 0 ;;
    esac
  done
}

# ==================== MULTI-SELECT CIRCLE ====================
multi_select() {
  local items=("$@")
  local checked=()
  local selected=0
  local key key2

  for i in "${!items[@]}"; do checked[i]=0; done
  for i in "${!checked[@]}"; do [ "$i" -ne $(( ${#items[@]}-1 )) ] && checked[i]=1; done

  while true; do
    printf "\033[2J\033[H"
    show_banner
    print_line
    echo -e "${BOLD}${BLUE}Chọn các mục muốn dọn (Space = chọn/bỏ):${RESET}\n"

    for i in "${!items[@]}"; do
      mark=$([ "${checked[$i]}" -eq 1 ] && echo "${GREEN}●${RESET}" || echo "○")
      if [ "$i" -eq "$selected" ]; then
        printf " ${GREEN}➤ %s %s${RESET}\n" "$mark" "${items[$i]}"
      else
        printf "   %s %s\n" "$mark" "${items[$i]}"
      fi
    done

    echo -e "\n${DIM}↑↓ = di chuyển • Space = tick/untick • Enter = xác nhận • q = thoát${RESET}"

    IFS= read -rsn1 key < /dev/tty
    case "$key" in
      $'\e')
        IFS= read -rsn2 -t 0.1 key2 < /dev/tty 2>/dev/null
        case "$key2" in
          '[A') selected=$(( (selected - 1 + ${#items[@]}) % ${#items[@]} )) ;;
          '[B') selected=$(( (selected + 1) % ${#items[@]} )) ;;
        esac
        ;;
      " ") 
        [ "${checked[$selected]}" -eq 1 ] && checked[selected]=0 || checked[selected]=1
        ;;
      "") 
        SELECTED_ITEMS=()
        for i in "${!items[@]}"; do
          [ "${checked[$i]}" -eq 1 ] && SELECTED_ITEMS+=("${items[$i]}")
        done
        return 0
        ;;
      "q"|"Q") echo -e "${YELLOW}Đã hủy.${RESET}"; exit 0 ;;
    esac
  done
}

# ==================== HÀM HỖ TRỢ ====================
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

step() {
  CURRENT_STEP=$((CURRENT_STEP + 1))
  printf "\n%b\n" "${BOLD}${MAGENTA}[$CURRENT_STEP/$TOTAL_STEPS] $1${RESET}"
}

# ==================== CLEANUP FUNCTIONS ====================
cleanup_apt() { step "APT"; run_cmd "Update & Upgrade" sudo apt update && sudo apt upgrade -y; run_cmd "Autoremove" sudo apt autoremove --purge -y; run_cmd "Clean" sudo apt clean; }
cleanup_logs() { step "Logs"; run_cmd "Vacuum" sudo journalctl --vacuum-time=7d --vacuum-size=300M; }
cleanup_trash() { step "Trash"; run_cmd "Clear" rm -rf "${HOME}/.local/share/Trash/"* 2>/dev/null || true && sudo find /tmp -mindepth 1 -mtime +7 -delete 2>/dev/null || true; }
cleanup_basic() { step "Basic Cache"; run_cmd "Thumbnails" rm -rf "${HOME}/.cache/thumbnails/"* 2>/dev/null || true; }
cleanup_browser() { step "Browser"; run_cmd "Clear" rm -rf "${HOME}/.cache/mozilla/"* "${HOME}/.cache/google-chrome/"* "${HOME}/.cache/chromium/"* 2>/dev/null || true; }
cleanup_dev() { step "Dev Cache"; command -v npm >/dev/null && run_cmd "npm" npm cache clean --force; command -v pip >/dev/null && run_cmd "pip" pip cache purge; rm -rf "${HOME}/.gradle/caches/"* 2>/dev/null || true; }
cleanup_snap() { step "Snap"; if command -v snap >/dev/null; then sudo snap set system refresh.retain=2; LANG=C snap list --all | awk '/disabled/{print $1,$3}' | while read -r n r; do [ -n "$n" ] && run_cmd "Remove $n" sudo snap remove "$n" --revision="$r"; done; fi; }
cleanup_flatpak() { step "Flatpak"; command -v flatpak >/dev/null && run_cmd "Unused" flatpak uninstall -y --unused; }
cleanup_docker() { step "Docker"; if command -v docker >/dev/null; then run_cmd "Prune" docker system prune -a -f; fi; }
purge_apps() { step "Purge old apps"; if select_yes_no "Muốn purge app cũ?"; then echo; apt-mark showmanual | sort; echo; read -r -p "${CYAN}Nhập gói (cách space): ${RESET}" pkgs < /dev/tty; [ -n "$pkgs" ] && sudo apt purge -y $pkgs && sudo apt autoremove --purge -y; fi; }

# ==================== MAIN ====================
main() {
  title
  echo -e "${DIM}Dung lượng hiện tại: $(get_free_space)${RESET}\n"

  local options=(
    "APT System Cleanup"
    "System Logs"
    "Trash & Temp files"
    "Basic Cache"
    "Browser Caches"
    "Developer Caches"
    "Snap Cleanup"
    "Flatpak Cleanup"
    "Docker Cleanup"
    "Purge old apps (manual)"
  )

  multi_select "${options[@]}"

  if [ ${#SELECTED_ITEMS[@]} -eq 0 ]; then
    warn "Không chọn mục nào → thoát."
    exit 0
  fi

  select_yes_no "Bật Dry-run (chỉ xem, không xóa)?" && DRY_RUN=true || DRY_RUN=false
  select_yes_no "🚀 BẮT ĐẦU DỌN NGAY?" || { warn "Hủy."; exit 0; }

  CURRENT_STEP=0
  TOTAL_STEPS=${#SELECTED_ITEMS[@]}

  for item in "${SELECTED_ITEMS[@]}"; do
    case "$item" in
      "APT System Cleanup") cleanup_apt ;;
      "System Logs") cleanup_logs ;;
      "Trash & Temp files") cleanup_trash ;;
      "Basic Cache") cleanup_basic ;;
      "Browser Caches") cleanup_browser ;;
      "Developer Caches") cleanup_dev ;;
      "Snap Cleanup") cleanup_snap ;;
      "Flatpak Cleanup") cleanup_flatpak ;;
      "Docker Cleanup") cleanup_docker ;;
      "Purge old apps (manual)") purge_apps ;;
    esac
  done

  summary
}

summary() {
  print_line
  printf "%b\n" "${BOLD}${GREEN}✅ Hoàn tất!${RESET}"
  printf "📊 Dung lượng sau: ${BLUE}%s${RESET}\n" "$(get_free_space)"
  print_line
}

main
