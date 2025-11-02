#!/bin/bash
# Common library functions for dotfiles scripts
# Source this file in your scripts: source "$(dirname "$0")/lib/common.sh"

# Color definitions for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Ensure gum is installed (works on macOS and Linux)
ensure_gum_installed() {
    if ! command_exists gum; then
        echo "Gum is required but not installed. Installing..."
        
        # Detect OS and install gum
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            print_message "$BLUE" "Detected macOS, installing via Homebrew..."
            if ! command_exists brew; then
                print_message "$RED" "Homebrew is not installed. Please install it first."
                exit 1
            fi
            brew install gum
        else
            # Ubuntu/Debian Linux
            print_message "$BLUE" "Detected Linux, installing via APT..."
            sudo mkdir -p /etc/apt/keyrings
            curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
            echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list > /dev/null
            sudo apt update && sudo apt install -y gum
        fi
        
        # Verify installation
        if ! command_exists gum; then
            print_message "$RED" "Failed to install gum. Please install it manually."
            exit 1
        fi
        
        print_message "$GREEN" "✓ Gum installed successfully!"
    fi
}

# Check if inside a Git repository
check_git_repository() {
    if ! git rev-parse --is-inside-work-tree &> /dev/null; then
        if command_exists gum; then
            gum style --foreground 196 "❌ This is not a Git repository. Please navigate to a valid repository."
        else
            print_message "$RED" "❌ This is not a Git repository. Please navigate to a valid repository."
        fi
        exit 1
    fi
}

# Get emoji for commit type (basic mapping)
get_commit_emoji() {
    local commit_type=$1
    local emoji
    
    case $commit_type in
        "feat"|"feature") emoji="✨" ;;
        "refactor") emoji="🔄" ;;
        "fix") emoji="🐞" ;;
        "docs") emoji="📚" ;;
        "style") emoji="🎨" ;;
        "test") emoji="✅" ;;
        "chore") emoji="🔧" ;;
        "perf") emoji="⚡" ;;
        "build") emoji="🏗️" ;;
        *) emoji="❓" ;;
    esac
    
    echo "$emoji"
}

# Interactive emoji selection using gum (full Gitmoji palette)
# Returns just the emoji character
select_commit_emoji() {
    if ! command_exists gum; then
        echo "❓"
        return
    fi
    
    local selection
    selection=$(gum choose \
        "✨ - New feature" \
        "🐛 - Bug fix" \
        "📝 - Documentation" \
        "🎨 - Code style improvements" \
        "♻️ - Refactoring" \
        "⚡ - Performance improvements" \
        "🚀 - New functionality" \
        "🚧 - Work in progress" \
        "✅ - Adding tests" \
        "🔧 - Configuration changes" \
        "🔒 - Security fixes" \
        "⬆️ - Dependency updates" \
        "⬇️ - Downgrade dependencies" \
        "🔥 - Removing code/files" \
        "💄 - UI updates" \
        "📈 - Analytics or tracking" \
        "🐳 - Docker-related changes" \
        "🔖 - Version tagging" \
        "🎉 - Initial commit" \
        "➕ - Adding dependencies" \
        "🔄 - Dependency updates")
    
    # Extract just the emoji (first field)
    echo "$selection" | awk '{print $1}'
}

# Install IBUS Bamboo (Vietnamese input method)
install_ibus_bamboo() {
    if command_exists gum; then
        gum style --foreground 46 "Adding ibus-bamboo repository..."
    else
        print_message "$GREEN" "Adding ibus-bamboo repository..."
    fi
    
    echo 'deb http://download.opensuse.org/repositories/home:/lamlng/Debian_12/ /' | sudo tee /etc/apt/sources.list.d/home:lamlng.list > /dev/null
    
    if command_exists gum; then
        gum style --foreground 46 "Adding ibus-bamboo repository key..."
    else
        print_message "$GREEN" "Adding ibus-bamboo repository key..."
    fi
    
    curl -fsSL https://download.opensuse.org/repositories/home:lamlng/Debian_12/Release.key | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/home_lamlng.gpg > /dev/null
    
    if command_exists gum; then
        gum style --foreground 46 "Updating apt repositories..."
    else
        print_message "$GREEN" "Updating apt repositories..."
    fi
    
    sudo apt update
    
    if command_exists gum; then
        gum style --foreground 46 "Installing ibus-bamboo package..."
    else
        print_message "$GREEN" "Installing ibus-bamboo package..."
    fi
    
    sudo apt -y install ibus-bamboo
    
    if command_exists gum; then
        gum style --foreground 46 "✅ IBUS-Bamboo installation complete!"
    else
        print_message "$GREEN" "✅ IBUS-Bamboo installation complete!"
    fi
}

# Export functions so they can be used by sourcing scripts
export -f command_exists
export -f print_message
export -f ensure_gum_installed
export -f check_git_repository
export -f get_commit_emoji
export -f select_commit_emoji
export -f install_ibus_bamboo
