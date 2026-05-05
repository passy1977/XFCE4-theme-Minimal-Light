#!/bin/bash
# install.sh - Install Minimal-Light theme and XFCE configuration
# Usage: bash install.sh [--remote] [--user <username>] [--help]
#
# Dependencies: tar (with xz support)
# Remote install dependencies: curl

set -euo pipefail

TARGET_USER="${SUDO_USER:-$USER}"
INVOKING_USER="${SUDO_USER:-$USER}"
TARGET_HOME=""
SCRIPT_DIR=""
REMOTE_MODE=0
REMOTE_ARCHIVE_URL="${MINIMAL_LIGHT_REMOTE_ARCHIVE_URL:-https://github.com/passy1977/XFCE4-theme-Minimal-Light/archive/refs/heads/main.tar.gz}"
TEMP_DIR=""
DEFAULT_BACKGROUNDS_DIR="/usr/local/share/backgrounds"

timestamp() {
    date +%Y%m%d%H%M%S
}

backup_path() {
    local source_path="$1"

    if [[ -e "$source_path" ]]; then
        local backup_dest="${source_path}.bak.$(timestamp)"
        mv "$source_path" "$backup_dest"
        echo "      Backup: $backup_dest"
    fi
}

stop_xfconfd() {
    if [[ "$TARGET_USER" != "$INVOKING_USER" ]]; then
        return
    fi

    if [[ -z "${DISPLAY:-}" || -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
        return
    fi

    local xfconfd_pid
    xfconfd_pid=$(pgrep -u "$USER" xfconfd 2>/dev/null || true)
    if [[ -n "$xfconfd_pid" ]]; then
        echo "      Stopping xfconfd (PID $xfconfd_pid) before writing config files..."
        kill "$xfconfd_pid" 2>/dev/null || true
        local i
        for i in {1..10}; do
            kill -0 "$xfconfd_pid" 2>/dev/null || break
            sleep 0.2
        done
    fi
}

reload_current_xfce_session() {
    if [[ "$TARGET_USER" != "$INVOKING_USER" ]]; then
        return
    fi

    if [[ -z "${DISPLAY:-}" || -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
        return
    fi

    if ! command -v xfconf-query &>/dev/null; then
        return
    fi

    echo "[5/5] Reloading active XFCE session..."

    xfconf-query -c xsettings -p /Net/ThemeName -n -t string -s "Minimal-Light" 2>/dev/null || \
        xfconf-query -c xsettings -p /Net/ThemeName -t string -s "Minimal-Light" 2>/dev/null || true
    xfconf-query -c xsettings -p /Net/IconThemeName -n -t string -s "Zafiro-Icons-Light" 2>/dev/null || \
        xfconf-query -c xsettings -p /Net/IconThemeName -t string -s "Zafiro-Icons-Light" 2>/dev/null || true
    xfconf-query -c xfwm4 -p /general/theme -n -t string -s "Minimal-Light" 2>/dev/null || \
        xfconf-query -c xfwm4 -p /general/theme -t string -s "Minimal-Light" 2>/dev/null || true

    # Wait for xfconfd to be fully up before reloading xfdesktop.
    # The xfconf-query calls above trigger its restart; without this wait
    # xfdesktop --reload reads stale/empty wallpaper values from xfconfd.
    local i
    for i in {1..20}; do
        pgrep -u "$USER" xfconfd &>/dev/null && break
        sleep 0.2
    done

    if command -v xfce4-panel &>/dev/null; then
        xfce4-panel -r >/dev/null 2>&1 || true
    fi

    if command -v xfdesktop &>/dev/null; then
        xfdesktop --reload >/dev/null 2>&1 || true
    fi

    echo "      -> Active XFCE session reloaded"
}

usage() {
    echo "Usage: bash install.sh [--remote] [--user <username>]"
    echo ""
    echo "  --remote            Download the repository archive before installing"
    echo "  --user <username>   Install for a specific user (default: invoking user, even under sudo)"
    echo "  --help              Show this help message"
}

cleanup() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}

bootstrap_remote_assets() {
    if ! command -v curl &>/dev/null; then
        echo "Error: curl is required when using --remote."
        exit 1
    fi

    TEMP_DIR=$(mktemp -d)
    echo "==> Downloading project files from remote archive..."
    curl -fsSL "$REMOTE_ARCHIVE_URL" | tar -xzf - -C "$TEMP_DIR"

    SCRIPT_DIR=$(find "$TEMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)
    if [[ -z "$SCRIPT_DIR" ]]; then
        echo "Error: unable to extract project archive from $REMOTE_ARCHIVE_URL"
        exit 1
    fi
}

ensure_local_assets() {
    if [[ ! -d "$SCRIPT_DIR/themes/Minimal-Light" ]] || [[ ! -f "$SCRIPT_DIR/icons/Zafiro-Icons-Light.tar.xz" ]]; then
        echo "Error: repository assets were not found next to install.sh."
        echo "Run the script from the project root or use --remote."
        exit 1
    fi
}

trap cleanup EXIT

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --remote)
            REMOTE_MODE=1
            shift
            ;;
        --user)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --user requires a username."
                usage
                exit 1
            fi
            TARGET_USER="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Error: unknown argument '$1'."
            usage
            exit 1
            ;;
    esac
done

if [[ "$REMOTE_MODE" -eq 1 ]]; then
    bootstrap_remote_assets
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

ensure_local_assets

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

# Warn if installing for another user that they must have logged in at least once
if [[ "$TARGET_USER" != "$USER" ]]; then
    echo "Note: '$TARGET_USER' must have logged in at least once before running this script,"
    echo "      so that their home directory and XFCE profile are properly initialized."
    echo ""
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
# 2. Install icon theme (Zafiro-Icons-Light)
# -------------------------------------------------------
echo "[2/5] Installing Zafiro-Icons-Light..."
ICONS_DIR="$TARGET_HOME/.local/share/icons"
mkdir -p "$ICONS_DIR"

ICONS_ARCHIVE="$SCRIPT_DIR/icons/Zafiro-Icons-Light.tar.xz"
if [[ ! -f "$ICONS_ARCHIVE" ]]; then
    echo "Error: icons archive not found at $ICONS_ARCHIVE"
    exit 1
fi
tar -xJf "$ICONS_ARCHIVE" -C "$ICONS_DIR/"
echo "      -> $ICONS_DIR/Zafiro-Icons-Light"

if command -v gtk-update-icon-cache &>/dev/null; then
    gtk-update-icon-cache -f -t "$ICONS_DIR/Zafiro-Icons-Light" 2>/dev/null || true
fi

# -------------------------------------------------------
# 3. Install wallpapers
# -------------------------------------------------------
echo "[3/5] Installing wallpapers..."
BACKGROUNDS_DEST="$DEFAULT_BACKGROUNDS_DIR"

if [[ "$EUID" -eq 0 ]]; then
    mkdir -p "$BACKGROUNDS_DEST"
    cp "$SCRIPT_DIR/backgrounds/"* "$BACKGROUNDS_DEST/"
    echo "      -> $BACKGROUNDS_DEST"
else
    # Fall back to a user-local path when no privileged install is available
    BACKGROUNDS_DEST="$TARGET_HOME/.local/share/backgrounds"
    mkdir -p "$BACKGROUNDS_DEST"
    cp "$SCRIPT_DIR/backgrounds/"* "$BACKGROUNDS_DEST/"
    echo "      -> $BACKGROUNDS_DEST (user-local, no root available)"
fi

# -------------------------------------------------------
# 4. Install XFCE and Thunar configuration
# -------------------------------------------------------
# Stop xfconfd before writing config files so the running daemon's in-memory
# state cannot overwrite newly installed XML files when the session exits.
stop_xfconfd
echo "[4/5] Installing XFCE and Thunar configuration..."
XFCONF_DIR="$TARGET_HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
mkdir -p "$XFCONF_DIR"

for xml_file in "$SCRIPT_DIR/config/xfce4/xfconf/xfce-perchannel-xml/"*.xml; do
    filename=$(basename "$xml_file")
    dest="$XFCONF_DIR/$filename"
    if [[ -f "$dest" ]]; then
        cp "$dest" "${dest}.bak"
        echo "      Backup: ${dest}.bak"
    fi
    # Normalize wallpaper paths in the desktop config to the chosen install target.
    if [[ "$filename" == "xfce4-desktop.xml" ]]; then
        sed "s|$DEFAULT_BACKGROUNDS_DIR|$BACKGROUNDS_DEST|g" "$xml_file" > "$dest"
    else
        cp "$xml_file" "$dest"
    fi
    echo "      -> $dest"
done

# Install panel launcher .desktop files
PANEL_DIR="$TARGET_HOME/.config/xfce4/panel"
if [[ -d "$SCRIPT_DIR/config/xfce4/panel" ]]; then
    backup_path "$PANEL_DIR"
    mkdir -p "$PANEL_DIR"
    for launcher_dir in "$SCRIPT_DIR/config/xfce4/panel/launcher-"*/; do
        launcher_name=$(basename "$launcher_dir")
        dest_launcher="$PANEL_DIR/$launcher_name"
        mkdir -p "$dest_launcher"
        cp "$launcher_dir"*.desktop "$dest_launcher/" 2>/dev/null || true
        echo "      -> $dest_launcher"
    done
fi

THUNAR_CONFIG_SRC="$SCRIPT_DIR/config/Thunar"
THUNAR_CONFIG_DIR="$TARGET_HOME/.config/Thunar"
if [[ -d "$THUNAR_CONFIG_SRC" ]]; then
    mkdir -p "$THUNAR_CONFIG_DIR"
    shopt -s nullglob
    thunar_files=("$THUNAR_CONFIG_SRC"/*)
    for thunar_file in "${thunar_files[@]}"; do
        [[ -f "$thunar_file" ]] || continue
        filename=$(basename "$thunar_file")
        dest="$THUNAR_CONFIG_DIR/$filename"
        if [[ -f "$dest" ]]; then
            cp "$dest" "${dest}.bak"
            echo "      Backup: ${dest}.bak"
        fi
        cp "$thunar_file" "$dest"
        echo "      -> $dest"
    done
    shopt -u nullglob
fi

SESSIONS_CACHE_DIR="$TARGET_HOME/.cache/sessions"
if [[ -d "$SESSIONS_CACHE_DIR" ]]; then
    shopt -s nullglob
    session_files=("$SESSIONS_CACHE_DIR"/xfce4-session-*)
    if (( ${#session_files[@]} > 0 )); then
        STALE_SESSIONS_DIR="$SESSIONS_CACHE_DIR/minimal-light-stale-session-$(timestamp)"
        mkdir -p "$STALE_SESSIONS_DIR"
        for session_file in "${session_files[@]}"; do
            mv "$session_file" "$STALE_SESSIONS_DIR/"
        done
        echo "      Archived stale XFCE session cache -> $STALE_SESSIONS_DIR"
    fi
    shopt -u nullglob
fi

# -------------------------------------------------------
# 5. Fix file ownership when installing for another user
# -------------------------------------------------------
if [[ "$TARGET_USER" != "$USER" ]] && [[ "$EUID" -eq 0 ]]; then
    echo "[5/5] Fixing file ownership..."
    OWNERSHIP_TARGETS=(
        "$THEMES_DIR/Minimal-Light"
        "$ICONS_DIR/Zafiro-Icons-Light"
        "$XFCONF_DIR"
    )
    if [[ -d "$PANEL_DIR" ]]; then
        OWNERSHIP_TARGETS+=("$PANEL_DIR")
    fi
    if [[ -d "$THUNAR_CONFIG_DIR" ]]; then
        OWNERSHIP_TARGETS+=("$THUNAR_CONFIG_DIR")
    fi
    if [[ -n "${STALE_SESSIONS_DIR:-}" && -d "$STALE_SESSIONS_DIR" ]]; then
        OWNERSHIP_TARGETS+=("$STALE_SESSIONS_DIR")
    fi
    chown -R "$TARGET_USER":"$TARGET_USER" "${OWNERSHIP_TARGETS[@]}"
    # Only chown backgrounds if installed to user-local path
    if [[ "$BACKGROUNDS_DEST" != "$DEFAULT_BACKGROUNDS_DIR" ]]; then
        chown -R "$TARGET_USER":"$TARGET_USER" "$BACKGROUNDS_DEST"
    fi
else
    echo "[5/5] File ownership: OK (same user)"
fi

reload_current_xfce_session

echo ""
echo "==> Installation complete!"
echo ""
echo "    Existing panel state was replaced and stale XFCE session cache was archived when present."
echo "    If you installed this for another user or outside an active XFCE session, log out and log back in."
echo ""
echo "    If some settings are not applied automatically:"
echo "       - Go to Settings > Appearance and select 'Minimal-Light'"
echo "       - Go to Settings > Icons and select 'Zafiro-Icons-Light'"
