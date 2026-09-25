#!/bin/bash
# templates/installer.sh — starter for a curl|bash installer.
#
# Run as:  bash <(curl -fsSL "$REPO_URL/scripts/<domain>/<name>.sh")
# Conventions: AGENTS.md → "Dependency Verification Pattern".

REPO_URL="https://raw.githubusercontent.com/comchienlab/dotfiles/main"
source <(curl -fsSL "$REPO_URL/base/ui.sh")

# ── Preconditions ────────────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ] && ! command_exists sudo; then
    ui_error "Root or sudo is required."
    exit 1
fi

# ── Dependency policy: auto-install gum via the Charm APT repo ───────
if ! gum_available; then
    ui_info "Installing gum from the Charm APT repo..."
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://repo.charm.sh/apt/gpg.key \
        | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
    echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" \
        | sudo tee /etc/apt/sources.list.d/charm.list >/dev/null
    sudo apt update && sudo apt install -y gum
fi

# ── Config ───────────────────────────────────────────────────────────
PACKAGE="my-package"

# ── Confirm before touching the system ───────────────────────────────
ui_banner "📦 my-installer"
gum confirm "Install $PACKAGE on this machine?" || { ui_warn "Cancelled."; exit 0; }

# ── Install ──────────────────────────────────────────────────────────
gum spin --spinner dot --title "Installing..." -- sudo apt install -y "$PACKAGE"

ui_success "$PACKAGE installed."
