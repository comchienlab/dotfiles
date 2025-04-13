#!/bin/bash

# === Setup PATH ===
export PATH="$HOME/.local/bin:$PATH"

# === Ensure gum is installed ===
if ! command -v gum &> /dev/null; then
    echo "Installing gum..."
    curl -s https://raw.githubusercontent.com/charmbracelet/gum/main/install.sh | bash
    export PATH="$HOME/.local/bin:$PATH"
fi

# === Ensure rclone is installed or updated ===
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

# === Rclone Config Management ===
import_config() {
    config_mode=$(gum choose \
        "Import from local file" \
        "Paste config content" \
        "Show current config content" \
        "Copy current config to clipboard" \
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
        "Copy current config to clipboard")
            if [ -f ~/.config/rclone/rclone.conf ]; then
                if command -v pbcopy &> /dev/null; then
                    cat ~/.config/rclone/rclone.conf | pbcopy
                    gum style --foreground 42 "Copied to clipboard using pbcopy (macOS)."
                elif command -v xclip &> /dev/null; then
                    cat ~/.config/rclone/rclone.conf | xclip -selection clipboard
                    gum style --foreground 42 "Copied to clipboard using xclip (Linux)."
                else
                    gum style --foreground 1 "Clipboard tool not found (pbcopy/xclip)."
                fi
            else
                gum style --foreground 1 "No config file found to copy."
            fi
            ;;
        *)
            return
            ;;
    esac
}

# === Select Local Folder ===
select_local_folder() {
    gum file --directory
}

# === Select Rclone Folder Recursively ===
select_rclone_folder() {
    remote="$1"
    path="$2"

    folder_list=$(rclone lsf --dirs-only "$remote:$path" 2>/dev/null)

    if [ -z "$folder_list" ]; then
        echo "$path"
        return
    fi

    folder_choice=$(echo -e "..\n$folder_list" | gum choose --no-limit --header="📂 Select folder in $remote:$path")

    if [ "$folder_choice" == ".." ]; then
        parent=$(dirname "$path")
        select_rclone_folder "$remote" "$parent"
    else
        new_path="${path%/}/$folder_choice"
        select_rclone_folder "$remote" "$new_path"
    fi
}

# === Manage File Moves ===
manage_files() {
    action=$(gum choose \
        "Move from local to Rclone drive" \
        "Move from Rclone drive to local" \
        "Move from one Rclone remote to another" \
        "Back to main menu")

    case "$action" in
        "Move from local to Rclone drive")
            src_path=$(select_local_folder)
            if [ ! -d "$src_path" ]; then
                gum style --foreground 1 "Invalid local folder!"
                return
            fi
            remote_target=$(gum choose $(rclone listremotes | sed 's/:$//g'))
            dest_path=$(select_rclone_folder "$remote_target" "")
            cmd="rclone move \"$src_path\" \"$remote_target:$dest_path\" -P"
            gum style --foreground 3 "🚀 Starting transfer..."
            echo "$cmd" | gum format
            eval "$cmd" 2>&1 | gum pager
            ;;

        "Move from Rclone drive to local")
            from_remote=$(gum choose $(rclone listremotes | sed 's/:$//g'))
            src_path=$(select_rclone_folder "$from_remote" "")
            dest_path=$(select_local_folder)
            mkdir -p "$dest_path"
            cmd="rclone move \"$from_remote:$src_path\" \"$dest_path\" -P"
            gum style --foreground 3 "🚀 Starting transfer..."
            echo "$cmd" | gum format
            eval "$cmd" 2>&1 | gum pager
            ;;

        "Move from one Rclone remote to another")
            from_remote=$(gum choose $(rclone listremotes | sed 's/:$//g'))
            src_path=$(select_rclone_folder "$from_remote" "")
            to_remote=$(gum choose $(rclone listremotes | sed 's/:$//g'))
            dest_path=$(select_rclone_folder "$to_remote" "")
            cmd="rclone move \"$from_remote:$src_path\" \"$to_remote:$dest_path\" -P"
            gum style --foreground 3 "🚀 Starting transfer..."
            echo "$cmd" | gum format
            eval "$cmd" 2>&1 | gum pager
            ;;

        *)
            return
            ;;
    esac

    gum style --foreground 42 "✅ File move completed."
}

# === Add New Rclone Drive ===
add_drive_config() {
    gum confirm "Open rclone interactive config?" && rclone config
}

# === Main Menu ===
while true; do
    choice=$(gum choose \
        "Install & Update Rclone" \
        "Add or Modify config" \
        "Manage drive" \
        "Manage files" \
        "Exit")

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
        "Exit")
            break
            ;;
    esac
done
#!/bin/bash

# === Setup PATH ===
export PATH="$HOME/.local/bin:$PATH"

# === Ensure gum is installed ===
if ! command -v gum &> /dev/null; then
    echo "Installing gum..."
    curl -s https://raw.githubusercontent.com/charmbracelet/gum/main/install.sh | bash
    export PATH="$HOME/.local/bin:$PATH"
fi

# === Ensure rclone is installed or updated ===
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

# === Rclone Config Management ===
import_config() {
    config_mode=$(gum choose \
        "Import from local file" \
        "Paste config content" \
        "Show current config content" \
        "Copy current config to clipboard" \
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
        "Copy current config to clipboard")
            if [ -f ~/.config/rclone/rclone.conf ]; then
                if command -v pbcopy &> /dev/null; then
                    cat ~/.config/rclone/rclone.conf | pbcopy
                    gum style --foreground 42 "Copied to clipboard using pbcopy (macOS)."
                elif command -v xclip &> /dev/null; then
                    cat ~/.config/rclone/rclone.conf | xclip -selection clipboard
                    gum style --foreground 42 "Copied to clipboard using xclip (Linux)."
                else
                    gum style --foreground 1 "Clipboard tool not found (pbcopy/xclip)."
                fi
            else
                gum style --foreground 1 "No config file found to copy."
            fi
            ;;
        *)
            return
            ;;
    esac
}

# === Select Local Folder ===
select_local_folder() {
    gum file --directory
}

# === Select Rclone Folder Recursively ===
select_rclone_folder() {
    remote="$1"
    path="$2"

    folder_list=$(rclone lsf --dirs-only "$remote:$path" 2>/dev/null)

    if [ -z "$folder_list" ]; then
        echo "$path"
        return
    fi

    folder_choice=$(echo -e "..\n$folder_list" | gum choose --no-limit --header="📂 Select folder in $remote:$path")

    if [ "$folder_choice" == ".." ]; then
        parent=$(dirname "$path")
        select_rclone_folder "$remote" "$parent"
    else
        new_path="${path%/}/$folder_choice"
        select_rclone_folder "$remote" "$new_path"
    fi
}

# === Manage File Moves ===
manage_files() {
    action=$(gum choose \
        "Move from local to Rclone drive" \
        "Move from Rclone drive to local" \
        "Move from one Rclone remote to another" \
        "Back to main menu")

    case "$action" in
        "Move from local to Rclone drive")
            src_path=$(select_local_folder)
            if [ ! -d "$src_path" ]; then
                gum style --foreground 1 "Invalid local folder!"
                return
            fi
            remote_target=$(gum choose $(rclone listremotes | sed 's/:$//g'))
            dest_path=$(select_rclone_folder "$remote_target" "")
            cmd="rclone move \"$src_path\" \"$remote_target:$dest_path\" -P"
            gum style --foreground 3 "🚀 Starting transfer..."
            echo "$cmd" | gum format
            eval "$cmd" 2>&1 | gum pager
            ;;

        "Move from Rclone drive to local")
            from_remote=$(gum choose $(rclone listremotes | sed 's/:$//g'))
            src_path=$(select_rclone_folder "$from_remote" "")
            dest_path=$(select_local_folder)
            mkdir -p "$dest_path"
            cmd="rclone move \"$from_remote:$src_path\" \"$dest_path\" -P"
            gum style --foreground 3 "🚀 Starting transfer..."
            echo "$cmd" | gum format
            eval "$cmd" 2>&1 | gum pager
            ;;

        "Move from one Rclone remote to another")
            from_remote=$(gum choose $(rclone listremotes | sed 's/:$//g'))
            src_path=$(select_rclone_folder "$from_remote" "")
            to_remote=$(gum choose $(rclone listremotes | sed 's/:$//g'))
            dest_path=$(select_rclone_folder "$to_remote" "")
            cmd="rclone move \"$from_remote:$src_path\" \"$to_remote:$dest_path\" -P"
            gum style --foreground 3 "🚀 Starting transfer..."
            echo "$cmd" | gum format
            eval "$cmd" 2>&1 | gum pager
            ;;

        *)
            return
            ;;
    esac

    gum style --foreground 42 "✅ File move completed."
}

# === Add New Rclone Drive ===
add_drive_config() {
    gum confirm "Open rclone interactive config?" && rclone config
}

# === Main Menu ===
while true; do
    choice=$(gum choose \
        "Install & Update Rclone" \
        "Add or Modify config" \
        "Manage drive" \
        "Manage files" \
        "Exit")

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
        "Exit")
            break
            ;;
    esac
done
