# Repository Guidelines

## Project Overview

This repository is a developer environment automation and dotfiles repository for Linux (primarily Debian/Ubuntu) and macOS. It provides:
- Interactive TUI-based developer commands (`fsetup`, `fgit`) powered by Charm's `gum`.
- End-to-end infrastructure and tool setup scripts (Rclone, Nerd Fonts, Flyway, and LLM proxy routers).
- Curated terminal, editor, and shell configurations (Ghostty, Zed, Zsh, Starship prompt).

The repository adopts a remote-executable model where scripts can be executed directly via `bash <(curl -fsSL ...)` or installed locally into `~/.local/bin/`.

---

## Architecture & Data Flow

### Architecture Layers

1. **Interactive CLI Orchestrator Tier (`bin/`)**
   - Self-contained Bash/Zsh scripts providing interactive menu-driven interfaces (`gum choose`, `gum filter`, `gum input`, `gum confirm`).
   - Handles developer workflows: Git operations (`bin/fgit.sh`) and workstation provisioning (`bin/fsetup.sh`).
2. **Shared Helper Tier (`base/`)**
   - Policy-free shell helpers sourced by other scripts: colors, `command_exists()`, banner styling, and a gum availability check. Never installs anything.
3. **Task Script Tier (`scripts/`, `templates/`)**
   - Domain-specific automation: Linux system utilities (`scripts/linux/`), AI proxy deployment (`scripts/llm/`), font cache builders (`scripts/fonts/`), cloud storage (`scripts/rclone/`), and project starters (`templates/`).
4. **Shell Environment & Dotfile Tier (`config/`)**
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
- Downloads `bin/fgit.sh` and `bin/fsetup.sh` from raw GitHub URLs, removes the `.sh` extension, and grants executable permissions (`chmod +x`).

---

## Key Directories

| Directory | Purpose |
|---|---|
| `/` (Root) | Bootstrap installer (`install.sh`). |
| `bin/` | Commands installed to `~/.local/bin`: `fgit.sh` (Git workflow) and `fsetup.sh` (workstation provisioning). |
| `base/` | Shared shell helpers sourced by other scripts: `ui.sh` (colors, `command_exists()`, banner, gum availability check). |
| `templates/` | Starters meant to be copied into a project: `qkbe.sh` (Flyway migration runner/repair/creation, conflict resolution, entity scaffolding). |
| `scripts/linux/` | Linux system utilities: `create_swap.sh` (swap file creation), `debloat.sh` (pre-installed package removal), `vps_optimize.sh` (VPS tuning pipeline), `fub_clean.sh` (interactive cleanup assistant), `certbot-kit.sh` (Let's Encrypt certificates for bare IPs). |
| `scripts/llm/` | AI proxy deployment kits: `setup_9router.sh` (VPS router with tiered memory tuning, self-diagnostics doctor, systemd service) and `setup_cliproxy.sh` (CLIProxyAPI PLUS installer with Go build and Caddy SSL). |
| `scripts/fonts/` | Font management: `nerdfont-installer.sh` (queries GitHub release API, downloads selected Nerd Fonts, installs to `~/.local/share/fonts`, rebuilds font cache). |
| `scripts/rclone/` | Cloud storage tooling: `rclone-tool.sh` (interactive TUI for remote browsing, transfer queues, and configuration sync). |
| `config/` | Reference configurations, never executed: `shell/` (`.zshrc`, `.zshfn`, `starship.toml`), `ghostty/` (`config`, `custom.css`), `zed/` (`settings.json`), and `mise/` (`config.toml` — unified dev toolchain). |

---

## Development Commands

### Running Scripts Locally
```bash
# Execute core interactive tools directly
bash fgit.sh
bash fsetup.sh

# Execute utility scripts
bash scripts/linux/create_swap.sh
bash scripts/fonts/nerdfont-installer.sh
bash templates/qkbe.sh
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
shellcheck -x install.sh

# Lint all shell scripts across repository
find . -name "*.sh" -not -empty -exec shellcheck {} +
```

### Diagnostic Tools
```bash
# Run 9router built-in diagnostic checks
bash scripts/llm/setup_9router.sh doctor

# Run 9router diagnostics with JSON output
bash scripts/llm/setup_9router.sh doctor --json
```

---

## Code Conventions & Common Patterns

### Shell Dialect & Compatibility
- **Non-POSIX Standard**: Scripts strictly target Bash 4+ or Zsh. Avoid rewriting scripts into POSIX `/bin/sh` syntax.
- **Shebangs**:
  - `#!/bin/bash` for cross-platform/Linux scripts (`bin/fgit.sh`, `bin/fsetup.sh`, `install.sh`, `templates/qkbe.sh`).
  - `#!/usr/bin/env bash` for standalone server scripts (`scripts/linux/vps_optimize.sh`, `scripts/linux/fub_clean.sh`, `scripts/fonts/nerdfont-installer.sh`).
- Use modern Bash features: `[[ ... ]]` for conditionals, `read -rd '' -a` for array splitting, `<(...)` for process substitution, and `${var%.*}` parameter expansions.

### Execution Modes & Error Handling
- **Interactive UI Scripts (`bin/fgit.sh`, `bin/fsetup.sh`)**:
  - Do **NOT** use `set -e` or `set -u`. In interactive scripts, user cancellations in `gum` (pressing `Esc` or choosing `No`) return non-zero exit codes. Uncontrolled `set -e` aborts the shell instead of permitting graceful control flow.
  - Guard critical steps explicitly:
    ```bash
    gum confirm "Proceed with commit?" || exit 1
    ```
- **Server & Non-Interactive Scripts (`scripts/linux/vps_optimize.sh`, `setup_9router.sh`, `scripts/linux/fub_clean.sh`)**:
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
- **Conventional Commits**: Format enforced via `bin/fgit.sh`:
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

  > **gum v2:** `gum choose --prompt` was removed — use `--header` instead. All other flags in use are v2-compatible.
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

### Shared Helpers (`base/`)

`base/ui.sh` holds policy-free helpers: colors, `command_exists()`, `gum_available()`, `ui_info`/`ui_success`/`ui_warn`/`ui_error`, and `ui_banner()`. Source it, never execute it:

```bash
REPO_URL="https://raw.githubusercontent.com/comchienlab/dotfiles/main"
source <(curl -fsSL "$REPO_URL/base/ui.sh")
```

**It must never install anything, set shell options, print, or exit at source time.** Dependency policy stays with the caller — some scripts auto-install gum, some only check, some exit with instructions. That decision is deliberately not shared.

Cost: sourcing adds one network fetch per run and the script is no longer single-file. For short scripts (< ~100 lines) duplication is cheaper than coupling — keep those self-contained.

### Templates (`templates/`)

Starters to **copy**, not source:

| Template | Use for |
|---|---|
| `tui-tool.sh` | Interactive gum tool (menu, confirm, input) |
| `installer.sh` | `curl \| bash` installer that changes the system |
| `server-setup.sh` | Non-interactive server script with `set -euo pipefail` |

`qkbe.sh` also lives here: it hardcodes `MIGRATION_DIR="sql/oracle"` and `config/flyway.properties`, so it is designed to run inside a Java project, not as a global command.

---

## Important Files

### Core Executables & Entry Points
- `install.sh`: Central bootstrap installer that installs `gum`, provisions `~/.local/bin`, and downloads `fgit` and `fsetup`.
- `bin/fsetup.sh`: Workstation setup manager (Desktop apps, Gnome packages, dev runtimes, swap creation, system cleanup).
- `bin/fgit.sh`: Interactive Git management tool (status, branch creation/checkout, conventional commit, pull/merge, stash).

### Dotfiles & Configurations
- `config/shell/.zshrc`: Primary interactive Zsh shell profile (aliases for `eza`, `lazydocker`, `bun`, mise shell activation).
- `config/shell/.zshfn`: Modular Zsh helper functions (safe delete `dl`, Claude Code profile switchers `use-claude` and `use-glm`).
- `config/shell/starship.toml`: Prompt theme configuration with Catppuccin Mocha color scheme.
- `config/ghostty/config`: Ghostty terminal configuration (fonts, opacity, keybindings, clipboard safety).
- `config/ghostty/custom.css`: GTK CSS sheet for Ghostty terminal window padding and border radius.
- `config/zed/settings.json`: Zed editor configuration with Claude 3.5 Sonnet, disabled telemetry, and Geist/JetBrains fonts.

### Specialized Infrastructure Scripts
- `scripts/linux/create_swap.sh`: Interactive swap file creation for Linux hosts.
- `scripts/linux/debloat.sh`: Removes pre-installed packages to reclaim disk space.
- `scripts/linux/vps_optimize.sh`: Non-interactive VPS tuning pipeline (swap, sysctl, ulimits, UFW, fail2ban, systemd).
- `scripts/linux/fub_clean.sh`: Interactive multi-select Ubuntu cleanup assistant with dry-run mode.
- `scripts/linux/certbot-kit.sh`: Let's Encrypt certificate issuance for bare IP addresses via multiple ACME clients.
- `templates/qkbe.sh`: Backend developer assistant — Flyway migration run/repair/create, conflict resolution, entity scaffolding.
- `scripts/fonts/nerdfont-installer.sh`: GitHub release scraper and installer for Nerd Fonts.
- `scripts/llm/setup_9router.sh`: VPS AI proxy router deployment script with tiered tuning and built-in health check diagnostics.
- `scripts/rclone/rclone-tool.sh`: Rclone cloud storage management utility.

---

## Runtime/Tooling Preferences

### Required Interpreters & Tools
- **Bash 4+**: Required for root and utility scripts.
- **Zsh**: Primary user shell (`config/shell/.zshrc`).
- **Charm `gum`**: Required for all interactive CLI scripts. Auto-installed via Charm APT repository or Homebrew.
- **Git**: Required for version control operations and git worktree checks (`git rev-parse --is-inside-work-tree`).
- **curl / wget**: Required for remote script execution and asset downloads.
- **jq**: Required by `rclone-tool.sh` and `setup_cliproxy.sh` for JSON parsing.

### Package Managers by Platform
- **Debian / Ubuntu**: Primary Linux platform. Uses `apt` (with PPAs for Charm, Docker, VS Code, Spotify) and `snap`.
- **macOS**: Secondary platform. Uses `brew` (Homebrew) for packages and formulas.

### Runtimes & Version Managers
- **Java / Maven**: Managed via **mise** (`corretto-17`, `maven 3.9.9`).
- **Node.js / Yarn / pnpm**: Managed via **mise** (`node lts`, `yarn 1`, `pnpm 12`).
- **Go / Rust**: Managed via **mise** (`latest`).
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
   Use the conventional commit format:
   ```
   type(scope): emoji - description
   ```
