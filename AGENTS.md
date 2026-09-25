# Repository Guidelines

## Project Overview

This repository is a developer environment automation and dotfiles repository for Linux (primarily Debian/Ubuntu) and macOS. It provides:
- Interactive TUI-based developer commands (`fsetup`, `fgit`, `qkcommit`) powered by Charm's `gum`.
- End-to-end infrastructure and tool setup scripts (N8N, Rclone, Nerd Fonts, Flyway, and LLM proxy routers).
- Curated terminal, editor, and shell configurations (Ghostty, Zed, Zsh, Starship prompt).

The repository adopts a remote-executable model where scripts can be executed directly via `bash <(curl -fsSL ...)` or installed locally into `~/.local/bin/`.

---

## Architecture & Data Flow

### Architecture Layers

1. **Interactive CLI Orchestrator Tier (`~/.local/bin/` / Root)**
   - Self-contained, zero-dependency Bash/Zsh scripts providing interactive menu-driven interfaces (`gum choose`, `gum filter`, `gum input`, `gum confirm`).
   - Handles developer workflows: Git operations (`fgit.sh`), workstation provisioning (`fsetup.sh`), and conventional commit composition (`qkcommit.sh`).
2. **Infrastructure & Platform Automation Tier (`linux/`, `backend/`, `macos/`, `llm/`, `fonts/`, `n8n/`, `rclone/`)**
   - Domain-specific automation: Linux system utilities (`linux/`), Docker Compose orchestration (`n8n/`), database migration helpers (`backend/`), font cache builders (`fonts/`), macOS maintenance (`macos/`), and low-spec VPS reverse-proxy deployments (`llm/`).
3. **Shell Environment & Dotfile Tier (`config/`)**
   - Reference configurations and runtime profiles for modern developer terminals and editors (Ghostty terminal with custom GTK CSS, Zed editor with Claude 3.5 Sonnet integration, and Catppuccin Mocha Starship prompt).

### Data Flow & Execution Pipeline

```
User Invocation ──> Dependency Pre-flight (gum, git, package managers)
                     │
                     ▼
          Interactive Menu / Filter Selection (gum choose / gum filter)
                     │
                     ▼
          Input Prompts & Live Previews (gum input / custom preview functions)
                     │
                     ▼
          Confirmation Barrier (gum confirm) ──[No]──> Graceful Exit (0 / 1)
                     │ [Yes]
                     ▼
          Command Dispatch with Progress Feedback (gum spin)
                     │
                     ▼
          Formatted Status Display (gum style / gum format / gum pager)
```

### Bootstrap Flow (`install.sh`)
- `install.sh` acts as the package distributor.
- Verifies and auto-installs `gum` (via Charm APT repository on Debian/Ubuntu or Homebrew on macOS).
- Ensures `~/.local/bin` exists and is exported in `~/.bashrc` and `~/.zshrc`.
- Downloads `fgit.sh`, `fsetup.sh`, and `qkcommit.sh` from raw GitHub URLs, removes the `.sh` extension, and grants executable permissions (`chmod +x`).

---

## Key Directories

| Directory | Purpose |
|---|---|
| `/` (Root) | Core interactive CLI tools (`fsetup.sh`, `fgit.sh`, `qkcommit.sh`) and the bootstrap installer (`install.sh`). |
| `linux/` | Linux system utilities: `create_swap.sh` (swap file creation), `debloat.sh` (pre-installed package removal), `vps_optimize.sh` (VPS tuning pipeline), `fub_clean.sh` (interactive cleanup assistant), `certbot-kit.sh` (Let's Encrypt certificates for bare IPs). |
| `config/` | Reference configurations, never executed: `shell/` (`.zshrc`, `.zshfn`, `starship.toml`), `ghostty/` (`config`, `custom.css`), and `zed/` (`settings.json`). |
| `backend/` | Database and backend engineering utilities: `qkflyway.sh` (Flyway migration generator) and `qkbe.sh` (Flyway repair/migration runners, conflict resolution, environment bootstrap). |
| `fonts/` | Font management: `nerdfont-installer.sh` (queries GitHub release API, downloads selected Nerd Fonts, installs to `~/.local/share/fonts`, rebuilds font cache). |
| `llm/` | AI proxy deployment kits: `setup_9router.sh` (VPS router with tiered memory tuning, self-diagnostics doctor, systemd service) and `setup_cliproxy.sh` (CLIProxyAPI PLUS installer with Go build and Caddy SSL). |
| `macos/` | macOS-specific maintenance: `qkmacos.sh` (Zsh TUI script for clearing user/system caches, Xcode derived data, and restarting Finder/Dock). |
| `n8n/` | Workflow automation: `n8n-installer.sh` (Docker Compose deployment of n8n with Caddy reverse proxy and auto-updates). |
| `rclone/` | Cloud storage tooling: `rclone-tool.sh` (interactive TUI for remote browsing, transfer queues, and configuration sync). |

---

## Development Commands

### Running Scripts Locally
```bash
# Execute core interactive tools directly
bash fgit.sh
bash fsetup.sh
bash qkcommit.sh

# Execute macOS-specific maintenance (requires zsh)
zsh macos/qkmacos.sh

# Execute utility scripts
bash linux/create_swap.sh
bash fonts/nerdfont-installer.sh
bash backend/qkflyway.sh
```

### Installation and Bootstrap
```bash
# Run local installer to provision ~/.local/bin
bash install.sh

# Remote installation from GitHub
bash <(curl -fsSL https://raw.githubusercontent.com/comchienlab/dotfiles/main/install.sh)
```

### Linting and Static Analysis
```bash
# Syntax dry-run check (verifies bash syntax without execution)
find . -name "*.sh" -not -empty -exec bash -n {} +

# Lint specific script with ShellCheck
shellcheck -x fgit.sh
shellcheck -x fsetup.sh
shellcheck -x qkcommit.sh
shellcheck -x install.sh

# Lint all shell scripts across repository
find . -name "*.sh" -not -empty -exec shellcheck {} +
```

### Diagnostic Tools
```bash
# Run 9router built-in diagnostic checks
bash llm/setup_9router.sh doctor

# Run 9router diagnostics with JSON output
bash llm/setup_9router.sh doctor --json
```

---

## Code Conventions & Common Patterns

### Shell Dialect & Compatibility
- **Non-POSIX Standard**: Scripts strictly target Bash 4+ or Zsh. Avoid rewriting scripts into POSIX `/bin/sh` syntax.
- **Shebangs**:
  - `#!/bin/bash` for cross-platform/Linux scripts (`fgit.sh`, `fsetup.sh`, `qkcommit.sh`, `install.sh`, `backend/qkbe.sh`).
  - `#!/bin/zsh` for macOS maintenance scripts (`macos/qkmacos.sh`).
  - `#!/usr/bin/env bash` for standalone server scripts (`linux/vps_optimize.sh`, `linux/fub_clean.sh`, `fonts/nerdfont-installer.sh`).
- Use modern Bash features: `[[ ... ]]` for conditionals, `read -rd '' -a` for array splitting, `<(...)` for process substitution, and `${var%.*}` parameter expansions.

### Execution Modes & Error Handling
- **Interactive UI Scripts (`fgit.sh`, `fsetup.sh`, `qkcommit.sh`)**:
  - Do **NOT** use `set -e` or `set -u`. In interactive scripts, user cancellations in `gum` (pressing `Esc` or choosing `No`) return non-zero exit codes. Uncontrolled `set -e` aborts the shell instead of permitting graceful control flow.
  - Guard critical steps explicitly:
    ```bash
    gum confirm "Proceed with commit?" || exit 1
    ```
- **Server & Non-Interactive Scripts (`linux/vps_optimize.sh`, `setup_9router.sh`, `linux/fub_clean.sh`)**:
  - Enforce strict error handling: `set -euo pipefail`.
  - Use trap handlers for diagnostics and cleanup:
    ```bash
    trap 'echo "Error occurred at line $LINENO"' ERR
    ```

### Naming Conventions
- **Global Constants & Configuration**: `UPPER_SNAKE_CASE` (e.g., `INSTALL_DIR`, `REPO_URL`, `JAVA_VERSION`, `SWAP_PATH`).
- **Local Variables & Function Scope**: `lower_snake_case` (e.g., `commit_tag`, `commit_scope`, `current_branch`, `selected_package`).
- **Functions**: `lower_snake_case` (e.g., `show_preview`, `get_emoji`, `purge_package`, `clean_trash`).
- **Git Branches**: `type/description` (e.g., `feat/user-auth`, `fix/login-bug`, `chore/bump-deps`).
- **Flyway Migrations**: `V<YYYYMMDD>_<order>__<type>_<description>.sql` (e.g., `V20260925_01__INIT_create_tables.sql`).
- **Conventional Commits**: Format enforced via `qkcommit.sh` and `fgit.sh`:
  ```
  type(scope): emoji - description
  ```
  Example: `feat(auth): ✨ - add oauth login workflow`

### Charm `gum` TUI Design Patterns
All interactive tooling adheres to standard `gum` components:
- **Title Banners**:
  ```bash
  gum style --border double --margin "1" --padding "1" --border-foreground "#FF5733" "🚀 Title"
  ```
- **Menus & Selections**:
  ```bash
  # Single choice
  action=$(gum choose "Option 1" "Option 2")

  # Multi-choice
  apps=$(gum choose --no-limit "App 1" "App 2" "App 3")

  # Fuzzy filter search
  branch=$(git branch --all | gum filter --placeholder "Search branch...")
  ```
- **Inputs & Prompts**:
  ```bash
  input_val=$(gum input --placeholder "Enter value..." --char-limit 50)
  ```
- **Confirmation Guards**:
  ```bash
  if gum confirm "Are you sure you want to proceed?"; then
      # execute action
  fi
  ```
- **Progress Spinners**:
  ```bash
  gum spin --spinner dot --title "Processing..." -- command_to_execute
  ```
- **Color Palette Conventions**:
  - Success: Bright green (`--foreground 46` or `#27ae60`)
  - Error: Bright red (`--foreground 196` or `#c0392b`)
  - Warning / Header: Gold/Yellow (`--foreground 220` or `#f1c40f`)
  - Information / Prompt: Blue (`--foreground "#3498db"`)
  - Secondary / Preview: Muted gray (`--foreground 245`)

### Dependency Verification Pattern
Check tool existence before running subroutines:
```bash
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

if ! command_exists gum; then
    echo "❌ gum is required but not installed." >&2
    exit 1
fi
```

---

## Important Files

### Core Executables & Entry Points
- `install.sh`: Central bootstrap installer that installs `gum`, provisions `~/.local/bin`, and downloads `fgit`, `fsetup`, and `qkcommit`.
- `fsetup.sh`: Workstation setup manager (Desktop apps, Gnome packages, dev runtimes, swap creation, system cleanup).
- `fgit.sh`: Interactive Git management tool (status, branch creation/checkout, conventional commit, pull/merge, stash).
- `qkcommit.sh`: Standalone conventional commit wizard with Gitmoji integration and push automation.

### Dotfiles & Configurations
- `config/shell/.zshrc`: Primary interactive Zsh shell profile (aliases for `eza`, `lazydocker`, `bun`, environment exports for SDKMAN/FNM).
- `config/shell/.zshfn`: Modular Zsh helper functions (safe delete `dl`, Claude Code profile switchers `use-claude` and `use-glm`).
- `config/shell/starship.toml`: Prompt theme configuration with Catppuccin Mocha color scheme.
- `config/ghostty/config`: Ghostty terminal configuration (fonts, opacity, keybindings, clipboard safety).
- `config/ghostty/custom.css`: GTK CSS sheet for Ghostty terminal window padding and border radius.
- `config/zed/settings.json`: Zed editor configuration with Claude 3.5 Sonnet, disabled telemetry, and Geist/JetBrains fonts.

### Specialized Infrastructure Scripts
- `linux/create_swap.sh`: Interactive swap file creation for Linux hosts.
- `linux/debloat.sh`: Removes pre-installed packages to reclaim disk space.
- `linux/vps_optimize.sh`: Non-interactive VPS tuning pipeline (swap, sysctl, ulimits, UFW, fail2ban, systemd).
- `linux/fub_clean.sh`: Interactive multi-select Ubuntu cleanup assistant with dry-run mode.
- `linux/certbot-kit.sh`: Let's Encrypt certificate issuance for bare IP addresses via multiple ACME clients.
- `macos/qkmacos.sh`: macOS maintenance and cache cleanup wizard.
- `backend/qkbe.sh`: Backend developer assistant with Flyway migration repairs and dev environment tooling.
- `backend/qkflyway.sh`: Oracle Flyway SQL migration filename generator.
- `fonts/nerdfont-installer.sh`: GitHub release scraper and installer for Nerd Fonts.
- `llm/setup_9router.sh`: VPS AI proxy router deployment script with tiered tuning and built-in health check diagnostics.
- `rclone/rclone-tool.sh`: Rclone cloud storage management utility.

---

## Runtime/Tooling Preferences

### Required Interpreters & Tools
- **Bash 4+**: Required for root and utility scripts.
- **Zsh**: Primary user shell (`config/shell/.zshrc`) and `macos/qkmacos.sh` interpreter.
- **Charm `gum`**: Required for all interactive CLI scripts. Auto-installed via Charm APT repository or Homebrew.
- **Git**: Required for version control operations and git worktree checks (`git rev-parse --is-inside-work-tree`).
- **curl / wget**: Required for remote script execution and asset downloads.
- **jq**: Required by `rclone-tool.sh`, `n8n-installer.sh`, and `setup_cliproxy.sh` for JSON parsing.

### Package Managers by Platform
- **Debian / Ubuntu**: Primary Linux platform. Uses `apt` (with PPAs for Charm, Docker, VS Code, Spotify) and `snap`.
- **macOS**: Secondary platform. Uses `brew` (Homebrew) for packages and formulas.

### Runtimes & Version Managers
- **Java**: Managed via **SDKMAN** (`Amazon Corretto 17.0.13`, `Maven 3.9.9`).
- **Node.js**: Managed via **FNM** or **Volta** (Node.js v18 LTS, Yarn v1).
- **Bun**: Configured in `config/shell/.zshrc` (`~/.bun/bin`).

---

## Testing & QA

### Test Frameworks & Coverage Expectations
- **No automated test frameworks are configured** (no Bats, shunit2, or shellspec suites exist).
- **No CI/CD pipelines exist**: There are no GitHub Actions workflows or automated pull request checks. Changes to `main` directly impact remote `curl | bash` consumers.

### Mandatory Pre-Commit Validation Workflow
Before committing any changes to shell scripts, perform the following validation:

1. **Syntax Validation (Dry-Run)**:
   Ensure no syntax errors exist without executing side effects:
   ```bash
   bash -n <modified_script.sh>
   ```
2. **Static Analysis with ShellCheck**:
   Lint modified scripts with ShellCheck:
   ```bash
   shellcheck -x <modified_script.sh>
   ```
3. **Manual Execution & TTY Verification**:
   - Because scripts rely heavily on `gum` for menus and prompts, they must be tested in an interactive terminal (TTY).
   - Verify input cancellation: test that pressing `Esc` or selecting `No` on `gum confirm` handles exit gracefully without crashing the shell.
4. **Commit Formatting**:
   Use `qkcommit.sh` or follow the conventional commit format:
   ```
   type(scope): emoji - description
   ```
