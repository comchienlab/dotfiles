# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a dotfiles repository containing shell scripts and configuration files for automating development environment setup on Linux and macOS systems. The repository focuses on system automation, developer productivity tools, and configuration management.

## Key Commands and Scripts

### Main Interactive Scripts
- `fsetup` - Interactive menu-driven setup operations (system packages, desktop apps, development tools)
- `fgit` - Git workflow automation with branch management, commits, stash operations  
- `qkcommit` - Conventional commit message generator with emoji support

### Installation and Setup
- `./install.sh` - Bootstrap script that installs the main `f*` commands to `~/.local/bin`
- `bash <(curl -fsSL https://raw.githubusercontent.com/comchienlab/dotfiles/main/install.sh)` - Remote installation

### Platform-Specific Scripts
- `macos/qkmacos.sh` - macOS environment setup with Homebrew and applications
- `backend/qkflyway.sh` - Flyway database migration helper

### Utilities
- `create_swap.sh` - Linux swap file creation
- `debloat.sh` - Remove unnecessary system packages
- `n8n/n8n-installer.sh` - n8n workflow automation tool installer
- `rclone/rclone-tool.sh` - Cloud storage management tool installer
- `fonts/nerdfont-installer.sh` - Nerd Fonts installer

## Development and Testing

### Script Validation
- All shell scripts should be validated with `shellcheck` before committing
- Test scripts manually: `bash path/to/script.sh`
- No automated test framework is configured

### Dependencies
- **Required**: `gum` (interactive CLI components) - scripts auto-install if missing
- **Optional**: Various package managers (brew, apt, snap) depending on platform

## Configuration Files

### Terminal and Editor Configurations
- `ghostty/config` - Ghostty terminal emulator settings (fonts, keybindings, appearance)
- `ghostty/custom.css` - Custom styling for Ghostty terminal
- `zed/setting.json` - Zed editor configuration (fonts, themes, assistant settings)

### Shell Environment
- Scripts configure zsh with starship prompt, autosuggestions, and syntax highlighting
- Git aliases and configuration are set up automatically

## Architecture Notes

### Script Structure
- All interactive scripts use `gum` for consistent UI/UX
- Modular design with functions for reusable operations
- Color-coded output for different message types (success, error, info)
- Confirmation prompts before destructive operations

### Platform Detection
- Scripts detect OS type (`darwin` for macOS, Linux distributions)
- Package manager detection (brew, apt, snap)
- Architecture awareness for downloading platform-specific binaries

### Error Handling
- Scripts validate prerequisites before execution
- Graceful failure with informative error messages
- Rollback capabilities where applicable

## Workflow Patterns

### Git Operations (fgit.sh)
- Branch naming convention: `type/description` (e.g., `feat/user-auth`, `fix/bug-123`)
- Conventional commits with emoji support
- Integration with remote repositories and pull requests

### System Setup (fsetup.sh)
- Modular installation options via interactive menus
- Development environment setup (Java via SDKMAN, Node.js via FNM/Volta)
- Package management and system optimization

### Commit Conventions (qkcommit.sh)
- Conventional commit format: `type(scope): emoji - description`
- Gitmoji integration for visual commit history
- Automatic staging and push workflows