#!/bin/bash

# Check if `gum` is installed, if not, install it
if ! command -v gum &> /dev/null; then
    echo "gum is not installed. Installing gum..."
    curl -sSL https://github.com/charmbracelet/gum/releases/latest/download/gum-linux-amd64.tar.gz | tar xz -C /tmp
    sudo mv /tmp/gum /usr/local/bin/
    echo "gum installed successfully."
fi

# Main menu options
choice=$(gum choose "Run Flyway Migration" \
                    "Repair Flyway Migration" \
                    "Fast Create migration" \
                    "Fix Migration Order Conflicts")

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

esac
