#!/bin/bash

# Display main menu banner
gum style --border double --margin "1" --padding "1" --border-foreground "#FF5733" "✅ fsetup process completed!"

# Define default versions
JAVA_VERSION="17.0.13-amzn" # Amazon Corretto 17.0.13
MAVEN_VERSION="3.9.9"       # Maven 3.9.9
NODE_VERSION="18"           # Node.js v18 (via Volta)
YARN_VERSION="1"            # Yarn v1
ZSHRC_CONFIG="https://raw.githubusercontent.com/comchienlab/dotfiles/main/.config/.zshrc"
STARSHIP_CONFIG="https://raw.githubusercontent.com/comchienlab/dotfiles/main/.config/starship.toml"

# Check if `gum` is installed, if not install it
if ! command -v gum &>/dev/null; then
    echo "Gum is required but not installed. Installing..."
    # Detect OS and install gum
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if ! command -v brew &>/dev/null; then
            gum style --foreground 196 "Homebrew is not installed. Please install it first."
            exit 1
        fi
        brew install gum
    else
        # Ubuntu/Debian
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
        echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
        sudo apt update && sudo apt install -y gum
    fi
fi

# Check if SDKMAN is installed and source it
if [ -f "$HOME/.sdkman/bin/sdkman-init.sh" ]; then
    source "$HOME/.sdkman/bin/sdkman-init.sh"
    SDKMAN_INSTALLED=true
else
    SDKMAN_INSTALLED=false
fi

# Main menu options
choice=$(gum choose "🖥️ Install Desktop" \
                    "📦 Install Packages Gnome" \
                    "📚 Install Libraries" \
                    "🧹 Debloat Gnome" \
                    "⌨️ Install Ibus Bamboo" \
                    "⚙️ Fast Configuration" \
                    "🗑️ Purge Package" \
                    "👻 Install Ghostty Terminal"\
                    "🔠 Install Nerd Fonts" \
                    "💾 Create Swap File" \
                    "🛠️ Setup Development Environment")

# Print the selected option
echo "You selected: $choice"

case $choice in
"📦 Install Packages Gnome")
    gum style --foreground 46 "Starting 'Install Packages Gnome' process..."

    # Install Zsh
    gum style --foreground 46 "Installing Zsh..."
    sudo apt install zsh
    gum style --foreground 46 "Changing default shell to zsh..."
    chsh -s $(which zsh)
    gum style --foreground 46 "Downloading .zshrc configuration..."
    curl -fsSL -o ~/.zshrc ${ZSHRC_CONFIG}
    gum style --foreground 46 "Creating .zsh directory..."
    mkdir -p ~/.zsh
    gum style --foreground 46 "Cloning zsh-autosuggestions repository..."
    git clone https://github.com/zsh-users/zsh-autosuggestions ~/.zsh/zsh-autosuggestions
    gum style --foreground 46 "Cloning zsh-syntax-highlighting repository..."
    git clone https://github.com/zsh-users/zsh-syntax-highlighting ~/.zsh/zsh-syntax-highlighting
    gum style --foreground 46 "Cloning fzf-tab repository..."
    git clone https://github.com/Aloxaf/fzf-tab ~/.zsh/fzf-tab

    # Install Git
    gum style --foreground 46 "Installing Git..."
    sudo apt install git
    gum style --foreground 46 "Configuring Git aliases..."
    git config --global alias.co checkout
    git config --global alias.br branch
    git config --global alias.ci commit
    git config --global alias.st status
    git config --global pull.rebase true

    # Install starship shell prompt
    gum style --foreground 46 "Installing starship shell prompt..."
    curl -sS https://starship.rs/install.sh | sh
    gum style --foreground 46 "Downloading starship configuration..."
    curl -fsSL -o ~/.config/starship.toml ${STARSHIP_CONFIG}

    # Enable contrib and non-free repo
    gum style --foreground 46 "Enabling contrib and non-free repository..."
    sudo apt-add-repository contrib non-free -y

    # Install ibus-bamboo
    gum style --foreground 46 "Adding repository for ibus-bamboo..."
    echo 'deb http://download.opensuse.org/repositories/home:/lamlng/Debian_12/ /' | sudo tee /etc/apt/sources.list.d/home:lamlng.list
    gum style --foreground 46 "Adding key for ibus-bamboo repository..."
    curl -fsSL https://download.opensuse.org/repositories/home:lamlng/Debian_12/Release.key | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/home_lamlng.gpg >/dev/null
    gum style --foreground 46 "Updating apt repository..."
    sudo apt update
    gum style --foreground 46 "Installing ibus-bamboo..."
    sudo apt -y install ibus-bamboo

    # Install essential packages
    gum style --foreground 46 "Installing essential packages..."
    sudo apt -y install curl unzip btop neovim intel-media-va-driver-non-free libavcodec-extra gstreamer1.0-vaapi
    ;;

"🖥️ Install Desktop")
    # Select tools to install (using gum's multi-selection feature)
    apps=$(gum choose --no-limit \
        "Chrome" \
        "📲 Local Send" \
        "🆚 VSCode" \
        "🎧 Spotify" \
        "🌐 Zen Browsers" \
        "💡 Install IDEA" \
        "🛢️ Install DataGrip" \
        "💻 Install Zed" \
        "🛰️ Install Postman" \
        "📦 Other")

    # If no tools selected, show a warning
    if [ -z "$apps" ]; then
        gum style --foreground 196 "No tools selected for installation."
        exit 1
    fi

    # Print selected tools
    echo "You selected the following tools for installation:"
    echo "$apps"

    # Convert the tools string into an array
    IFS=$'\n' read -rd '' -a app_array <<<"$apps"

    # Loop through each selected tool and install it
    for app in "${app_array[@]}"; do
        case "$app" in
        "Chrome")
            gum style --foreground 46 "Downloading Google Chrome installer..."
            cd /tmp
            wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
            gum style --foreground 46 "Installing Google Chrome..."
            sudo apt install -y ./google-chrome-stable_current_amd64.deb
            gum style --foreground 46 "Removing Google Chrome installer..."
            rm google-chrome-stable_current_amd64.deb
            gum style --foreground 46 "Setting Google Chrome as default browser..."
            xdg-settings set default-web-browser google-chrome.desktop
            cd -
            ;;

        "📲 Local Send")
            # Install Local Send
            gum style --foreground 46 "Installing Local Send..."
            cd /tmp
            LOCALSEND_VERSION=$(curl -s "https://api.github.com/repos/localsend/localsend/releases/latest" | grep -Po '"tag_name": "v\K[^"\\]*')
            wget -O localsend.deb "https://github.com/localsend/localsend/releases/latest/download/LocalSend-${LOCALSEND_VERSION}-linux-x86-64.deb"
            sudo apt install -y ./localsend.deb
            rm localsend.deb
            cd -
            ;;
        "🌐 Zen Browsers")
            # Install Local Send
            gum spin --spinner minidot --title "Installing Zen Browsers..." -- bash <(curl -s https://updates.zen-browser.app/install.sh)
            ;;

        "🆚 VSCode")
            # Install VSCode
            gum style --foreground 46 "Installing VSCode..."
            cd /tmp
            wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor >packages.microsoft.gpg
            sudo install -D -o root -g root -m 644 packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
            echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null
            rm -f packages.microsoft.gpg
            cd -
            gum style --foreground 46 "Updating apt repository for VSCode..."
            sudo apt update -y
            gum style --foreground 46 "Installing VSCode package..."
            sudo apt install -y code
            ;;
        "💡 Install IDEA")
            gum style --foreground 46 "Installing IDEA..."
            sudo snap install intellij-idea-ultimate --classic
            gum style --foreground 46 "Installed IDEA."
            ;;

        "🛢️ Install DataGrip")
            gum spin --spinner dot --title "Installing DataGrip..." -- sudo snap install datagrip --classic
            gum style --foreground 46 "Installed DataGrip."
            ;;

        "💻 Install Zed")
            gum spin --spinner dot --title "Installing Zed...." --show-output false -- curl -f https://zed.dev/install.sh | sh
            gum style --foreground 46 "Installed Zed."
            ;;

        "🛰️ Install Postman")
            gum style --foreground 46 "Installing Postman..."
            wget https://dl.pstmn.io/download/latest/linux64 -O postman.tar.gz
            sudo tar -xzf postman.tar.gz -C /opt
            sudo ln -s /opt/Postman/Postman /usr/bin/postman
            rm postman.tar.gz
            echo """
                        [Desktop Entry]
                        Type=Application
                        Name=Postman
                        Icon=/opt/Postman/app/resources/app/assets/icon.png
                        Exec="/opt/Postman/Postman"
                        Comment=Postman Desktop App
                        Categories=Development;Code;
                        """ >>/usr/share/applications/postman.desktop
            gum style --foreground 46 "Installed Postman."
            ;;

        "🎧 Spotify")
            # Install Spotify
            gum style --foreground --border --align center 46 "Installing Spotify..."
            curl -sS https://download.spotify.com/debian/pubkey_6224F9941A8AA6D1.gpg | sudo gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/spotify.gpg
            echo "deb [signed-by=/etc/apt/trusted.gpg.d/spotify.gpg] http://repository.spotify.com stable non-free" | sudo tee /etc/apt/sources.list.d/spotify.list
            sudo apt update
            sudo apt install -y spotify-client
            ;;

        "📦 Other")
            gum style --foreground 46 "Installing gnome-tweak-tool, gnome-sushi, fzf, ripgrep, bat, eza, zoxide, plocate, btop, apache2-utils, fd-find, tldr..."
            sudo apt install -y gnome-tweak-tool
            sudo apt install -y gnome-sushi
            sudo apt install -y fzf ripgrep bat eza zoxide plocate btop apache2-utils fd-find tldr
            ;;
        esac
    done

    gum style --foreground 46 "Selected tools installation is complete!"
    ;;

"🧹 Debloat Gnome")
    gum style --foreground 46 "Debloating Gnome packages..."
    sudo apt -y autopurge evolution synaptic gnome-games gnome-sound-recorder gnome-music libreoffice-core libreoffice-common gnome-contacts baobab simple-scan yelp gnome-maps rhythmbox totem transmission-gtk
    ;;

"🗑️ Purge Package")
    gum style --foreground 46 "Starting 'Purge Package' process..."

    # Function to search, select, and purge packages using dpkg
    purge_package() {
        # Check if gum is installed
        if ! command -v gum &>/dev/null; then
            echo "gum is not installed. Please install gum first."
            exit 1
        fi

        # Prompt the user to input the search query
        search_query=$(gum input --placeholder "Enter package name to search")
        if [ -z "$search_query" ]; then
            gum style --foreground 196 "❌ Search query cannot be empty."
            exit 1
        fi

        # Use dpkg to list installed packages and filter by the search query
        packages=$(dpkg --get-selections | grep "$search_query" | awk '{print $1}')

        # If no packages match the search query, exit
        if [ -z "$packages" ]; then
            gum style --foreground 196 "No packages found for the search term '$search_query'."
            exit 1
        fi

        # Use gum to let the user select a package from the list
        selected_package=$(echo "$packages" | gum choose --limit 1 --prompt "Select a package to purge")

        # If no package is selected, exit
        if [ -z "$selected_package" ]; then
            gum style --foreground 196 "No package selected for purging."
            exit 1
        fi

        # Confirm the action with the user
        echo "You selected: $selected_package"
        if gum confirm "Are you sure you want to purge $selected_package?"; then
            echo "Purging $selected_package..."
            sudo dpkg --purge "$selected_package"
            sudo apt-get autoremove -y # Remove dependencies that are no longer needed
            echo "$selected_package has been purged."
        else
            echo "Action canceled."
        fi
        }


    # Run the purge_package function
    purge_package
    ;;

"⌨️ Install Ibus Bamboo")
    gum style --foreground 46 "Installing Ibus Bamboo..."
    gum style --foreground 46 "Adding ibus-bamboo repository..."
    echo 'deb http://download.opensuse.org/repositories/home:/lamlng/Debian_12/ /' | sudo tee /etc/apt/sources.list.d/home:lamlng.list
    gum style --foreground 46 "Adding ibus-bamboo repository key..."
    curl -fsSL https://download.opensuse.org/repositories/home:lamlng/Debian_12/Release.key | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/home_lamlng.gpg > /dev/null
    gum style --foreground 46 "Updating apt repositories..."
    sudo apt update
    gum style --foreground 46 "Installing ibus-bamboo package..."
    sudo apt -y install ibus-bamboo
    gum style --foreground 46 "IBUS-Bamboo installation complete!"
    ;;

"📚 Install Libraries")
    gum style --foreground 46 "Installing Libraries..."
    sudo apt install -y \
        build-essential pkg-config autoconf bison clang rustc \
        libssl-dev libreadline-dev zlib1g-dev libyaml-dev libreadline-dev libncurses5-dev libffi-dev libgdbm-dev libjemalloc2 \
        libvips imagemagick libmagickwand-dev mupdf mupdf-tools gir1.2-gtop-2.0 gir1.2-clutter-1.0 \
        redis-tools sqlite3 libsqlite3-0 libmysqlclient-dev libpq-dev postgresql-client postgresql-client-common
    ;;

"⚙️ Fast Configuration")
    gum style --foreground 196 "Disabling Hibernate..."
    sudo echo "AllowHibernation=no" >>/etc/systemd/sleep.conf
    sudo echo "AllowSuspendThenHibernate=no" >>/etc/systemd/sleep.conf

    gum style --foreground 196 "Disabling Tracker services..."
    systemctl --user mask tracker-extract-3 tracker-miner-fs-3 tracker-miner-control-3 tracker-miner-rss-3 tracker-writeback-3 tracker-xdg-portal-3
    sudo apt-mark hold tracker
    sudo apt-mark hold tracker-extract
    sudo apt-mark hold tracker-miner-fs

    sudo chmod -x /usr/libexec/tracker-extract-3
    sudo chmod -x /usr/libexec/tracker-miner-fs-3

    tracker3 reset --filesystem --rss # Clean all database
    tracker3 daemon --terminate
    ;;

"👻 Install Ghostty Terminal")
    gum style --foreground 46 "Fetching OS release information..."
    source /etc/os-release
    gum style --foreground 46 "Detecting system architecture..."
    ARCH=$(dpkg --print-architecture)
    gum style --foreground 46 "Fetching latest Ghostty Terminal release URL..."
    GHOSTTY_DEB_URL=$(
        curl -s https://api.github.com/repos/mkasberg/ghostty-ubuntu/releases/latest |
            grep -oP "https://github.com/mkasberg/ghostty-ubuntu/releases/download/[^\s/]+/ghostty_[^\s/_]+_${ARCH}_${VERSION_ID}.deb"
    )
    if [ -z "$GHOSTTY_DEB_URL" ]; then
        gum style --foreground 196 "❌ Could not find a compatible Ghostty Terminal release for your system."
        exit 1
    fi
    gum style --foreground 46 "Preparing to download Ghostty Terminal package..."
    GHOSTTY_DEB_FILE=$(basename "$GHOSTTY_DEB_URL")
    gum style --foreground 46 "Downloading Ghostty Terminal package..."
    curl -LO "$GHOSTTY_DEB_URL"
    gum style --foreground 46 "Installing Ghostty Terminal..."
    sudo dpkg -i "$GHOSTTY_DEB_FILE"
    gum style --foreground 46 "Cleaning up Ghostty Terminal package file..."
    rm "$GHOSTTY_DEB_FILE"
    ;;

"🔠 Install Nerd Fonts")
    gum style --foreground 46 "Running Nerd Font installer..."
    bash <(curl -fsSL https://raw.githubusercontent.com/comchienlab/dotfiles/main/fonts/nerdfont-installer.sh)
    ;;

"💾 Create Swap File")
    gum style --foreground 46 "Running swap file creation script..."
    bash <(curl -fsSL https://raw.githubusercontent.com/comchienlab/dotfiles/main/create_swap.sh)
    ;;

"🛠️ Setup Development Environment")
    tools=$(gum choose --no-limit \
                "🛠️ Install SDKMAN" \
                "☕ Install Java (Amazon Corretto 17.0.13)" \
                "📦 Install Maven (3.9.9)" \
                "⚡ Install Volta" \
                "📁 Install FNM" \
                "🐳 Install LazyDocker" \
                "🟩 Install Node.js (v18 via FNM)" \
                "🧶 Install Yarn (v1)" \
                "🐳 Install Docker & Docker Compose")

    # If no tools selected, show a warning
    if [ -z "$tools" ]; then
        gum style --foreground 196 "No tools selected for installation."
        exit 1
    fi

    # Print selected tools
    echo "You selected the following tools for installation:"
    echo "$tools"

    # Convert the tools string into an array
    IFS=$'\n' read -rd '' -a tool_array <<<"$tools"

    # Loop through each selected tool and install it
    for tool in "${tool_array[@]}"; do
        case "$tool" in
        "🛠️ Install SDKMAN")
            if ! $SDKMAN_INSTALLED; then
                gum style --foreground 46 "Installing SDKMAN..."
                curl -s "https://get.sdkman.io" | bash
                source "$HOME/.sdkman/bin/sdkman-init.sh"
                SDKMAN_INSTALLED=true
            else
                gum style --foreground 196 "SDKMAN is already installed."
            fi
            ;;

        "☕ Install Java (Amazon Corretto 17.0.13)")
            if $SDKMAN_INSTALLED; then
                gum style --foreground 46 "Installing Java (Amazon Corretto 17.0.13)..."
                sdk install java $JAVA_VERSION
            else
                gum style --foreground 196 "SDKMAN is not installed. Please install SDKMAN first."
            fi
            ;;

        "📦 Install Maven (3.9.9)")
            if $SDKMAN_INSTALLED; then
                gum style --foreground 46 "Installing Maven (3.9.9)..."
                sdk install maven $MAVEN_VERSION
            else
                gum style --foreground 196 "SDKMAN is not installed. Please install SDKMAN first."
            fi
            ;;

        "⚡ Install Volta")
            gum style --foreground 46 "Installing Volta..."
            curl https://get.volta.sh | bash
            source "$HOME/.volta/bin/volta"
            ;;
        "📁 Install FNM")
            gum style --foreground 46 "Installing FNM..."
            curl -fsSL https://fnm.vercel.app/install | bash
            fnm install --lts
            gum style --foreground 46 "FNM installed successfully!"
            ;;
        "🐳 Install LazyDocker")
            gum style --foreground 46 "Installing LazyDocker..."
            cd /tmp
            LAZYDOCKER_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazydocker/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
            curl -sLo lazydocker.tar.gz "https://github.com/jesseduffield/lazydocker/releases/latest/download/lazydocker_${LAZYDOCKER_VERSION}_Linux_x86_64.tar.gz"
            tar -xf lazydocker.tar.gz lazydocker
            gum style --foreground 46 "Installing LazyDocker executable..."
            sudo install lazydocker /usr/local/bin
            gum style --foreground 46 "Cleaning up LazyDocker installers..."
            rm lazydocker.tar.gz lazydocker
            cd -
            ;;

        "🟩 Install Node.js (v18 via FNM)")
            if command -v fnm &>/dev/null; then
                gum style --foreground 46 "Installing Node.js (v18)..."
                fnm install v18
                fnm use v18
            else
                gum style --foreground 196 "FNM is not installed. Install FNM first."
            fi
            ;;

        "🧶 Install Yarn (v1)")
            if command -v npm &>/dev/null; then
                gum style --foreground 46 "Installing Yarn (v1)..."
                npm install -g yarn
            else
                gum style --foreground 196 "NPM is not installed. Install Node.js and NPM first."
            fi
            ;;

        "🐳 Install Docker & Docker Compose")
            gum style --foreground 46 "Installing Docker & Docker Compose..."
            gum style --foreground 46 "Setting up Docker repository and key..."
            sudo install -m 0755 -d /etc/apt/keyrings
            sudo wget -qO /etc/apt/keyrings/docker.asc https://download.docker.com/linux/ubuntu/gpg
            sudo chmod a+r /etc/apt/keyrings/docker.asc
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
            gum style --foreground 46 "Updating apt repository for Docker..."
            sudo apt update
            gum style --foreground 46 "Installing Docker packages..."
            sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras
            gum style --foreground 46 "Adding current user to Docker group..."
            sudo usermod -aG docker ${USER}
            gum style --foreground 46 "Configuring Docker daemon log options..."
            echo '{"log-driver":"json-file","log-opts":{"max-size":"10m","max-file":"5"}}' | sudo tee /etc/docker/daemon.json
            gum style --foreground 46 "Docker & Docker Compose installed successfully!"
            ;;
        esac
    done

    gum style --foreground 46 "Selected tools installation is complete!"
    ;;

*)
    gum style --foreground 196 "❌ Invalid selection! Please select a valid option from the menu."
    exit 1
    ;;
esac
