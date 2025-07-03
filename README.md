# My Dotfiles

My personal collection of dotfiles and scripts to streamline the setup of a new Linux or macOS environment.

## 🚀 Installation

Run the following command to install the necessary tools and set up the environment:

```sh
curl -fsSL https://raw.githubusercontent.com/comchienlab/linux-setup/main/install.sh | bash
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
bash <(curl -fsSL https://raw.githubusercontent.com/comchienlab/dotfiles/main/create_swap.sh)
```
</details>

<details>
<summary><code>debloat.sh</code> - Debloat System</summary>

This script helps in removing pre-installed software that you may not need, freeing up disk space and system resources.

To run:
```sh
bash <(curl -fsSL https://raw.githubusercontent.com/comchienlab/dotfiles/main/debloat.sh)
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

---

## ⚙️ Configuration Files

This repository also includes configuration files for various tools to maintain a consistent development environment.

-   **Zsh & Starship:** `.zshrc` and `starship.toml` for a customized and informative shell prompt.
-   **Ghostty:** `ghostty/config` and `ghostty/custom.css` for the Ghostty terminal emulator.
-   **Zed:** `zed/setting.json` for the Zed code editor.