#!/bin/bash

# Define default versions for tools
JAVA_VERSION="17.0.13-amzn"  # Amazon Corretto 17.0.13
MAVEN_VERSION="3.9.9"        # Maven 3.9.9
YARN_VERSION="1"             # Yarn v1

# Check if `gum` is installed, if not, install it
if ! command -v gum &> /dev/null; then
    echo "gum is not installed. Installing gum..."
    curl -sSL https://github.com/charmbracelet/gum/releases/latest/download/gum-linux-amd64.tar.gz | tar xz -C /tmp
    sudo mv /tmp/gum /usr/local/bin/
    echo "gum installed successfully."
fi

# Check if SDKMAN is installed
# Ensure SDKMAN is sourced if installed
if [ -f "$HOME/.sdkman/bin/sdkman-init.sh" ]; then
    source "$HOME/.sdkman/bin/sdkman-init.sh"
    SDKMAN_INSTALLED=true
else
    SDKMAN_INSTALLED=false
fi

# Main menu options
choice=$(gum choose "Run Flyway Migration" \
                    "Repair Flyway Migration" \
                    "Fast Create migration" \
                    "Fix Migration Order Conflicts" \
                    "Setup Development Environment")

# Print the selected option
echo "You selected: $choice"

case $choice in
    "Run Flyway Migration")
        # Run Flyway Migration using Maven
        if [ -f "config/flyway.properties" ]; then
            gum style --foreground 46 "Running Flyway migration using Maven..."
            mvn clean -Dflyway.configFiles=config/flyway.properties flyway:migrate
        else
            gum style --foreground 196 "Missing Flyway config file at 'config/flyway.properties'."
        fi
        ;;

    "Repair Flyway Migration")
        # Repair Flyway Migration using Maven
        if [ -f "config/flyway.properties" ]; then
            gum style --foreground 46 "Repairing Flyway migration using Maven..."
            mvn clean -Dflyway.configFiles=config/flyway.properties flyway:repair
        else
            gum style --foreground 196 "Missing Flyway config file at 'config/flyway.properties'."
        fi
        ;;

    "Fix Migration Order Conflicts")
        MIGRATION_DIR="sql/oracle"
        declare -A seen_files

        gum style \
          --border double \
          --margin "1" --padding "1" \
          --border-foreground 208 \
          --foreground 15 \
          "🛠 Fixing Migration Order Conflicts"

        # Find all migration files starting with V and ending with .sql
        mapfile -t files < <(find "$MIGRATION_DIR" -type f -name "V*.sql")

        # Group and check per date
        for filepath in "${files[@]}"; do
            filename=$(basename "$filepath")
            if [[ "$filename" =~ ^V([0-9]{8})_([0-9]{2})__.*\.sql$ ]]; then
                date="${BASH_REMATCH[1]}"
                order="${BASH_REMATCH[2]}"
                key="${date}_${order}"

                # If already seen a file with this date and order, we need to bump it
                if [[ -n "${seen_files[$key]}" ]]; then
                    next_order=$((10#$order + 1))
                    while [[ -n "${seen_files[${date}_$(printf "%02d" $next_order)]}" ]]; do
                        next_order=$((next_order + 1))
                    done

                    new_order=$(printf "%02d" $next_order)
                    new_filename=$(echo "$filename" | sed -E "s/^V${date}_[0-9]{2}/V${date}_${new_order}/")
                    new_filepath="$MIGRATION_DIR/$new_filename"

                    mv "$filepath" "$new_filepath"
                    gum style --foreground 220 "Renamed: $filename -> $new_filename"
                    seen_files["${date}_${new_order}"]=1
                else
                    seen_files["$key"]=1
                fi
            fi
        done

        gum style \
          --border normal \
          --margin "1" --padding "1" \
          --border-foreground 10 \
          --foreground 15 \
          "✔ Migration files re-ordered successfully"
        ;;

    "Fast Create migration")
        # Fast Create migration using Flyway
        if [ -f "config/flyway.properties" ]; then
            gum style --foreground 46 "Creating Flyway migration..."
        else
            gum style --foreground 196 "Missing Flyway config file at 'config/flyway.properties'."
        fi

        # Thư mục chứa migration files
        MIGRATION_DIR="sql/oracle"

        # Định dạng tên file: VYYYYMMDD_order__(uml,ddl)_shortdescription.sql
        TODAY=$(date +%Y%m%d)

        # Tìm số thứ tự lớn nhất của file migration hôm nay
        LATEST_ORDER=$(ls "$MIGRATION_DIR" | grep -oE "V${TODAY}_[0-9]{2}" | awk -F'_' '{print $2}' | sort -nr | head -n 1)

        # Nếu không có file nào hôm nay, bắt đầu từ 01
        if [[ -z "$LATEST_ORDER" ]]; then
            NEXT_ORDER="01"
        else
            NEXT_ORDER=$(printf "%02d" $((10#$LATEST_ORDER + 1)))
        fi

        # Hiển thị tiêu đề với màu sắc
        gum style \
          --border double \
          --margin "1" --padding "1" \
          --border-foreground 212 \
          --foreground 15 \
          "✨ Tạo file Flyway Migration ✨"

        # Chọn loại migration với menu đẹp hơn
        TYPE=$(gum choose "uml" "ddl")

        # Nhập mô tả ngắn với hộp nhập màu mè
        DESCRIPTION=$(gum input --placeholder "Nhập mô tả ngắn (không dấu cách)" --char-limit 50)
        DESCRIPTION=$(echo "$DESCRIPTION" | tr ' ' '_' | tr -cd 'a-zA-Z0-9_')

        # Tạo tên file
        FILENAME="V${TODAY}_${NEXT_ORDER}__${TYPE}_${DESCRIPTION}.sql"
        FILEPATH="$MIGRATION_DIR/$FILENAME"

        # Xác nhận với người dùng trước khi tạo file
        gum confirm "Tạo file: $FILENAME ?" && touch "$FILEPATH" && echo "-- Migration file: $FILENAME" > "$FILEPATH"

        # Hiển thị kết quả với hiệu ứng đẹp hơn
        gum style \
          --border normal \
          --margin "1" --padding "1" \
          --border-foreground 10 \
          --foreground 15 \
          "✔ File đã tạo thành công: $FILEPATH"
        ;;

    "Setup Development Environment")
        # Select tools to install (using gum's multi-selection feature)
        tools=$(gum choose --no-limit \
                    "Install SDKMAN" \
                    "Install Java (Amazon Corretto 17.0.13)" \
                    "Install Maven (3.9.9)" \
                    "Install Volta" \
                    "Install Node.js (v18 via Volta)" \
                    "Install Yarn (v$YARN_VERSION)" \
                    "Install Docker & Docker Compose")

        # If no tools selected, show a warning
        if [ -z "$tools" ]; then
            gum style --foreground 196 "No tools selected for installation."
            exit 1
        fi

        # Print selected tools
        echo "You selected the following tools for installation:"
        echo "$tools"

        # Convert the tools string into an array
        IFS=$'\n' read -rd '' -a tool_array <<< "$tools"

        # Loop through each selected tool and install it
        for tool in "${tool_array[@]}"; do
            case "$tool" in
                "Install SDKMAN")
                    if ! $SDKMAN_INSTALLED; then
                        gum style --foreground 46 "Installing SDKMAN..."
                        curl -s "https://get.sdkman.io" | bash
                        source "$HOME/.sdkman/bin/sdkman-init.sh"
                        SDKMAN_INSTALLED=true
                    else
                        gum style --foreground 196 "SDKMAN is already installed."
                    fi
                    ;;

                "Install Java (Amazon Corretto 17.0.13)")
                    if $SDKMAN_INSTALLED; then
                        gum style --foreground 46 "Installing Java (Amazon Corretto 17.0.13)..."
                        sdk install java $JAVA_VERSION
                    else
                        gum style --foreground 196 "SDKMAN is not installed. Please install SDKMAN first."
                    fi
                    ;;

                "Install Maven (3.9.9)")
                    if $SDKMAN_INSTALLED; then
                        gum style --foreground 46 "Installing Maven (3.9.9)..."
                        sdk install maven $MAVEN_VERSION
                    else
                        gum style --foreground 196 "SDKMAN is not installed. Please install SDKMAN first."
                    fi
                    ;;

                "Install Volta")
                    gum style --foreground 46 "Installing Volta..."
                    curl https://get.volta.sh | bash
                    source "$HOME/.volta/bin/volta"
                    ;;

                "Install Node.js (v18 via Volta)")
                    if command -v volta &> /dev/null; then
                        gum style --foreground 46 "Installing Node.js (v18)..."
                        volta install node@v18
                    else
                        gum style --foreground 196 "Volta is not installed. Install Volta first."
                    fi
                    ;;

                "Install Yarn (v$YARN_VERSION)")
                    gum style --foreground 46 "Installing Yarn v$YARN_VERSION..."
                    # First, ensure that npm is installed (if npm isn't available, Yarn won't work)
                    if command -v npm &> /dev/null; then
                        npm install -g yarn@$YARN_VERSION
                    else
                        gum style --foreground 196 "npm is not installed. Please install npm first."
                    fi
                    ;;

                "Install Docker & Docker Compose")
                    # Install Docker and Docker Compose
                    if ! command -v docker &> /dev/null; then
                        gum style --foreground 46 "Installing Docker..."
                        curl -fsSL https://get.docker.com | bash
                        sudo systemctl enable docker
                        sudo systemctl start docker
                        gum style --foreground 46 "Docker installed successfully."
                    else
                        gum style --foreground 196 "Docker is already installed."
                    fi

                    # Install Docker Compose
                    if ! command -v docker-compose &> /dev/null; then
                        gum style --foreground 46 "Installing Docker Compose..."
                        curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
                        sudo chmod +x /usr/local/bin/docker-compose
                        gum style --foreground 46 "Docker Compose installed successfully."
                    else
                        gum style --foreground 196 "Docker Compose is already installed."
                    fi
                    ;;
            esac
        done

        gum style --foreground 46 "Selected tools installation is complete!"
        ;;
esac
