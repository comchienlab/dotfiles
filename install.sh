#!/bin/bash

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

# Create the installation directories
INSTALL_DIR="$HOME/.local/bin"
LIB_DIR="$HOME/.local/lib"
mkdir -p "$INSTALL_DIR"
mkdir -p "$LIB_DIR"

# Add the installation directory to PATH if not already present
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
fi

# Download and install the common library first
print_message "$BLUE" "Installing common library..."
REPO_URL="https://raw.githubusercontent.com/comchienlab/dotfiles/main"

if curl -sSL "$REPO_URL/lib/common.sh" -o "$LIB_DIR/common.sh"; then
    chmod +x "$LIB_DIR/common.sh"
    print_message "$GREEN" "✓ Successfully installed common library"
else
    print_message "$RED" "✗ Failed to install common library"
    exit 1
fi

# Download and install the f files
QK_FILES=("fgit.sh" "fsetup.sh" "qkcommit.sh")

for file in "${QK_FILES[@]}"; do
    # Remove .sh extension for the command name
    command_name="${file%.sh}"
    target_path="$INSTALL_DIR/$command_name"
    
    print_message "$BLUE" "Installing $command_name..."
    
    # Download the file
    if curl -sSL "$REPO_URL/$file" -o "$target_path"; then
        # Update the script to look for common.sh in ~/.local/lib
        sed -i.bak 's|source "$SCRIPT_DIR/lib/common.sh"|source "$HOME/.local/lib/common.sh"|g' "$target_path"
        sed -i.bak 's|source "$(dirname "$SCRIPT_DIR")/lib/common.sh"|source "$HOME/.local/lib/common.sh"|g' "$target_path"
        rm -f "$target_path.bak"
        
        # Make it executable
        chmod +x "$target_path"
        print_message "$GREEN" "✓ Successfully installed $command_name"
    else
        print_message "$RED" "✗ Failed to install $command_name"
    fi
done

print_message "$GREEN" "Installation completed!\nPlease restart your terminal or run:\n    source ~/.bashrc (if using bash)\n    source ~/.zshrc  (if using zsh)\n\nAvailable commands:\n    fgit   - Quick Git operations\n    fsetup - Quick Setup operations\n    qkcommit - Quick Commit operations"
