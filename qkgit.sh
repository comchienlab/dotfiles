#!/bin/bash

# Check if `gum` is installed
if ! command -v gum &> /dev/null; then
    echo "gum is required but not installed. Install it and try again."
    echo "Install with: brew install gum (on macOS) or go install github.com/charmbracelet/gum@latest"
    exit 1
fi

# Check if inside a Git repository
if ! git rev-parse --is-inside-work-tree &> /dev/null; then
    gum style --foreground 196 "This is not a Git repository. Please navigate to a valid repository."
    exit 1
fi

# Main menu options
choice=$(gum choose --height 15 "Check Git Status"\
 "Checkout Another Branch"\
 "Commit with Default Message"\
 "Pull Latest Changes"\
 "Pull from Origin/Develop and Merge"\
 "View Git Log")

case $choice in
    "Check Git Status")
        # Display git status with color formatting
        gum style --foreground 220 "Git Status:"
        git status --short | gum format
        ;;
    
    "Checkout Another Branch")
        # List branches and allow user to select one with better filtering
        gum style --foreground 220 "Loading branches..."
        git fetch --all --quiet
        branch=$(git branch --all | grep -v HEAD | sed 's/^..//' | gum filter --placeholder "Search and select a branch to checkout")
        if [ -n "$branch" ]; then
            # Strip off "remotes/" if selected from remote branches
            branch=$(echo "$branch" | sed 's/^\s*remotes\/origin\///')
            gum confirm "Checkout branch: $branch?" && {
                gum spin --spinner dot --title "Switching branches..." -- git checkout "$branch" || 
                gum style --foreground 196 "Failed to checkout branch."
            }
        else
            gum style --foreground 196 "No branch selected."
        fi
        ;;
    
    "Commit with Default Message")
        # Predefined commit messages
        commit_message=$(gum choose \
            "feat: :sparkles: - add new feature" \
            "fix: :bug: - bug fix" \
            "docs: :book: - documentation changes" \
            "style: :art: - formatting changes" \
            "refactor: :recycle: - code refactoring" \
            "test: :white_check_mark: - add/update tests" \
            "chore: :wrench: - maintenance tasks")

        # Show changes to be committed
        gum style --foreground 220 "Changes to be committed:"
        git diff --cached --name-status | gum format

        # Stage and commit
        gum confirm "Commit with message: '$commit_message'?" && {
            git add .
            gum spin --spinner dot --title "Committing changes..." -- git commit -m "$commit_message" || {
                gum style --foreground 196 "Commit failed. Ensure there are changes to commit."
                exit 1
            }

            # Push to the current branch after confirmation
            current_branch=$(git rev-parse --abbrev-ref HEAD)
            gum confirm "Push to '$current_branch'?" && {
                gum spin --spinner dot --title "Pushing changes..." -- git push origin "$current_branch"
                gum style --foreground 46 "Changes committed and pushed to $current_branch successfully."
            }
        }
        ;;

    "Pull Latest Changes")
        current_branch=$(git rev-parse --abbrev-ref HEAD)
        gum confirm "Pull latest changes from origin/$current_branch?" && {
            gum spin --spinner dot --title "Pulling changes..." -- git pull origin "$current_branch"
            gum style --foreground 46 "Successfully pulled latest changes."
        }
        ;;
    
    "Pull from Origin/Develop and Merge")
        gum confirm "Pull from origin/develop and merge?" && {
            gum spin --spinner dot --title "Pulling changes..." -- git -c credential.helper= -c core.quotepath=false -c log.showSignature=false merge origin/develop
            gum style --foreground 46 "Successfully pulled from origin/develop."
        }
        ;;

    "View Git Log")
        # Show pretty git log with pagination
        git log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit | gum pager
        ;;
    
    *)
        gum style --foreground 196 "Invalid choice. Exiting."
        exit 1
        ;;
esac
