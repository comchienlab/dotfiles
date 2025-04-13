#!/usr/bin/env bash

set -e

# --- Check and install gum if missing ---
if ! command -v gum &>/dev/null; then
  echo "🔧 Installing gum from Charm.sh APT repo..."

  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
  echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list > /dev/null

  sudo apt update && sudo apt install gum -y
fi

# --- Get font list from GitHub release ---
font_list=$(gum spin --spinner dot --title "Fetching Nerd Font list..." -- \
  bash -c "curl -s https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest |
  grep browser_download_url |
  grep -E 'zip\"$' |
  sed -E 's/.*\/([^\/]+)\.zip\"/\1/' |
  sort -u")

# --- Select font zip ---
selected_font=$(echo "$font_list" | gum choose --header "🎨 Select a Nerd Font Zip to download:")

if [[ -z "$selected_font" ]]; then
  echo "❌ No font selected. Exiting."
  exit 0
fi

# --- Download the zip ---
gum spin --spinner dot --title "📦 Downloading $selected_font.zip..." -- \
bash -c "
  mkdir -p /tmp/nerdfont_zip &&
  cd /tmp/nerdfont_zip &&
  curl -sLO https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${selected_font}.zip
"

# --- List TTF fonts inside zip ---
unzip -l "/tmp/nerdfont_zip/${selected_font}.zip" | grep '\.ttf' | awk '{print $NF}' > /tmp/font_files.txt

# --- Let user select which fonts to install ---
selected_fonts=$(cat /tmp/font_files.txt | gum choose --no-limit --header "📝 Select fonts to install:")

if [[ -z "$selected_fonts" ]]; then
  echo "❌ No fonts selected from zip. Exiting."
  exit 0
fi

# --- Extract selected fonts ---
install_dir="$HOME/.local/share/fonts/NerdFonts/$selected_font"
mkdir -p "$install_dir"

echo "$selected_fonts" | while read -r font; do
  gum spin --spinner dot --title "Installing $font..." -- \
  unzip -j "/tmp/nerdfont_zip/${selected_font}.zip" "$font" -d "$install_dir" >/dev/null
done

# --- Refresh font cache ---
gum spin --spinner line --title "Refreshing font cache..." -- \
  fc-cache -fv > /dev/null

echo "✅ Installed fonts:"
echo "$selected_fonts"
