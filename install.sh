#!/bin/bash

# Define colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to print colored messages
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Check if gum is installed
if ! command -v gum &> /dev/null; then
    echo "Gum is required but not installed. Installing..."
    # Detect OS and install gum
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        echo "Detected macOS, installing via Homebrew..."
        brew install gum
    else
        # Ubuntu/Debian
        echo "Detected Linux, installing via APT..."
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
        echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
        sudo apt update && sudo apt install -y gum
    fi    
fi

# Create the installation directory
INSTALL_DIR="$HOME/.local/bin"
mkdir -p "$INSTALL_DIR"

# Add the installation directory to PATH if not already present
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
fi

# Download and install the qk files
QK_FILES=("qkgit.sh" "qksetup.sh" "qkcommit.sh")
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

print_message "$GREEN" "Installation completed!\nPlease restart your terminal or run:\n    source ~/.bashrc (if using bash)\n    source ~/.zshrc  (if using zsh)\n\nAvailable commands:\n    qkgit   - Quick Git operations\n    qksetup - Quick Setup operations\n    qkcommit - Quick Commit operations"
