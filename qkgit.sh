#!/bin/bash

# Display main menu banner
gum style --border double --margin "1" --padding "1" --border-foreground "#FF5733" "🚀 fgit - Fast Git Workflow cho Developer (zsh)"

# Check if `gum` is installed
if ! command -v gum &> /dev/null; then
    echo "❌ gum is required but not installed. Install it and try again."
    echo "📦 Install with: brew install gum (on macOS) or go install github.com/charmbracelet/gum@latest"
    exit 1
fi

# Check if inside a Git repository
if ! git rev-parse --is-inside-work-tree &> /dev/null; then
    gum style --foreground 196 "❌ This is not a Git repository. Please navigate to a valid repository."
    exit 1
fi

get_emoji() {
    case $1 in
        "feat") echo "✨" ;;
        "refactor") echo "🔥" ;;
        "fix") echo "🐞" ;;
        "docs") echo "📚" ;;
        "style") echo "🎨" ;;
        "test") echo "✅" ;;
        "chore") echo "🔧" ;;
        *) echo "❓" ;;
    esac
}

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
        action=$(gum choose --height 7 --cursor.foreground "#FF0" \
            "🌱 Checkout to new branch from develop" \
            "🔀 Checkout Another Branch" \
            "➕ Checkout to new branch")
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
            gum confirm "🔄 Checkout branch: $branch?" && {
                gum spin --spinner dot --title "🔄 Switching branches..." -- git checkout "$branch" ||
                gum style --foreground 196 "❌ Failed to checkout branch."
            }
        else
            gum style --foreground 196 "❌ No branch selected."
        fi
        ;;

    "🌱 Checkout to new branch from develop")
        gum spin --spinner dot --title.foreground "#3498db" --title "⏳ Fetching latest remote branches..." -- git fetch --all --quiet --prune
        branch_type=$(gum choose "🔥 refactor" "🐞 fix" "✨ feat" "📚 docs")
        method=$(gum choose "✍️ Manual description" "🔗 From Jira link")

        if [ "$method" = "✍️ Manual description" ]; then
            branch_desc=$(gum input --placeholder "📝 Enter short description (e.g., bug fix, new api)")
            if [ -z "$branch_desc" ]; then
                gum style --foreground 196 "❌ Branch description cannot be empty."
                exit 1
            fi
            branch_desc=$(echo "$branch_desc" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
        else
            jira_link=$(gum input --placeholder "🔗 Enter Jira link (e.g., https://jira-local.ots.vn/browse/C8P2-241)")
            issue_key=${jira_link##*/}
            if [ -z "$issue_key" ]; then
                gum style --foreground 196 "❌ Invalid Jira link. Could not extract issue key."
                exit 1
            fi
            branch_desc=$issue_key
        fi

        new_branch="${branch_type#* }/${branch_desc}"
        echo "🌿 Branch: $new_branch"
        git checkout -b "$new_branch" "origin/develop"
        gum confirm "⬆️ Push '$new_branch' to origin?" && git push --set-upstream origin "$new_branch"
        gum style --foreground 46 "✅ Branch '$new_branch' created and set up successfully!"
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
        gum style --foreground 220 "📊 Changes to be committed:"
        git diff --cached --name-status | gum format
        gum confirm "💾 Commit with message: '$commit_message'?" && {
            git add .
            gum spin --spinner dot --title "⏳ Committing changes..." -- git commit -m "$commit_message" || {
                gum style --foreground 196 "❌ Commit failed. Ensure there are changes to commit."
                exit 1
            }
            current_branch=$(git rev-parse --abbrev-ref HEAD)
            gum confirm "⬆️ Push to '$current_branch'?" && {
                gum spin --spinner jump --title "⬆️ Pushing changes..." -- git push origin "$current_branch"
                gum style \
                    --border thick \
                    --width 50\
                    --border-foreground "#16a085" \
                    --padding "1 5" \
                    --margin "1" \
                    "✅ Changes committed and pushed to $current_branch successfully."
            }
        }
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
        emoji=$(get_emoji "${commit_type#* }")
        gum style --foreground "#3498db" "📍 Enter the zone/scope (e.g., button, auth, api):"
        zone=$(gum input --placeholder "zone/scope")
        gum style --foreground "#3498db" "📝 Enter commit description:"
        description=$(gum input --placeholder "Enter short description..." --width 256)
        commit_message="${commit_type#* }($zone): $emoji - $description."
        gum style --foreground "#f1c40f" "📊 Changes to be committed:"
        git diff --cached --name-status | gum format
        gum style --foreground "#8e44ad" "📜 Commit message preview:"
        gum style --foreground "#2980b9" "$commit_message"
        gum confirm "💾 Commit with message above?" && {
            git add .
            gum spin --spinner monkey --title "⏳ Committing changes..." -- git commit -m "$commit_message" || {
                gum style --foreground "#c0392b" "❌ Commit failed. Ensure there are changes to commit."
                exit 1
            }
            current_branch=$(git rev-parse --abbrev-ref HEAD)
            gum confirm "⬆️ Push to '$current_branch'?" && {
                gum spin --spinner monkey --title "⬆️ Pushing changes..." -- git push origin "$current_branch"
                gum style \
                    --border thick \
                    --width 50\
                    --border-foreground "#16a085" \
                    --padding "1 5" \
                    --margin "1" \
                    "🚀 Changes committed and pushed to $current_branch successfully."
            }
        }
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
        git stash push -m "$(gum input --placeholder '📝 Enter stash message')"
        gum style --foreground 46 "✅ Changes have been stashed successfully!"
        ;;

    "📤 Apply stash")
        stash_list=$(git stash list | awk -F: '{print $1 " - " $2}')
        if [[ -z "$stash_list" ]]; then
            gum style --foreground 196 "❌ No stash found!"
        else
            selected_stash=$(echo "$stash_list" | gum choose)
            stash_index=$(echo "$selected_stash" | awk '{print $1}')
            git stash apply "$stash_index"
            gum style --foreground 46 "✅ Stash $stash_index has been applied!"
        fi
        ;;

    "🗑️ Remove/Delete a stash")
        stash_list=$(git stash list | awk -F: '{print $1 " - " $2}')
        if [[ -z "$stash_list" ]]; then
            gum style --foreground 196 "❌ No stash found!"
        else
            selected_stash=$(echo "$stash_list" | gum choose)
            stash_index=$(echo "$selected_stash" | awk '{print $1}')
            gum confirm "🗑️ Delete $stash_index?" && {
                git stash drop "$stash_index"
                gum style --foreground 46 "✅ Stash $stash_index has been deleted!"
            }
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
        gum confirm "🔄 Update and upgrade system packages?" && {
            gum spin --spinner dot --title "⏳ Updating package lists..." -- sudo apt-get update
            gum spin --spinner dot --title "⏳ Upgrading packages..." -- sudo apt-get upgrade -y
            gum spin --spinner dot --title "⏳ Cleaning up..." -- sudo apt-get autoremove -y
            gum style --foreground "#27ae60" "✅ System packages updated successfully."
        }
        ;;

    "🚀 Full System Upgrade")
        gum confirm "🚀 Perform full system upgrade (including release upgrade)?" && {
            gum spin --spinner dot --title "⏳ Backing up /etc directory..." -- sudo tar -czf /etc_backup_$(date +%F).tar.gz /etc
            gum spin --spinner dot --title "⏳ Updating package lists..." -- sudo apt-get update
            gum spin --spinner dot --title "⏳ Upgrading packages..." -- sudo apt-get upgrade -y
            gum spin --spinner dot --title "⏳ Performing dist-upgrade..." -- sudo apt-get dist-upgrade -y
            gum spin --spinner dot --title "⏳ Cleaning up..." -- sudo apt-get autoremove -y
            gum spin --spinner pulse --title "⏳ Performing release upgrade..." -- sudo do-release-upgrade -f DistUpgradeViewNonInteractive
            if [ -f /var/run/reboot-required ]; then
                gum confirm "🔄 Reboot required. Reboot now?" && sudo reboot
            fi
            gum style --foreground "#27ae60" "✅ System upgrade completed successfully."
        }
        ;;

    *)
        gum style --foreground 196 "❌ Invalid choice. Exiting."
        exit 1
        ;;
esac
