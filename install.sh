#!/bin/bash
# install.sh - Install Minimal-Light theme and XFCE configuration
# Usage: bash install.sh [--user <username>] [--help]
#
# Dependencies: curl or wget, tar (with xz support)

ZAFIRO_URL="https://github.com/zayronxio/Zafiro-icons/releases/download/1.3/Zafiro-Icons-Light.tar.xz"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_USER="${1:-$USER}"

# Detect download tool
if command -v curl &>/dev/null; then
    DOWNLOAD_CMD="curl -fL --progress-bar -o"
elif command -v wget &>/dev/null; then
    DOWNLOAD_CMD="wget -q --show-progress -O"
else
    echo "Error: neither curl nor wget is available. Please install one of them."
    exit 1
fi
TARGET_HOME=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --user)
            TARGET_USER="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: bash install.sh [--user <username>]"
            echo ""
            echo "  --user <username>   Install for a specific user (default: current user)"
            echo "  --help              Show this help message"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

# Resolve target user's home directory
if [[ "$TARGET_USER" == "$USER" ]]; then
    TARGET_HOME="$HOME"
else
    TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
    if [[ -z "$TARGET_HOME" ]]; then
        echo "Error: user '$TARGET_USER' not found."
        exit 1
    fi
fi

echo "==> Installing Minimal-Light theme for user: $TARGET_USER"
echo "    Home: $TARGET_HOME"
echo ""

# Check permissions when installing for another user
if [[ "$TARGET_USER" != "$USER" ]] && [[ "$EUID" -ne 0 ]]; then
    echo "Warning: installing for another user without root privileges."
    echo "You may need to run this script with sudo."
    read -r -p "Continue anyway? [y/N] " confirm
    [[ "$confirm" =~ ^[yY]$ ]] || exit 1
fi

# -------------------------------------------------------
# 1. Install GTK theme (Minimal-Light)
# -------------------------------------------------------
echo "[1/5] Installing GTK theme Minimal-Light..."
THEMES_DIR="$TARGET_HOME/.local/share/themes"
mkdir -p "$THEMES_DIR"
cp -r "$SCRIPT_DIR/themes/Minimal-Light" "$THEMES_DIR/"
echo "      -> $THEMES_DIR/Minimal-Light"

# -------------------------------------------------------
# 2. Download and install icon theme (Zafiro-Icons-Light)
# -------------------------------------------------------
echo "[2/5] Downloading Zafiro-Icons-Light from GitHub..."
ICONS_DIR="$TARGET_HOME/.local/share/icons"
mkdir -p "$ICONS_DIR"

TMP_ARCHIVE=$(mktemp /tmp/zafiro-icons-XXXXXX.tar.xz)
$DOWNLOAD_CMD "$TMP_ARCHIVE" "$ZAFIRO_URL"
echo "      Extracting..."
tar -xJf "$TMP_ARCHIVE" -C "$ICONS_DIR/"
rm -f "$TMP_ARCHIVE"
echo "      -> $ICONS_DIR/Zafiro-Icons-Light"

if command -v gtk-update-icon-cache &>/dev/null; then
    gtk-update-icon-cache -f -t "$ICONS_DIR/Zafiro-Icons-Light" 2>/dev/null || true
fi

# -------------------------------------------------------
# 3. Install wallpapers
# -------------------------------------------------------
echo "[3/5] Installing wallpapers..."
BACKGROUNDS_DEST="/usr/local/share/backgrounds"

if [[ "$EUID" -eq 0 ]]; then
    mkdir -p "$BACKGROUNDS_DEST"
    cp "$SCRIPT_DIR/backgrounds/"* "$BACKGROUNDS_DEST/"
    echo "      -> $BACKGROUNDS_DEST"
else
    # Fall back to user-local path and patch the desktop config
    BACKGROUNDS_DEST="$TARGET_HOME/.local/share/backgrounds"
    mkdir -p "$BACKGROUNDS_DEST"
    cp "$SCRIPT_DIR/backgrounds/"* "$BACKGROUNDS_DEST/"
    echo "      -> $BACKGROUNDS_DEST (user-local, no root available)"
fi

# -------------------------------------------------------
# 4. Install XFCE configuration
# -------------------------------------------------------
echo "[4/5] Installing XFCE configuration..."
XFCONF_DIR="$TARGET_HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
mkdir -p "$XFCONF_DIR"

for xml_file in "$SCRIPT_DIR/config/xfce4/xfconf/xfce-perchannel-xml/"*.xml; do
    filename=$(basename "$xml_file")
    dest="$XFCONF_DIR/$filename"
    if [[ -f "$dest" ]]; then
        cp "$dest" "${dest}.bak"
        echo "      Backup: ${dest}.bak"
    fi
    # If backgrounds were installed to user-local path, patch the desktop config
    if [[ "$filename" == "xfce4-desktop.xml" && "$BACKGROUNDS_DEST" != "/usr/local/share/backgrounds" ]]; then
        sed "s|/usr/local/share/backgrounds|$BACKGROUNDS_DEST|g" "$xml_file" > "$dest"
    else
        cp "$xml_file" "$dest"
    fi
    echo "      -> $dest"
done

# Install panel launcher .desktop files
PANEL_DIR="$TARGET_HOME/.config/xfce4/panel"
if [[ -d "$SCRIPT_DIR/config/xfce4/panel" ]]; then
    for launcher_dir in "$SCRIPT_DIR/config/xfce4/panel/launcher-"*/; do
        launcher_name=$(basename "$launcher_dir")
        dest_launcher="$PANEL_DIR/$launcher_name"
        mkdir -p "$dest_launcher"
        cp "$launcher_dir"*.desktop "$dest_launcher/" 2>/dev/null || true
        echo "      -> $dest_launcher"
    done
fi

# -------------------------------------------------------
# 5. Fix file ownership when installing for another user
# -------------------------------------------------------
if [[ "$TARGET_USER" != "$USER" ]] && [[ "$EUID" -eq 0 ]]; then
    echo "[5/5] Fixing file ownership..."
    chown -R "$TARGET_USER":"$TARGET_USER" \
        "$THEMES_DIR/Minimal-Light" \
        "$ICONS_DIR/Zafiro-Icons-Light" \
        "$TARGET_HOME/.local/share/backgrounds" \
        "$XFCONF_DIR" \
        "$PANEL_DIR"
else
    echo "[5/5] File ownership: OK (same user)"
fi

echo ""
echo "==> Installation complete!"
echo ""
echo "    To apply the theme:"
echo "    1. Log out and log back into your XFCE session"
echo "       OR run: xfce4-panel --restart && xfsettingsd --replace &"
echo ""
echo "    2. If some settings are not applied automatically:"
echo "       - Go to Settings > Appearance and select 'Minimal-Light'"
echo "       - Go to Settings > Icons and select 'Zafiro-Icons-Light'"
