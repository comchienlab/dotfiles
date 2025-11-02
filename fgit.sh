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

# Display main menu banner
gum style --border double --margin "1" --padding "1" --border-foreground "#FF5733" "🚀 fgit - Fast Git Workflow cho Developer (zsh)"

# Check if inside a Git repository
check_git_repository

# Top-level group menu with improved styling
feature_group=$(gum choose --height 10 --cursor.foreground "#FF0" --selected.foreground "#0FF" \
    "📊 Status & Log" \
    "🌿 Branch Management" \
    "💾 Commit" \
    "🔄 Pull & Merge" \
    "📦 Stash" \
    "🛠️ System Upgrade")

case $feature_group in
    "📊 Status & Log")
        action=$(gum choose --height 5 --cursor.foreground "#FF0" \
            "🔍 Check Git Status" \
            "📜 View Git Log")
        ;;
    "🌿 Branch Management")
        action=$(gum choose --height 8 --cursor.foreground "#FF0" \
            "🌱 Checkout to new branch from develop" \
            "🔀 Checkout Another Branch" \
            "➕ Checkout to new branch" \
            "📅 Create feature branch with date pattern")
        ;;
    "💾 Commit")
        action=$(gum choose --height 5 --cursor.foreground "#FF0" \
            "✍️ Commit with Custom Message" \
            "📝 Commit with Default Message")
        ;;
    "🔄 Pull & Merge")
        action=$(gum choose --height 5 --cursor.foreground "#FF0" \
            "🔗 Pull from Origin/Develop and Merge" \
            "⬇️ Pull Latest Changes")
        ;;
    "📦 Stash")
        action=$(gum choose --height 7 --cursor.foreground "#FF0" \
            "📥 Stash current changes" \
            "📤 Apply stash" \
            "🗑️ Remove/Delete a stash" \
            "📋 View stash list")
        ;;
    "🛠️ System Upgrade")
        action=$(gum choose --height 5 --cursor.foreground "#FF0" \
            "🔄 Update Packages" \
            "🚀 Full System Upgrade")
        ;;
    *)
        gum style --foreground 196 "❌ Invalid group. Exiting."
        exit 1
        ;;
esac

case $action in
    "🔍 Check Git Status")
        gum style --foreground "#27ae60" --border double --padding "1 2" "📊 Git Status:"
        git status --short | gum format
        ;;

    "🔀 Checkout Another Branch")
        gum spin --spinner minidot --title "⏳ Loading branches..." -- git fetch --all --quiet
        branch=$(git branch --all | grep -v HEAD | sed 's/^..//' | gum filter --placeholder "🔎 Search and select a branch to checkout")
        if [ -n "$branch" ]; then
            branch=$(echo "$branch" | sed 's/^\s*remotes\/origin\///')
            if gum confirm "🔄 Checkout branch: $branch?"; then
                if ! gum spin --spinner dot --title "🔄 Switching branches..." -- git checkout "$branch"; then
                    gum style --foreground 196 "❌ Failed to checkout branch."
                fi
            fi
        else
            gum style --foreground 196 "❌ No branch selected."
        fi
        ;;

    "🌱 Checkout to new branch from develop")
        gum spin --spinner dot --title.foreground "#3498db" --title "⏳ Fetching latest remote branches..." -- git fetch --all --quiet --prune
        branch_type=$(gum choose "🔥 refactor" "🐞 fix" "✨ feat" "📚 docs")
        if [ -z "$branch_type" ]; then
            gum style --foreground 196 "❌ No branch type selected."
            exit 1
        fi
        method=$(gum choose "✍️ Manual description" "🔗 From Jira link")
        if [ -z "$method" ]; then
            gum style --foreground 196 "❌ No method selected."
            exit 1
        fi

        if [ "$method" = "✍️ Manual description" ]; then
            branch_desc=$(gum input --placeholder "📝 Enter short description (e.g., bug fix, new api)")
            if [ -z "$branch_desc" ]; then
                gum style --foreground 196 "❌ Branch description cannot be empty."
                exit 1
            fi
            branch_desc=$(echo "$branch_desc" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
        else
            jira_link=$(gum input --placeholder "🔗 Enter Jira link (e.g., https://jira-local.example.com/browse/C8P2-241)")
            if [ -z "$jira_link" ]; then
                gum style --foreground 196 "❌ Jira link cannot be empty."
                exit 1
            fi
            issue_key=${jira_link##*/}
            if [ -z "$issue_key" ]; then
                gum style --foreground 196 "❌ Invalid Jira link. Could not extract issue key."
                exit 1
            fi
            branch_desc=$issue_key
        fi

        new_branch="${branch_type#* }/${branch_desc}"
        echo "🌿 Branch: $new_branch"
        if git checkout -b "$new_branch" "origin/develop"; then
            if gum confirm "⬆️ Push '$new_branch' to origin?"; then
                git push --set-upstream origin "$new_branch"
            fi
            gum style --foreground 46 "✅ Branch '$new_branch' created and set up successfully!"
        else
            gum style --foreground 196 "❌ Failed to create branch '$new_branch'."
        fi
        ;;

    "➕ Checkout to new branch")
        echo "⏳ Fetching latest remote branches..."
        git fetch --prune
        branches=$(git branch -r | grep -v "HEAD" | sed 's/origin\///' | sort)
        if [ -z "$branches" ]; then
            gum style --foreground 196 "❌ No remote branches found."
            exit 1
        fi
        selected_branch=$(git branch --all | grep -v HEAD | sed 's/^..//' | gum filter --placeholder "🔎 Search and select a branch to checkout")
        gum confirm "➕ Create a new branch from '$selected_branch'?" || exit 1
        branch_type=$(gum choose "🐞 fix" "✨ feature" "🔄 update" "📚 docs")
        branch_desc=$(gum input --placeholder "📝 Enter short description (e.g., bug fix, new api)")
        if [ -z "$branch_desc" ]; then
            gum style --foreground 196 "❌ Branch description cannot be empty."
            exit 1
        fi
        branch_desc=$(echo "$branch_desc" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
        new_branch="${branch_type#* }/${branch_desc}"
        echo "🌿 Branch: $new_branch"
        git checkout -b "$new_branch" "$selected_branch"
        gum confirm "⬆️ Push '$new_branch' to origin?" && git push --set-upstream origin "$new_branch"
        gum style --foreground 46 "✅ Branch '$new_branch' created and set up successfully!"
        ;;

    "📅 Create feature branch with date pattern")
        gum spin --spinner dot --title.foreground "#3498db" --title "⏳ Fetching latest remote branches..." -- git fetch --all --quiet --prune
        current_date=$(date +%Y%m%d)
        new_branch="feature/$current_date"
        echo "📅 Branch: $new_branch"
        if git checkout -b "$new_branch" "origin/develop"; then
            if gum confirm "⬆️ Push '$new_branch' to origin?"; then
                git push --set-upstream origin "$new_branch"
            fi
            gum style --foreground 46 "✅ Branch '$new_branch' created and set up successfully!"
        else
            gum style --foreground 196 "❌ Failed to create branch '$new_branch'."
        fi
        ;;

    "📝 Commit with Default Message")
        commit_message=$(gum choose \
            "✨ feat(all): - add new feature." \
            "🔥 refactor(all): - somethings change for easy maintainale." \
            "🔄 refactor(all): - code refactoring." \
            "🐞 fix(all): - bug fix for boss." \
            "📚 docs(all): - documentation changes." \
            "🎨 style(all): - formatting changes." \
            "✅ test(all): - add/update tests." \
            "🔧 chore(all): - maintenance tasks.")
        if [ -z "$commit_message" ]; then
            gum style --foreground 196 "❌ No commit message selected."
            exit 1
        fi
        gum style --foreground 220 "📊 Changes to be committed:"
        git diff --cached --name-status | gum format
        if gum confirm "💾 Commit with message: '$commit_message'?"; then
            git add .
            if gum spin --spinner dot --title "⏳ Committing changes..." -- git commit -m "$commit_message"; then
                current_branch=$(git rev-parse --abbrev-ref HEAD)
                if gum confirm "⬆️ Push to '$current_branch'?"; then
                    gum spin --spinner jump --title "⬆️ Pushing changes..." -- git push origin "$current_branch"
                    gum style \
                        --border thick \
                        --width 50\
                        --border-foreground "#16a085" \
                        --padding "1 5" \
                        --margin "1" \
                        "✅ Changes committed and pushed to $current_branch successfully."
                fi
            else
                gum style --foreground 196 "❌ Commit failed. Ensure there are changes to commit."
            fi
        fi
        ;;

    "✍️ Commit with Custom Message")
        commit_type=$(gum choose \
            "✨ feat" \
            "🔥 refactor" \
            "🐞 fix" \
            "📚 docs" \
            "🎨 style" \
            "✅ test" \
            "🔧 chore")
        if [ -z "$commit_type" ]; then
            gum style --foreground 196 "❌ No commit type selected."
            exit 1
        fi
        emoji=$(get_commit_emoji "${commit_type#* }")
        gum style --foreground "#3498db" "📍 Enter the zone/scope (e.g., button, auth, api):"
        zone=$(gum input --placeholder "zone/scope")
        if [ -z "$zone" ]; then
            gum style --foreground 196 "❌ Zone/scope cannot be empty."
            exit 1
        fi
        gum style --foreground "#3498db" "📝 Enter commit description:"
        description=$(gum input --placeholder "Enter short description..." --width 256)
        if [ -z "$description" ]; then
            gum style --foreground 196 "❌ Description cannot be empty."
            exit 1
        fi
        commit_message="${commit_type#* }($zone): $emoji - $description."
        gum style --foreground "#f1c40f" "📊 Changes to be committed:"
        git diff --cached --name-status | gum format
        gum style --foreground "#8e44ad" "📜 Commit message preview:"
        gum style --foreground "#2980b9" "$commit_message"
        if gum confirm "💾 Commit with message above?"; then
            git add .
            if gum spin --spinner monkey --title "⏳ Committing changes..." -- git commit -m "$commit_message"; then
                current_branch=$(git rev-parse --abbrev-ref HEAD)
                if gum confirm "⬆️ Push to '$current_branch'?"; then
                    gum spin --spinner monkey --title "⬆️ Pushing changes..." -- git push origin "$current_branch"
                    gum style \
                        --border thick \
                        --width 50\
                        --border-foreground "#16a085" \
                        --padding "1 5" \
                        --margin "1" \
                        "🚀 Changes committed and pushed to $current_branch successfully."
                fi
            else
                gum style --foreground "#c0392b" "❌ Commit failed. Ensure there are changes to commit."
            fi
        fi
        ;;

    "⬇️ Pull Latest Changes")
        current_branch=$(git rev-parse --abbrev-ref HEAD)
        gum confirm "⬇️ Pull latest changes from origin/$current_branch?" && {
            gum spin --spinner dot --title "⏳ Pulling changes..." -- git pull origin "$current_branch"
            gum style --foreground "#27ae60" "✅ Successfully pulled latest changes."
        }
        ;;

    "🔗 Pull from Origin/Develop and Merge")
        gum confirm "🔗 Pull from origin/develop and merge?" && {
            gum spin --spinner dot --title "⏳ Fetching from origin..." -- git -c credential.helper= -c core.quotepath=false -c log.showSignature=false fetch origin --recurse-submodules=no --progress --prune
            gum spin --spinner pulse --title "⏳ Pulling changes..." -- git -c credential.helper= -c core.quotepath=false -c log.showSignature=false merge origin/develop
            gum style \
                --border double \
                --width 50\
                --border-foreground "#16a085" \
                --padding "1 2" \
                --margin "1" \
                "🚀 Successfully pulled from origin/develop."
        }
        ;;

    "📥 Stash current changes")
        stash_message=$(gum input --placeholder '📝 Enter stash message')
        if [ -z "$stash_message" ]; then
            gum style --foreground 196 "❌ Stash message cannot be empty."
            exit 1
        fi
        git stash push -m "$stash_message"
        gum style --foreground 46 "✅ Changes have been stashed successfully!"
        ;;

    "📤 Apply stash")
        stash_list=$(git stash list | awk -F: '{print $1 " - " $2}')
        if [[ -z "$stash_list" ]]; then
            gum style --foreground 196 "❌ No stash found!"
        else
            selected_stash=$(echo "$stash_list" | gum choose)
            if [ -n "$selected_stash" ]; then
                stash_index=$(echo "$selected_stash" | awk '{print $1}')
                git stash apply "$stash_index"
                gum style --foreground 46 "✅ Stash $stash_index has been applied!"
            else
                gum style --foreground 196 "❌ No stash selected."
            fi
        fi
        ;;

    "🗑️ Remove/Delete a stash")
        stash_list=$(git stash list | awk -F: '{print $1 " - " $2}')
        if [[ -z "$stash_list" ]]; then
            gum style --foreground 196 "❌ No stash found!"
        else
            selected_stash=$(echo "$stash_list" | gum choose)
            if [ -n "$selected_stash" ]; then
                stash_index=$(echo "$selected_stash" | awk '{print $1}')
                if gum confirm "🗑️ Delete $stash_index?"; then
                    git stash drop "$stash_index"
                    gum style --foreground 46 "✅ Stash $stash_index has been deleted!"
                fi
            else
                gum style --foreground 196 "❌ No stash selected."
            fi
        fi
        ;;

    "📋 View stash list")
        stash_list=$(git stash list)
        if [[ -z "$stash_list" ]]; then
            gum style --foreground 196 "❌ No stash found!"
        else
            echo "$stash_list" | gum format
        fi
        ;;

    "📜 View Git Log")
        git log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit | gum pager
        ;;

    "🔄 Update Packages")
        if gum confirm "🔄 Update and upgrade system packages?"; then
            gum spin --spinner dot --title "⏳ Updating package lists..." -- sudo apt-get update
            gum spin --spinner dot --title "⏳ Upgrading packages..." -- sudo apt-get upgrade -y
            gum spin --spinner dot --title "⏳ Cleaning up..." -- sudo apt-get autoremove -y
            gum style --foreground "#27ae60" "✅ System packages updated successfully."
        fi
        ;;

    "🚀 Full System Upgrade")
        if gum confirm "🚀 Perform full system upgrade (including release upgrade)?"; then
            gum spin --spinner dot --title "⏳ Backing up /etc directory..." -- sudo tar -czf /etc_backup_$(date +%F).tar.gz /etc
            gum spin --spinner dot --title "⏳ Updating package lists..." -- sudo apt-get update
            gum spin --spinner dot --title "⏳ Upgrading packages..." -- sudo apt-get upgrade -y
            gum spin --spinner dot --title "⏳ Performing dist-upgrade..." -- sudo apt-get dist-upgrade -y
            gum spin --spinner dot --title "⏳ Cleaning up..." -- sudo apt-get autoremove -y
            gum spin --spinner pulse --title "⏳ Performing release upgrade..." -- sudo do-release-upgrade -f DistUpgradeViewNonInteractive
            if [ -f /var/run/reboot-required ]; then
                if gum confirm "🔄 Reboot required. Reboot now?"; then
                    sudo reboot
                fi
            fi
            gum style --foreground "#27ae60" "✅ System upgrade completed successfully."
        fi
        ;;

    *)
        gum style --foreground 196 "❌ Invalid choice. Exiting."
        exit 1
        ;;
esac
