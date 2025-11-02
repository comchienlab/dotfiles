#!/bin/zsh

# Dependencies: gum
# Install: brew install gum

# Source common library functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Try multiple locations for common.sh
if [ -f "$SCRIPT_DIR/lib/common.sh" ]; then
    source "$SCRIPT_DIR/lib/common.sh"
elif [ -f "$(dirname "$SCRIPT_DIR")/lib/common.sh" ]; then
    source "$(dirname "$SCRIPT_DIR")/lib/common.sh"
elif [ -f "$HOME/.local/lib/common.sh" ]; then
    source "$HOME/.local/lib/common.sh"
else
    echo "Error: Cannot find lib/common.sh"
    exit 1
fi

# Ensure gum is installed
ensure_gum_installed

# --- Banner ---
gum style \
	--foreground 212 --border-foreground 212 --border double \
	--align center --width 50 --margin "1 2" --padding "2 4" \
	' macOS Cleaner' 'A TUI for cleaning your macOS system'

confirm_action() {
  gum confirm "Do you want to proceed with cleaning \"$1\"?" && return 0 || return 1
}

# --- Cleaners with gum spin ---
clean_user_cache() {
  local user_cache=~/Library/Caches
  confirm_action "🧹 User Cache ($user_cache)" && {
    gum spin --title "Cleaning User Cache..." -- rm -rf "$user_cache"/*
  }
}

clean_system_cache() {
  local sys_cache=/Library/Caches
  sudo true
  confirm_action "⚙️ System Cache ($sys_cache)" && {
    gum spin --title "Cleaning System Cache..." -- sudo rm -rf "$sys_cache"/*
  }
}

clean_trash() {
  local trash=~/.Trash
  confirm_action "🗑️ Trash ($trash)" && {
    gum spin --title "Emptying Trash..." -- rm -rf "$trash"/*
  }
}

clean_xcode_derived_data() {
  local dd=~/Library/Developer/Xcode/DerivedData
  [[ -d $dd ]] || return 0
  confirm_action "📦 Xcode DerivedData ($dd)" && {
    gum spin --title "Cleaning Xcode DerivedData..." -- rm -rf "$dd"/*
  }
}

restart_finder() {
  confirm_action "🔄 Restart Finder" && {
    gum spin --title "Restarting Finder..." -- killall Finder
  }
}

restart_dock() {
  confirm_action "🔁 Restart Dock" && {
    gum spin --title "Restarting Dock..." -- killall Dock
  }
}

# --- Main Menu ---
main_menu() {
  local options=(
    "🧹 Clean User Cache"
    "⚙️ Clean System Cache"
    "🗑️ Empty Trash"
    "📦 Clean Xcode DerivedData"
    "🔄 Restart Finder"
    "🔁 Restart Dock"
    "🚪 Exit"
  )

  while true; do
    choice=$(gum choose "${options[@]}")
    case "$choice" in
      "🧹 Clean User Cache") clean_user_cache ;;
      "⚙️ Clean System Cache") clean_system_cache ;;
      "🗑️ Empty Trash") clean_trash ;;
      "📦 Clean Xcode DerivedData") clean_xcode_derived_data ;;
      "🔄 Restart Finder") restart_finder ;;
      "🔁 Restart Dock") restart_dock ;;
      "🚪 Exit") break ;;
    esac
    gum confirm "Back to menu?" || break
  done
}

main_menu
