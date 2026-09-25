# My Dotfiles

My personal collection of dotfiles and scripts to streamline the setup of a new Linux or macOS environment.

## 🚀 Installation

Run the following command to install the necessary tools and set up the environment:

```sh
curl -fsSL https://raw.githubusercontent.com/comchienlab/dotfiles/main/install.sh | bash
```

---

## ✨ Quick Commands

These are a series of "quick" commands to automate common developer tasks.

<details>
<summary><code>fsetup</code> - Quick Setup Operations</summary>

This script provides a menu-driven interface using `gum` to perform various setup tasks like updating the system, installing development tools, and setting up programming language environments.

To run, type the following command in your terminal:
```sh
fsetup
```
</details>

<details>
<summary><code>fgit</code> - Quick Git Operations</summary>

A script to simplify common Git workflows. It helps with tasks like adding, committing, and pushing changes, as well as more complex operations like rebasing and tagging.

To run, type the following command in your terminal:
```sh
fgit
```
</details>

<details>
<summary><code>qkcommit</code> - Quick Commit Operations</summary>

This script helps you write conventional commit messages easily. It prompts for the type of change, scope, and description.

To run, type the following command in your terminal:
```sh
qkcommit
```
</details>

<details>
<summary><code>qkmacos</code> - Quick macOS Setup</summary>

This script automates the setup and configuration of a macOS environment. It installs Homebrew, essential applications, and developer tools.

To install and run:
```sh
sudo curl -fsSL -o /usr/local/bin/qkmacos https://raw.githubusercontent.com/comchienlab/dotfiles/main/macos/qkmacos.sh && sudo chmod +x /usr/local/bin/qkmacos
qkmacos
```
</details>

---

## 🛠️ Installers & Utilities

A collection of scripts to install various tools and perform system utilities.

<details>
<summary><code>n8n-installer.sh</code> - Install n8n</summary>

Installs [n8n](https://n8n.io/), a free and source-available workflow automation tool.

To install:
```sh
bash <(curl -fsSL https://raw.githubusercontent.com/comchienlab/dotfiles/main/n8n/n8n-installer.sh)
```
</details>

<details>
<summary><code>rclone-tool.sh</code> - Install rclone tool</summary>

Installs and configures [rclone](https://rclone.org/), a command-line program to manage files on cloud storage.

To install:
```sh
sudo curl -fsSL -o /usr/local/bin/cccrclone https://raw.githubusercontent.com/comchienlab/dotfiles/main/rclone/rclone-tool.sh && sudo chmod +x /usr/local/bin/cccrclone
```
</details>

<details>
<summary><code>nerdfont-installer.sh</code> - Install Nerd Fonts</summary>

Installs Nerd Fonts, which are popular for developers and provide a wide range of glyphs and icons.

To run:
```sh
bash <(curl -fsSL https://raw.githubusercontent.com/comchienlab/dotfiles/main/fonts/nerdfont-installer.sh)
```
</details>

<details>
<summary><code>create_swap.sh</code> - Create Swap File</summary>

A script to create and enable a swap file on a Linux system, which is useful when the system runs out of physical RAM.

To run:
```sh
bash <(curl -fsSL https://raw.githubusercontent.com/comchienlab/dotfiles/main/linux/create_swap.sh)
```
</details>

<details>
<summary><code>debloat.sh</code> - Debloat System</summary>

This script helps in removing pre-installed software that you may not need, freeing up disk space and system resources.

To run:
```sh
bash <(curl -fsSL https://raw.githubusercontent.com/comchienlab/dotfiles/main/linux/debloat.sh)
```
</details>

<details>
<summary><code>vps_optimize.sh</code> - VPS Performance Tuning</summary>

Non-interactive tuning pipeline for low-spec VPS hosts: swap, sysctl, ulimits, UFW, fail2ban, systemd limits, unused service pruning, and a BBR check.

To run:
```sh
sudo bash <(curl -fsSL https://raw.githubusercontent.com/comchienlab/dotfiles/main/linux/vps_optimize.sh)
```
</details>

<details>
<summary><code>fub_clean.sh</code> - Ubuntu Cleanup Assistant</summary>

Interactive multi-select cleanup for Ubuntu: APT caches, journal logs, trash/temp files, browser and developer caches, snap/flatpak/docker pruning, and manual package purge. Includes a dry-run mode.

To run:
```sh
sudo bash <(curl -fsSL https://raw.githubusercontent.com/comchienlab/dotfiles/main/linux/fub_clean.sh)
```
</details>

<details>
<summary><code>certbot-kit.sh</code> - IP Certificate Setup</summary>

Issues Let's Encrypt certificates for **bare IP addresses** (no domain required), with auto-detection across multiple ACME clients and the 6-day shortlived profile.

To run:
```sh
sudo bash <(curl -fsSL https://raw.githubusercontent.com/comchienlab/dotfiles/main/linux/certbot-kit.sh)
```
</details>

<details>
<summary><code>qkflyway.sh</code> - Flyway Database Migrations</summary>

A helper script for running [Flyway](https://flywaydb.org/) database migrations.

To run:
```sh
bash <(curl -fsSL https://raw.githubusercontent.com/comchienlab/dotfiles/main/backend/qkflyway.sh)
```
</details>

<details>
<summary><code>qkbe.sh</code> - Backend Developer Assistant</summary>

Backend workflow helper: runs Flyway migrations and repairs, generates entity scaffolding (UML/DDL), and installs pinned toolchain versions via SDKMAN and Volta.

To run:
```sh
bash <(curl -fsSL https://raw.githubusercontent.com/comchienlab/dotfiles/main/backend/qkbe.sh)
```
</details>

---

## 👩‍🏫 9Router
Interactive menu (no args):
```sh
curl -fsSL http://st.changcomchien.workers.dev/9router | sudo bash
```

Direct subcommand (note `-s --` — required when passing args via pipe):
```sh
curl -fsSL https://raw.githubusercontent.com/comchienlab/dotfiles/main/llm/setup_9router.sh | sudo bash -s -- install
```

After install, the toolkit installs itself as `/usr/local/bin/9router`, so:
```sh
sudo 9router doctor      # weekly health check
sudo 9router update      # pull latest + redeploy
sudo 9router status      # one-screen summary
sudo 9router rollback    # restore previous build
```

---

## 🔀 CLIProxyAPI PLUS

All-in-one deployment for [CLIProxyAPIPlus](https://github.com/router-for-me/CLIProxyAPIPlus) on Ubuntu/Debian (amd64, arm64): Go binary + Caddy HTTPS + systemd service + UFW rules.

```sh
sudo bash <(curl -fsSL https://raw.githubusercontent.com/comchienlab/dotfiles/main/llm/setup_cliproxy.sh)
```

---

## ⚙️ Configuration Files

This repository also includes configuration files for various tools to maintain a consistent development environment.

-   **Shell:** `config/shell/.zshrc`, `config/shell/.zshfn`, and `config/shell/starship.toml` for a customized and informative shell prompt.
-   **Ghostty:** `config/ghostty/config` and `config/ghostty/custom.css` for the Ghostty terminal emulator.
-   **Zed:** `config/zed/settings.json` for the Zed code editor.
