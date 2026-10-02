#!/usr/bin/env bash

# Google Fonts TUI Installer
# Interactive installer for official Google Fonts desktop binaries powered by Charm gum

# ========== 1. Dependency Pre-flight ==========
if ! command -v gum &>/dev/null; then
  echo "🔧 Installing gum from Charm.sh APT repo..."
  if command -v apt-get &>/dev/null; then
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
    echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" \
      | sudo tee /etc/apt/sources.list.d/charm.list > /dev/null
    sudo apt update && sudo apt install -y gum
  elif command -v brew &>/dev/null; then
    brew install gum
  else
    echo "❌ gum is required. Please install it: https://github.com/charmbracelet/gum" >&2
    exit 1
  fi
fi

if ! command -v curl &>/dev/null; then
  gum style --foreground 196 "❌ curl is required but not installed."
  exit 1
fi

if ! command -v fc-cache &>/dev/null; then
  gum style --foreground 196 "❌ fontconfig (fc-cache) is required but not installed."
  exit 1
fi

# ========== 2. Fetch official Google Fonts catalog ==========
tmp_csv=$(mktemp /tmp/google_families.XXXXXX)
tmp_meta=$(mktemp /tmp/google_meta.XXXXXX)
trap 'rm -f "$tmp_csv" "$tmp_meta"' EXIT

raw_catalog=$(gum spin --spinner dot --title "Fetching official Google Fonts catalog..." -- curl -fsSL "https://raw.githubusercontent.com/google/fonts/main/tags/all/families.csv")

if [[ -z "$raw_catalog" ]]; then
  gum style --foreground 196 "❌ Failed to fetch Google Fonts catalog."
  exit 1
fi

echo "$raw_catalog" > "$tmp_csv"
font_list=$(cut -d, -f1 "$tmp_csv" | sort -u)
rm -f "$tmp_csv"

if [[ -z "$font_list" ]]; then
  gum style --foreground 196 "❌ Failed to parse Google Fonts catalog."
  exit 1
fi

# ========== 3. Select a font via fuzzy search ==========
selected_font=$(echo "$font_list" | gum filter --placeholder "🔍 Search from 1900+ Google Fonts (e.g. Inter, Space Grotesk, Poppins)...")

if [[ -z "$selected_font" ]]; then
  gum style --foreground 245 "❌ No font selected. Exiting."
  exit 0
fi

# ========== 4. Search font files in official repository ==========
clean_slug=$(echo "$selected_font" | tr -d ' _-' | tr '[:upper:]' '[:lower:]')
hyphen_slug=$(echo "$selected_font" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')

matched_lic=""
matched_slug=""

gum spin --spinner dot --title "🔍 Fetching metadata for '$selected_font'..." -- bash -c "
  for slug in '$clean_slug' '$hyphen_slug'; do
    for lic in ofl ufl apache; do
      url=\"https://raw.githubusercontent.com/google/fonts/main/\${lic}/\${slug}/METADATA.pb\"
      if curl -fsSL \"\$url\" -o '$tmp_meta' 2>/dev/null; then
        echo \"\${lic}:\${slug}\" > '$tmp_meta.matched'
        exit 0
      fi
    done
  done
  exit 1
"

if [[ ! -s "$tmp_meta.matched" ]]; then
  rm -f "$tmp_meta" "$tmp_meta.matched"
  gum style --foreground 196 "❌ Font metadata not found for '$selected_font'."
  exit 1
fi

matched_info=$(cat "$tmp_meta.matched")
rm -f "$tmp_meta.matched"

matched_lic="${matched_info%%:*}"
matched_slug="${matched_info##*:}"

# ========== 5. Extract font filenames from METADATA.pb ==========
mapfile -t font_files < <(grep -E 'filename:\s*"' "$tmp_meta" | sed -E 's/.*filename:\s*"([^"]+)".*/\1/' | grep -Ei '\.(ttf|otf)$' | sort -u)
rm -f "$tmp_meta"

if [[ ${#font_files[@]} -eq 0 ]]; then
  gum style --foreground 196 "❌ No TTF/OTF files found for '$selected_font'."
  exit 1
fi

# ========== 6. Granular selection of font files ==========
if [[ ${#font_files[@]} -eq 1 ]]; then
  selected_files=("${font_files[0]}")
  gum style --foreground 220 "ℹ️ Single variable font available: ${selected_files[0]}"
else
  selected_raw=$(printf '%s\n' "${font_files[@]}" | gum choose --no-limit --selected="*" --header "📝 Select fonts to install (Space to toggle, Enter to confirm):")
  if [[ -z "$selected_raw" ]]; then
    gum style --foreground 245 "❌ No fonts selected. Exiting."
    exit 0
  fi
  mapfile -t selected_files <<< "$selected_raw"
fi

# ========== 7. Download and install selected fonts ==========
install_dir="$HOME/.local/share/fonts/GoogleFonts/$selected_font"
mkdir -p "$install_dir"

installed_count=0
for file in "${selected_files[@]}"; do
  file_url="https://raw.githubusercontent.com/google/fonts/main/${matched_lic}/${matched_slug}/${file}"
  dest_path="$install_dir/$file"

  if gum spin --spinner dot --title "📦 Downloading $file..." -- curl -gfsSL -o "$dest_path" "$file_url"; then
    if [[ -s "$dest_path" ]]; then
      ((installed_count++))
    else
      gum style --foreground 196 "❌ Downloaded file $file is empty."
      rm -f "$dest_path"
    fi
  else
    gum style --foreground 196 "❌ Failed to download $file."
    rm -f "$dest_path"
  fi
done

if [[ "$installed_count" -eq 0 ]]; then
  gum style --foreground 196 "❌ Failed to install any font files for '$selected_font'."
  rmdir "$install_dir" 2>/dev/null || true
  exit 1
fi

# ========== 8. Refresh font cache ==========
gum spin --spinner line --title "🔄 Refreshing font cache..." -- fc-cache -fv >/dev/null

# ========== 9. Done ==========
echo ""
gum style \
  --border rounded \
  --padding "1" \
  --foreground 46 \
  "✅ Installed '$selected_font' ($installed_count/${#selected_files[@]} files)" \
  "" \
  "Destination: $install_dir" \
  "License: ${matched_lic^^}"

echo "Installed files:"
for file in "${selected_files[@]}"; do
  if [[ -f "$install_dir/$file" ]]; then
    gum style --foreground 46 "  • $file"
  fi
done
echo ""
