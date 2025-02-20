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
 "Checkout to new branch from Develop"\
 "Checkout to new branch"\
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

    "Checkout to new branch from Develop")
        # Fetch latest remote branches
        echo "Fetching latest remote branches..."
        git fetch --prune

        # Choose a branch type (conventional naming)
        branch_type=$(gum choose "fix" "feature" "refactor" "update" "docs")

        # Ask for a branch description
        branch_desc=$(gum input --placeholder "Enter short description (e.g., bug fix, new api)")

        # Check if description is empty
        if [ -z "$branch_desc" ]; then
        gum style --foreground 196 "Branch description cannot be empty."
        exit 1
        fi

        # Convert description to snake_case
        branch_desc=$(echo "$branch_desc" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')

        # Format the new branch name
        new_branch="${branch_type}/${branch_desc}"

        # Create and switch to the new branch
        echo "Branch: $new_branch"
        git checkout -b "$new_branch" "origin/develop"

        # Push new branch to origin
        gum confirm "Push '$new_branch' to origin?" && git push --set-upstream origin "$new_branch"

        gum style --foreground 46 "Branch '$new_branch' created and set up successfully!"
        ;;

    "Checkout to new branch")
        # Fetch latest remote branches
        echo "Fetching latest remote branches..."
        git fetch --prune

        # Get the list of remote branches (excluding HEAD)
        branches=$(git branch -r | grep -v "HEAD" | sed 's/origin\///' | sort)

        # If no branches found, exit
        if [ -z "$branches" ]; then
            gum style --foreground 196 "No remote branches found."
            exit 1
        fi

        # Let the user choose a base branch
        selected_branch=$(git branch --all | grep -v HEAD | sed 's/^..//' | gum filter --placeholder "Search and select a branch to checkout")

        # Confirm selection
        gum confirm "Create a new branch from '$selected_branch'?" || exit 1

        # Choose a branch type (conventional naming)
        branch_type=$(gum choose "fix" "feature" "update" "docs")

        # Ask for a branch description
        branch_desc=$(gum input --placeholder "Enter short description (e.g., bug fix, new api)")

        # Check if description is empty
        if [ -z "$branch_desc" ]; then
            gum style --foreground 196 "Branch description cannot be empty."
            exit 1
        fi

        # Convert description to snake_case
        branch_desc=$(echo "$branch_desc" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')

        # Format the new branch name
        new_branch="${branch_type}/${branch_desc}"

        # Create and switch to the new branch
        echo "Branch: $new_branch"
        git checkout -b "$new_branch" "$selected_branch"

        # Push new branch to origin
        gum confirm "Push '$new_branch' to origin?" && git push --set-upstream origin "$new_branch"

        gum style --foreground 46 "Branch '$new_branch' created and set up successfully!"
        ;;

    "Commit with Default Message")
        # Predefined commit messages
        commit_message=$(gum choose \
            "feat(:fire:): :sparkles: - add new feature." \
            "fix(:fire:): :bug: - bug fix." \
            "docs(:fire:): :book: - documentation changes." \
            "style(:fire:): :art: - formatting changes." \
            "refactor(:fire:): :recycle: - code refactoring." \
            "test(:fire:): :white_check_mark: - add/update tests." \
            "chore(:fire:): :wrench: - maintenance tasks.")

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
            gum spin --spinner dot --title "Fetching from origin..." -- git -c credential.helper= -c core.quotepath=false -c log.showSignature=false fetch origin --recurse-submodules=no --progress --prune
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
