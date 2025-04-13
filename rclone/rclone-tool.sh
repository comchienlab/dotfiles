#!/bin/bash

# Function to ensure gum is installed
ensure_gum() {
    if ! command -v gum &> /dev/null; then
        echo "Gum not found. Installing..."
        curl -s https://raw.githubusercontent.com/charmbracelet/gum/main/install.sh | bash
        export PATH="$HOME/.local/bin:$PATH"
    fi
}

# Function to install or update rclone
install_or_update_rclone() {
    if ! command -v rclone &> /dev/null; then
        gum confirm "Rclone is not installed. Install now?" && \
        curl https://rclone.org/install.sh | sudo bash
    else
        installed_version=$(rclone version | head -n 1 | awk '{print $2}' | tr -d 'v')
        latest_version=$(curl -s https://api.github.com/repos/rclone/rclone/releases/latest | grep '"tag_name":' | cut -d'"' -f4 | tr -d 'v')
        if [ "$installed_version" != "$latest_version" ]; then
            gum confirm "Rclone is outdated (installed: $installed_version, latest: $latest_version). Upgrade now?" && \
            curl https://rclone.org/install.sh | sudo bash
        else
            gum style --foreground 10 "Rclone is up to date (version $installed_version)."
        fi
    fi
}

# Function to manage rclone config
import_config() {
    config_mode=$(gum choose \
        "Import from local file" \
        "Paste config content" \
        "Show current config content" \
        "Back to main menu")

    case "$config_mode" in
        "Import from local file")
            config_path=$(gum input --placeholder "Enter full path to rclone.conf file")
            if [ -f "$config_path" ]; then
                mkdir -p ~/.config/rclone
                cp "$config_path" ~/.config/rclone/rclone.conf
                gum style --foreground 42 "Config imported successfully."
            else
                gum style --foreground 1 "File not found!"
            fi
            ;;
        "Paste config content")
            gum write --width 60 --height 20 --placeholder "Paste your rclone config here" > ~/.config/rclone/rclone.conf
            gum style --foreground 42 "Config saved."
            ;;
        "Show current config content")
            if [ -f ~/.config/rclone/rclone.conf ]; then
                gum pager < ~/.config/rclone/rclone.conf
            else
                gum style --foreground 1 "No config file found at ~/.config/rclone/rclone.conf"
            fi
            ;;
        *)
            return
            ;;
    esac
}

# Function to add new remote drive
add_drive_config() {
    gum confirm "Open rclone interactive config?" && rclone config
}

# Function for copy/move
file_transfer() {
    mode=$1
    src_path=$(gum input --placeholder "Enter local source path")
    remote_list=$(rclone listremotes)

    if [ -z "$remote_list" ]; then
        gum style --foreground 1 "No remotes found. Please configure rclone first using 'rclone config'."
        return
    fi

    remote_target=$(gum choose $(echo "$remote_list" | sed 's/:$//g'))
    dest_path=$(gum input --placeholder "Enter destination path on remote (e.g. backup/my-folder)")

    if [ "$mode" == "Copy" ]; then
        rclone copy "$src_path" "$remote_target:$dest_path" -P
    else
        rclone move "$src_path" "$remote_target:$dest_path" -P
    fi

    gum style --foreground 42 "$mode completed successfully."
}

manage_files() {
    action=$(gum choose \
        "Move from local to Rclone drive" \
        "Move from Rclone drive to local" \
        "Move from one Rclone remote to another" \
        "Back to main menu")

    case "$action" in
        "Move from local to Rclone drive")
            choose_method=$(gum choose "Select folder" "Type path manually")
            if [ "$choose_method" == "Select folder" ]; then
                src_path=$(gum file --directory)
            else
                src_path=$(gum input --placeholder "Enter local source path")
            fi

            if [ ! -d "$src_path" ]; then
                gum style --foreground 1 "Invalid local source path!"
                return
            fi

            remote_target=$(gum choose $(rclone listremotes | sed 's/:$//g'))
            dest_path=$(gum input --placeholder "Enter destination path on remote")
            rclone move "$src_path" "$remote_target:$dest_path" -P
            ;;

        "Move from Rclone drive to local")
            remote_source=$(gum choose $(rclone listremotes | sed 's/:$//g'))
            src_path=$(gum input --placeholder "Enter source path on remote")
            dest_path=$(gum input --placeholder "Enter local destination path")

            mkdir -p "$dest_path"
            rclone move "$remote_source:$src_path" "$dest_path" -P
            ;;

        "Move from one Rclone remote to another")
            from_remote=$(gum choose $(rclone listremotes | sed 's/:$//g'))
            src_path=$(gum input --placeholder "Enter source path on source remote")

            to_remote=$(gum choose $(rclone listremotes | sed 's/:$//g'))
            dest_path=$(gum input --placeholder "Enter destination path on target remote")

            rclone move "$from_remote:$src_path" "$to_remote:$dest_path" -P
            ;;

        *)
            return
            ;;
    esac

    gum style --foreground 42 "File move operation completed."
}

# === Main Execution ===
ensure_gum

while true; do
    choice=$(gum choose "Install & Update Rclone" "Add or Modify config" "Manage drive" "Manage files" "Exit")

    case "$choice" in
        "Install & Update Rclone")
            install_or_update_rclone
            ;;
        "Add or Modify config")
            import_config
            ;;
        "Manage drive")
            add_drive_config
            ;;

        "Manage files")
            manage_files
            ;;

        "Copy file")
            file_transfer "Copy"
            ;;
        "Move file")
            file_transfer "Move"
            ;;
        "Exit")
            break
            ;;
    esac
done
