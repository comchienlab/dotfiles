#!/bin/bash

# Kiểm tra nếu gum chưa được cài đặt
if ! command -v gum &> /dev/null; then
    echo -e "\e[31m⚠ Gum chưa được cài đặt! Hãy chạy:\e[0m"
    echo -e "\e[36mbrew install gum\e[0m"
    exit 1
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
