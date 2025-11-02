#!/bin/bash

# Source common library functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/common.sh" ]; then
    source "$SCRIPT_DIR/lib/common.sh"
else
    echo "Error: Cannot find lib/common.sh"
    exit 1
fi

# Ensure gum is installed
ensure_gum_installed

# Create the installation directory
INSTALL_DIR="$HOME/.local/bin"
mkdir -p "$INSTALL_DIR"

# Add the installation directory to PATH if not already present
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
fi

# Download and install the f files
QK_FILES=("fgit.sh" "fsetup.sh" "qkcommit.sh")
REPO_URL="https://raw.githubusercontent.com/comchienlab/dotfiles/main"

for file in "${QK_FILES[@]}"; do
    # Remove .sh extension for the command name
    command_name="${file%.sh}"
    target_path="$INSTALL_DIR/$command_name"
    
    print_message "$BLUE" "Installing $command_name..."
    
    # Download the file
    if curl -sSL "$REPO_URL/$file" -o "$target_path"; then
        # Make it executable
        chmod +x "$target_path"
        print_message "$GREEN" "✓ Successfully installed $command_name"
    else
        print_message "$RED" "✗ Failed to install $command_name"
    fi
done

print_message "$GREEN" "Installation completed!\nPlease restart your terminal or run:\n    source ~/.bashrc (if using bash)\n    source ~/.zshrc  (if using zsh)\n\nAvailable commands:\n    fgit   - Quick Git operations\n    fsetup - Quick Setup operations\n    qkcommit - Quick Commit operations"
