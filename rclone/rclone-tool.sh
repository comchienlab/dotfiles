#!/bin/bash

# === Setup PATH ===
export PATH="$HOME/.local/bin:$PATH"

# Source common library functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../lib/common.sh" ]; then
    source "$SCRIPT_DIR/../lib/common.sh"
else
    echo "Error: Cannot find lib/common.sh"
    exit 1
fi

# === Ensure gum is installed via official APT repo ===
ensure_gum_installed

TRANSFER_TRACK_FILE="/tmp/comchienrclone-transfers.json"

append_transfer() {
    jq -n \
        --arg src "$1" \
        --arg dst "$2" \
        --arg log "$3" \
        --arg status "running" \
        '{source: $src, destination: $dst, log: $log, status: $status}' \
        >> "$TRANSFER_TRACK_FILE.tmp"
    if [ -f "$TRANSFER_TRACK_FILE" ]; then
        jq -s '.' "$TRANSFER_TRACK_FILE" "$TRANSFER_TRACK_FILE.tmp" > "$TRANSFER_TRACK_FILE.merged"
        mv "$TRANSFER_TRACK_FILE.merged" "$TRANSFER_TRACK_FILE"
        rm "$TRANSFER_TRACK_FILE.tmp"
    else
        mv "$TRANSFER_TRACK_FILE.tmp" "$TRANSFER_TRACK_FILE"
    fi
}

select_local_path() {
    gum choose "📁 Select a directory" "📄 Select a file" | while read -r choice; do
        case "$choice" in
            "📁 Select a directory") gum file --directory;;
            "📄 Select a file") gum file;;
        esac
    done
}

select_rclone_folder() {
    remote="$1"
    path="$2"
    folder_list=$(rclone lsf --dirs-only "$remote:$path" 2>/dev/null)
    if [ -z "$folder_list" ]; then echo "$path"; return; fi
    folder_choice=$(echo -e "..\n$folder_list" | gum choose --no-limit --header="📂 Select folder in $remote:$path")
    if [ "$folder_choice" == ".." ]; then
        parent=$(dirname "$path")
        select_rclone_folder "$remote" "$parent"
    else
        new_path="${path%/}/$folder_choice"
        select_rclone_folder "$remote" "$new_path"
    fi
}

run_rclone_move_bg() {
    cmd="$1"
    src="$2"
    dst="$3"
    log_file="/tmp/rclone_$(date +%s%N).log"
    append_transfer "$src" "$dst" "$log_file"
    nohup bash -c "$cmd" > "$log_file" 2>&1 &
    gum style --foreground 42 "🚀 Transfer started in background. Returning to menu..."
}

manage_files() {
    action=$(gum choose \
        "Move from local to Rclone drive" \
        "Move from Rclone drive to local" \
        "Move from one Rclone remote to another" \
        "Back to main menu")
    case "$action" in
        "Move from local to Rclone drive")
            src_path=$(select_local_path)
            [ ! -e "$src_path" ] && gum style --foreground 1 "Invalid path" && return
            remote=$(gum choose $(rclone listremotes | sed 's/:$//g'))
            dest=$(select_rclone_folder "$remote" "")
            cmd="rclone move \"$src_path\" \"$remote:$dest\" -P"
            run_rclone_move_bg "$cmd" "$src_path" "$remote:$dest"
            ;;
        "Move from Rclone drive to local")
            remote=$(gum choose $(rclone listremotes | sed 's/:$//g'))
            src=$(select_rclone_folder "$remote" "")
            dest_path=$(select_local_path)
            mkdir -p "$dest_path"
            cmd="rclone move \"$remote:$src\" \"$dest_path\" -P"
            run_rclone_move_bg "$cmd" "$remote:$src" "$dest_path"
            ;;
        "Move from one Rclone remote to another")
            from=$(gum choose $(rclone listremotes | sed 's/:$//g'))
            src=$(select_rclone_folder "$from" "")
            to=$(gum choose $(rclone listremotes | sed 's/:$//g'))
            dest=$(select_rclone_folder "$to" "")
            cmd="rclone move \"$from:$src\" \"$to:$dest\" -P"
            run_rclone_move_bg "$cmd" "$from:$src" "$to:$dest"
            ;;
        *) return;;
    esac
}

view_transfer_progress() {
    [ ! -f "$TRANSFER_TRACK_FILE" ] && gum style --foreground 3 "No transfers yet." && return
    while IFS= read -r row; do
        src=$(echo "$row" | jq -r .source)
        dst=$(echo "$row" | jq -r .destination)
        log=$(echo "$row" | jq -r .log)
        progress=$(tail -n 5 "$log" 2>/dev/null)
        echo "🔄 $src → $dst"
        echo "$progress"
        echo
    done < <(jq -c '.[]' "$TRANSFER_TRACK_FILE") | gum pager
}

install_or_update_rclone() {
    if ! command -v rclone &> /dev/null; then
        gum confirm "Install Rclone now?" && curl https://rclone.org/install.sh | sudo bash
    else
        installed_version=$(rclone version | head -n 1 | awk '{print $2}' | tr -d 'v')
        latest_version=$(curl -s https://api.github.com/repos/rclone/rclone/releases/latest | grep '"tag_name":' | cut -d'"' -f4 | tr -d 'v')
        [ "$installed_version" != "$latest_version" ] && \
            gum confirm "Upgrade Rclone to $latest_version?" && \
            curl https://rclone.org/install.sh | sudo bash
        gum style --foreground 10 "✅ Rclone version $installed_version"
    fi
}

add_drive_config() {
    gum confirm "Open rclone config wizard?" && rclone config
}

import_config() {
    config_mode=$(gum choose \
        "Import from local file" \
        "Paste config content" \
        "Show current config content" \
        "Copy current config to clipboard" \
        "Back to main menu")
    case "$config_mode" in
        "Import from local file")
            config_path=$(gum input --placeholder "Path to rclone.conf")
            [ -f "$config_path" ] && mkdir -p ~/.config/rclone && cp "$config_path" ~/.config/rclone/rclone.conf && gum style --foreground 42 "Config imported."
            ;;
        "Paste config content")
            gum write --width 60 --height 20 > ~/.config/rclone/rclone.conf
            gum style --foreground 42 "Config saved."
            ;;
        "Show current config content")
            [ -f ~/.config/rclone/rclone.conf ] && gum pager < ~/.config/rclone/rclone.conf || gum style --foreground 1 "No config found"
            ;;
        "Copy current config to clipboard")
            if [ -f ~/.config/rclone/rclone.conf ]; then
                if command -v pbcopy &>/dev/null; then cat ~/.config/rclone/rclone.conf | pbcopy
                elif command -v xclip &>/dev/null; then cat ~/.config/rclone/rclone.conf | xclip -selection clipboard
                else gum style --foreground 1 "Clipboard tool missing"
                fi
                gum style --foreground 42 "Copied to clipboard"
            fi
            ;;
    esac
}

while true; do
    choice=$(gum choose \
        "Install & Update Rclone" \
        "Add or Modify config" \
        "Manage drive" \
        "Manage files" \
        "View transfer progress" \
        "Exit")
    case "$choice" in
        "Install & Update Rclone") install_or_update_rclone;;
        "Add or Modify config") import_config;;
        "Manage drive") add_drive_config;;
        "Manage files") manage_files;;
        "View transfer progress") view_transfer_progress;;
        "Exit") break;;
    esac
done
