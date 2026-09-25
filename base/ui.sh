#!/usr/bin/env bash
# base/ui.sh — shared, policy-free UI helpers.
#
# Source it, never execute it:
#   source <(curl -fsSL "$REPO_URL/base/ui.sh")
#
# This file MUST NOT:
#   - install anything
#   - set shell options (set -e / set -u)
#   - print or exit at source time
#
# Dependency policy stays with the caller: some scripts auto-install gum,
# some only check, some exit with instructions. That decision is not shared.

# ── Colors (palette from AGENTS.md) ──────────────────────────────────
UI_GREEN='\033[0;32m'
UI_RED='\033[0;31m'
UI_BLUE='\033[0;34m'
UI_YELLOW='\033[1;33m'
UI_CYAN='\033[0;36m'
UI_NC='\033[0m'

# ── Dependency checks ────────────────────────────────────────────────
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check only — never installs. Callers decide what to do when it fails.
gum_available() {
    command_exists gum
}

# ── Output ───────────────────────────────────────────────────────────
ui_info()    { printf '%b%s%b\n' "$UI_BLUE"   "$*" "$UI_NC"; }
ui_success() { printf '%b%s%b\n' "$UI_GREEN"  "$*" "$UI_NC"; }
ui_warn()    { printf '%b%s%b\n' "$UI_YELLOW" "$*" "$UI_NC"; }
ui_error()   { printf '%b%s%b\n' "$UI_RED"    "$*" "$UI_NC" >&2; }

# ── Banner ───────────────────────────────────────────────────────────
# ui_banner <title> [border-color]
# Falls back to plain text when gum is absent, so it is safe to call
# before the caller has resolved its gum policy.
ui_banner() {
    local title="$1" color="${2:-#FF5733}"
    if gum_available; then
        gum style --border double --margin "1" --padding "1" \
            --border-foreground "$color" "$title"
    else
        printf '\n== %s ==\n\n' "$title"
    fi
}
