# Project Summary

## Overview
This repository contains a collection of dotfiles and scripts designed to streamline development environment setup for Linux and macOS systems. It includes automation tools and configurations for various tasks such as development setup, system optimization, and workflow enhancements.

## Key Components
### Installation Scripts
- **install.sh**: Bootstraps environment setup.
- Various platform-specific and utility-specific installers like:
  - `macos/qkmacos.sh` for macOS setup.
  - `n8n/n8n-installer.sh` for n8n installation.
  - `fonts/nerdfont-installer.sh` for Nerd Fonts.

### Quick Scripts
- **fsetup.sh**: Interface for quick system setup operations.
- **fgit.sh**: Simplifies common Git workflows.
- **qkcommit.sh**: Helps write conventional commit messages.
- **backend/qkflyway.sh**: Manage Flyway database migrations.

### Utilities
- **create_swap.sh**: Creates and enables swap files on Linux.
- **debloat.sh**: Removes unnecessary pre-installed software.
- **rclone/rclone-tool.sh**: Installs and configures rclone.

### Configuration Files
- **ghostty/config** & **ghostty/custom.css**: Configuration for terminal emulator.
- **zed/setting.json**: Settings for Zed code editor.

## Notes
- Validates shell syntax using `shellcheck`.
- For testing, run scripts manually with `bash path/to/script.sh`.
