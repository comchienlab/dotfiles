#!/usr/bin/env bash

set -e

# ========== 1. Install gum if missing ==========
if ! command -v gum &>/dev/null; then
  echo "🔧 Installing gum from Charm.sh APT repo..."
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
  echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" \
    | sudo tee /etc/apt/sources.list.d/charm.list > /dev/null
  sudo apt update && sudo apt install gum -y
fi

# ========== 2. Get available font zips from GitHub ==========
font_list=$(gum spin --spinner dot --title "Fetching Nerd Font list..." -- bash -c '
  curl -s https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest |
  grep browser_download_url |
  grep -E "zip\"" |
  sed -E "s/.*\/([^\/]+)\.zip\"/\1/" |
  sort -u
')

# ========== 3. Select a font zip ==========
selected_font=$(echo "$font_list" | gum choose --header "🎨 Select a Nerd Font to download:")

if [[ -z "$selected_font" ]]; then
  echo "❌ No font selected. Exiting."
  exit 0
fi

# ========== 4. Download selected font zip ==========
gum spin --spinner dot --title "📦 Downloading $selected_font.zip..." -- bash -c "
  mkdir -p /tmp/nerdfont_zip &&
  cd /tmp/nerdfont_zip &&
  curl -sLO https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${selected_font}.zip
"

# ========== 5. List TTF/OTF font files inside zip ==========
unzip -Z1 "/tmp/nerdfont_zip/${selected_font}.zip" | grep -Ei '\.(ttf|otf)$' > /tmp/font_files.txt

# ========== 6. Let user select specific fonts to install ==========
selected_fonts=$(cat /tmp/font_files.txt | gum choose --no-limit --header "📝 Select fonts to install:")

if [[ -z "$selected_fonts" ]]; then
  echo "❌ No fonts selected from zip. Exiting."
  exit 0
fi

# ========== 7. Extract selected fonts ==========
install_dir="$HOME/.local/share/fonts/NerdFonts/$selected_font"
mkdir -p "$install_dir"

echo "$selected_fonts" | while read -r font; do
  gum spin --spinner dot --title "Installing $font..." -- \
    unzip -j "/tmp/nerdfont_zip/${selected_font}.zip" "$font" -d "$install_dir" >/dev/null
done

# ========== 8. Refresh font cache ==========
gum spin --spinner line --title "Refreshing font cache..." -- fc-cache -fv > /dev/null

# ========== 9. Done ==========
echo ""
echo "✅ Installed fonts to: $install_dir"
echo "$selected_fonts"
