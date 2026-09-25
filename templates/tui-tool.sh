#!/bin/bash
# templates/tui-tool.sh — starter for an interactive gum tool.
#
# Copy into bin/ (installed command) or scripts/<domain>/ (one-shot).
# Conventions: AGENTS.md → "Charm gum TUI Design Patterns".
#
# Interactive scripts MUST NOT use set -e / set -u: gum returns non-zero
# when the user cancels (Esc / "No"), and set -e would abort the shell.

REPO_URL="https://raw.githubusercontent.com/comchienlab/dotfiles/main"
# shellcheck source=/dev/null
source <(curl -fsSL "$REPO_URL/base/ui.sh")

# ── Dependency policy: pick ONE ──────────────────────────────────────
# (a) auto-install via the Charm APT repo, or
# (b) error out with instructions. Do not mix.
if ! gum_available; then
    ui_error "gum is required but not installed."
    echo "  Debian/Ubuntu: https://repo.charm.sh/apt/"
    echo "  macOS:         brew install gum"
    exit 1
fi

# ── Banner ───────────────────────────────────────────────────────────
ui_banner "🚀 my-tool – short description"

# ── Menu ─────────────────────────────────────────────────────────────
choice=$(gum choose "First action" "Second action" "Quit")

# gum returns non-zero and empty output when the user presses Esc.
if [ -z "$choice" ]; then
    ui_warn "Cancelled."
    exit 0
fi

case "$choice" in
    "First action")
        if gum confirm "Proceed with the first action?"; then
            gum spin --spinner dot --title "Working..." -- sleep 1
            ui_success "Done."
        else
            ui_warn "Cancelled."
        fi
        ;;
    "Second action")
        value=$(gum input --placeholder "Enter a value..." --char-limit 50)
        [ -n "$value" ] && ui_info "Got: $value"
        ;;
    "Quit")
        exit 0
        ;;
esac
