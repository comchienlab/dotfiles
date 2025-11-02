# Common Library

This directory contains shared utility functions used across all dotfiles scripts.

## Files

### common.sh

A collection of reusable bash functions that provide common functionality for all scripts in this repository.

## Functions

### `command_exists(command_name)`

Check if a command is available in the system PATH.

**Parameters:**
- `command_name`: The name of the command to check

**Returns:**
- 0 if command exists, 1 otherwise

**Example:**
```bash
if command_exists git; then
    echo "Git is installed"
fi
```

### `print_message(color, message)`

Print a colored message to the console.

**Parameters:**
- `color`: Color code (e.g., `$GREEN`, `$RED`, `$BLUE`)
- `message`: The message to print

**Example:**
```bash
print_message "$GREEN" "✓ Operation successful"
print_message "$RED" "✗ Operation failed"
```

### `ensure_gum_installed()`

Automatically install `gum` (Charm.sh's interactive CLI tool) if not already installed.

Supports:
- macOS (via Homebrew)
- Linux (via APT)

**Example:**
```bash
ensure_gum_installed
# gum is now guaranteed to be available
```

### `check_git_repository()`

Verify that the current directory is inside a Git repository. Exits with error if not.

**Example:**
```bash
check_git_repository
# Script continues only if inside a git repo
```

### `get_commit_emoji(commit_type)`

Get the appropriate emoji for a given commit type following conventional commits. This is a simple mapping function for programmatic use.

**Parameters:**
- `commit_type`: Type of commit (feat, fix, docs, style, refactor, test, chore, perf, build)

**Returns:**
- The corresponding emoji

**Example:**
```bash
emoji=$(get_commit_emoji "feat")  # Returns ✨
emoji=$(get_commit_emoji "fix")   # Returns 🐞
```

### `select_commit_emoji()`

Interactive emoji selection from the full Gitmoji palette using `gum`. Presents a menu with 20+ emoji options and returns the selected emoji.

**Returns:**
- The selected emoji character

**Example:**
```bash
# User selects from interactive menu
emoji=$(select_commit_emoji)
# Returns the selected emoji, e.g., ✨
```

### `install_ibus_bamboo()`

Install IBUS Bamboo Vietnamese input method on Debian-based Linux systems.

**Example:**
```bash
install_ibus_bamboo
```

## Usage

To use the common library in your script, add the following at the beginning:

```bash
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

# Now you can use the functions
ensure_gum_installed
print_message "$GREEN" "Hello, world!"
```

## Installation

When scripts are installed via `install.sh`, the common library is automatically copied to `~/.local/lib/common.sh` for system-wide access.

## Available Color Codes

- `$GREEN` - Green text (success messages)
- `$RED` - Red text (error messages)
- `$BLUE` - Blue text (informational messages)
- `$YELLOW` - Yellow text (warning messages)
- `$NC` - No color (reset to default)

## Contributing

When adding new common functionality:

1. Add the function to `lib/common.sh`
2. Export the function at the end of the file
3. Document the function in this README
4. Update scripts to use the common function instead of duplicating code
