#!/bin/bash

# Source common library functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Try multiple locations for common.sh
if [ -f "$SCRIPT_DIR/lib/common.sh" ]; then
    source "$SCRIPT_DIR/lib/common.sh"
elif [ -f "$(dirname "$SCRIPT_DIR")/lib/common.sh" ]; then
    source "$(dirname "$SCRIPT_DIR")/lib/common.sh"
elif [ -f "$HOME/.local/lib/common.sh" ]; then
    source "$HOME/.local/lib/common.sh"
else
    echo "Error: Cannot find lib/common.sh"
    exit 1
fi

# Ensure gum is installed
ensure_gum_installed

gum style --border double --padding "1 2" --margin "1" --foreground 212 --border-foreground 212 "🚀 TẠO SWAP FILE TUỲ CHỌN"

# MENU chọn dung lượng
CHOICE=$(gum choose --cursor "👉" "4GB" "8GB" "16GB" "32GB" "💬 Nhập tay")

if [[ "$CHOICE" == "💬 Nhập tay" ]]; then
  SWAP_GB=$(gum input --placeholder "VD: 12, 20, 64..." --prompt "📦 Dung lượng Swap (GB): ")
  if ! [[ "$SWAP_GB" =~ ^[0-9]+$ ]]; then
    gum style --foreground 196 "🚫 Sai định dạng. Phải là số nguyên."
    exit 1
  fi
else
  SWAP_GB=$(echo "$CHOICE" | grep -oE '[0-9]+')
fi

gum confirm "Xác nhận tạo swap ${SWAP_GB}GB? Swap cũ sẽ bị xoá!" || exit 0

# Tạo swap
gum spin --spinner line --title "Tắt & xoá swap cũ..." -- sudo swapoff -a && sudo rm -f /swapfile

gum spin --spinner dot --title "Tạo file swap ${SWAP_GB}GB..." -- sudo dd if=/dev/zero of=/swapfile bs=1G count="$SWAP_GB" status=none

gum spin --spinner dot --title "Cấp quyền 600..." -- sudo chmod 600 /swapfile

gum spin --spinner dot --title "Định dạng swap..." -- sudo mkswap /swapfile

gum spin --spinner dot --title "Bật swap..." -- sudo swapon /swapfile

# Ghi vào fstab nếu chưa có
if ! grep -q "/swapfile" /etc/fstab; then
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab > /dev/null
  gum style --foreground 35 "✓ Đã thêm swap vào /etc/fstab"
else
  gum style --foreground 35 "✓ Swap đã có trong /etc/fstab"
fi

gum style --padding "1 2" --border normal --border-foreground 10 "✅ TẠO SWAP ${SWAP_GB}GB THÀNH CÔNG!"
free -h | gum format
