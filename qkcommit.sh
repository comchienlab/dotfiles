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

# Check if inside a Git repository
check_git_repository

# Function to display a live preview of the commit message
function show_preview() {
    preview_message="$commit_tag"
    if [ -n "$commit_scope" ]; then
        preview_message+="($commit_scope)"
    fi
    preview_message+=": ${commit_icon:+$commit_icon} - ${commit_message:-<commit message>}"
    gum style --foreground 245 "Preview: $preview_message"
}

# Prompt for commit tag (e.g., feature, fix, chore) with preview
commit_tag=$(gum choose "feature" "fix" "chore" "docs" "style" "refactor" "test" "perf" "build")
show_preview

# Prompt for scope (optional) with preview
commit_scope=$(gum input --placeholder "Enter scope (optional)")
show_preview

# Select icon from Gitmoji options
commit_icon=$(gum choose "✨ - New feature" "🐛 - Bug fix" "📝 - Documentation" "🎨 - Code style improvements" \
                      "♻️ - Refactoring" "⚡ - Performance improvements" "🚀 - New functionality" \
                      "🚧 - Work in progress" "✅ - Adding tests" "🔧 - Configuration changes" "🔒 - Security fixes" \
                      "⬆️ - Dependency updates" "⬇️ - Downgrade dependencies" "🔥 - Removing code/files" \
                      "💄 - UI updates" "📈 - Analytics or tracking" "🐳 - Docker-related changes" "🔖 - Version tagging" \
                      "🎉 - Initial commit" "➕ - Adding dependencies" "🔄 - Dependency updates")

                      
# Extract the actual emoji from the selection for formatting
commit_icon=$(echo "$commit_icon" | awk '{print $1}')
show_preview

# Prompt for main commit message with preview
commit_message=$(gum input --placeholder "Enter commit message")
if [ -z "$commit_message" ]; then
    gum style --foreground 196 "Commit message cannot be empty."
    exit 1
fi

# Final formatted commit message without colon before the tag
formatted_message="$commit_tag"
if [ -n "$commit_scope" ]; then
    formatted_message+="($commit_scope)"
fi
formatted_message+=": $commit_icon - $commit_message."

# Show final preview and confirm commit
gum style --foreground 46 "Final commit message: $formatted_message"
gum confirm "Do you want to proceed with this commit?" || exit 1

# Stage all changes
git add .

# Commit changes with the formatted message
git commit -m "$formatted_message"

# Push to the current branch after confirmation
current_branch=$(git rev-parse --abbrev-ref HEAD)
gum confirm "Do you want to push to the current branch '$current_branch'?" || exit 1
git push origin "$current_branch"

# Display a success message
gum style --foreground 46 "Changes committed and pushed to $current_branch successfully with message: $formatted_message"
