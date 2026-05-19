#!/usr/bin/env bash
# =============================================================================
#  AppImage Installer — Graphical installer/uninstaller for AppImages on Linux
#  Installs to ~/Programs, creates .desktop entries, supports uninstall
# =============================================================================

set -euo pipefail

# ── Constants ────────────────────────────────────────────────────────────────
INSTALL_DIR="$HOME/Programs"
DESKTOP_DIR="$HOME/.local/share/applications"
ICONS_DIR="$HOME/.local/share/icons/appimage-installer"
REGISTRY="$HOME/.local/share/appimage-installer/registry.db"
REGISTRY_DIR="$(dirname "$REGISTRY")"
SCRIPT_NAME="appimage-installer"
SCRIPT_VERSION="1.0.0"

# ── Colors (for terminal fallback) ───────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

# ── Detect GUI backend ────────────────────────────────────────────────────────
detect_gui() {
    if command -v zenity &>/dev/null; then
        echo "zenity"
    elif command -v kdialog &>/dev/null; then
        echo "kdialog"
    elif command -v yad &>/dev/null; then
        echo "yad"
    else
        echo "none"
    fi
}

GUI=$(detect_gui)

# ── GUI Wrappers ──────────────────────────────────────────────────────────────

gui_info() {
    local title="$1" msg="$2"
    case "$GUI" in
        zenity)  zenity --info --title="$title" --text="$msg" --width=420 ;;
        kdialog) kdialog --title "$title" --msgbox "$msg" ;;
        yad)     yad --title="$title" --text="$msg" --button="OK:0" --width=420 ;;
        *)       echo -e "${GREEN}[INFO]${NC} $msg" ;;
    esac
}

gui_error() {
    local title="$1" msg="$2"
    case "$GUI" in
        zenity)  zenity --error --title="$title" --text="$msg" --width=420 ;;
        kdialog) kdialog --title "$title" --error "$msg" ;;
        yad)     yad --title="$title" --text="$msg" --button="OK:0" --image=dialog-error --width=420 ;;
        *)       echo -e "${RED}[ERROR]${NC} $msg" >&2 ;;
    esac
}

gui_question() {
    # Returns 0 = Yes, 1 = No
    local title="$1" msg="$2"
    case "$GUI" in
        zenity)  zenity --question --title="$title" --text="$msg" --width=420 ;;
        kdialog) kdialog --title "$title" --yesno "$msg" ;;
        yad)     yad --title="$title" --text="$msg" --button="Yes:0" --button="No:1" --width=420 ;;
        *)       read -r -p "$msg [y/N] " ans; [[ "$ans" =~ ^[Yy]$ ]] ;;
    esac
}

gui_file_picker() {
    local title="$1"
    case "$GUI" in
        zenity)  zenity --file-selection --title="$title" --file-filter="AppImage Files | *.AppImage *.appimage" ;;
        kdialog) kdialog --title "$title" --getopenfilename "$HOME" "*.AppImage *.appimage" ;;
        yad)     yad --title="$title" --file --file-filter="AppImage files | *.AppImage *.appimage" ;;
        *)       read -r -p "Enter full path to AppImage: " fpath; echo "$fpath" ;;
    esac
}

gui_entry() {
    local title="$1" label="$2" default="$3"
    case "$GUI" in
        zenity)  zenity --entry --title="$title" --text="$label" --entry-text="$default" ;;
        kdialog) kdialog --title "$title" --inputbox "$label" "$default" ;;
        yad)     yad --title="$title" --entry --text="$label" --entry-text="$default" ;;
        *)       read -r -p "$label [$default]: " val; echo "${val:-$default}" ;;
    esac
}

gui_progress() {
    # Reads lines from stdin, each line updates progress text
    local title="$1"
    case "$GUI" in
        zenity)
            zenity --progress --title="$title" --text="Starting…" \
                   --pulsate --auto-close --auto-kill --width=420
            ;;
        yad)
            yad --title="$title" --progress --pulsate --auto-close --width=420
            ;;
        *)
            cat  # just drain stdin
            ;;
    esac
}

gui_list() {
    # Show a list and return selected item
    # Args: title col1_header col2_header item1_col1 item1_col2 ...
    local title="$1"; shift
    case "$GUI" in
        zenity)
            zenity --list --title="$title" \
                   --column="Name" --column="Version" --column="Installed" \
                   --width=560 --height=420 "$@"
            ;;
        yad)
            yad --title="$title" --list \
                --column="Name" --column="Version" --column="Installed" \
                --width=560 --height=420 "$@"
            ;;
        *)
            # Terminal fallback: numbered list
            local items=("$@")
            local i=1
            while [[ $i -le ${#items[@]} ]]; do
                echo "  $((i/3+1)). ${items[$((i-1))]}  v${items[$i]}  (${items[$((i+1))]})"
                i=$((i+3))
            done
            read -r -p "Enter name to select (or blank to cancel): " sel
            echo "$sel"
            ;;
    esac
}

# ── Registry helpers ──────────────────────────────────────────────────────────

registry_init() {
    mkdir -p "$REGISTRY_DIR" "$INSTALL_DIR" "$DESKTOP_DIR" "$ICONS_DIR"
    [[ -f "$REGISTRY" ]] || touch "$REGISTRY"
}

registry_add() {
    local name="$1" version="$2" appimage_path="$3" desktop_path="$4" icon_path="$5"
    # Remove existing entry for this name
    registry_remove_entry "$name"
    echo "$name|$version|$appimage_path|$desktop_path|$icon_path|$(date '+%Y-%m-%d %H:%M')" >> "$REGISTRY"
}

registry_remove_entry() {
    local name="$1"
    [[ -f "$REGISTRY" ]] || return 0
    local tmp
    tmp=$(mktemp)
    grep -v "^${name}|" "$REGISTRY" > "$tmp" || true
    mv "$tmp" "$REGISTRY"
}

registry_list() {
    [[ -f "$REGISTRY" ]] && cat "$REGISTRY" || true
}

registry_get() {
    local name="$1" field="$2"
    local line
    line=$(grep "^${name}|" "$REGISTRY" 2>/dev/null | head -1)
    [[ -z "$line" ]] && return 1
    echo "$line" | cut -d'|' -f"$field"
}

# ── Icon extraction ───────────────────────────────────────────────────────────

extract_icon() {
    local appimage="$1" name="$2"
    local icon_dest="$ICONS_DIR/${name}.png"
    local tmp_dir

    tmp_dir=$(mktemp -d)
    trap 'rm -rf "$tmp_dir"' RETURN

    # Try to mount the AppImage and grab the icon
    if "$appimage" --appimage-extract '*.png' &>/dev/null 2>&1; then
        local extracted
        extracted=$(find squashfs-root -name '*.png' 2>/dev/null | head -1)
        [[ -n "$extracted" ]] && cp "$extracted" "$icon_dest" && rm -rf squashfs-root
    fi

    # Fallback: extract to tmp and search
    if [[ ! -f "$icon_dest" ]]; then
        (cd "$tmp_dir" && "$appimage" --appimage-extract '*.png' &>/dev/null 2>&1 || true
         "$appimage" --appimage-extract '*.svg' &>/dev/null 2>&1 || true)
        local found
        found=$(find "$tmp_dir" -name '*.png' -o -name '*.svg' 2>/dev/null | head -1)
        if [[ -n "$found" ]]; then
            cp "$found" "$icon_dest"
        fi
    fi

    # Final fallback: use a generic app icon name
    if [[ ! -f "$icon_dest" ]]; then
        echo "application-x-executable"
        return
    fi

    echo "$icon_dest"
}

# ── .desktop entry ────────────────────────────────────────────────────────────

create_desktop_entry() {
    local name="$1" version="$2" exec_path="$3" icon="$4" categories="$5" comment="$6"
    local safe_name
    safe_name=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-')
    local desktop_file="$DESKTOP_DIR/${safe_name}.desktop"

    cat > "$desktop_file" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$name
Comment=${comment:-Installed via AppImage Installer}
Exec=$exec_path
Icon=$icon
Categories=${categories:-Utility;}
Terminal=false
StartupNotify=true
X-AppImage-Version=$version
X-AppImage-Installer=appimage-installer/$SCRIPT_VERSION
EOF

    chmod 644 "$desktop_file"

    # Refresh desktop database if available
    command -v update-desktop-database &>/dev/null && \
        update-desktop-database "$DESKTOP_DIR" &>/dev/null || true

    echo "$desktop_file"
}

# ── Install flow ──────────────────────────────────────────────────────────────

do_install() {
    registry_init

    # Step 1: Pick file
    local appimage_src
    appimage_src=$(gui_file_picker "Select AppImage to Install") || {
        gui_error "Cancelled" "No file selected."
        return 1
    }
    [[ -z "$appimage_src" ]] && { gui_error "Cancelled" "No file selected."; return 1; }

    # Validate it's an AppImage
    if [[ ! -f "$appimage_src" ]]; then
        gui_error "File Not Found" "The selected file does not exist:\n$appimage_src"
        return 1
    fi
    if ! file "$appimage_src" | grep -qi "elf\|appimage\|iso 9660"; then
        gui_question "Warning" "This file may not be a valid AppImage:\n$appimage_src\n\nInstall anyway?" || return 1
    fi

    # Step 2: App name
    local default_name
    default_name=$(basename "$appimage_src" .AppImage)
    default_name=$(basename "$default_name" .appimage)
    # Remove version suffixes like -1.2.3 or _1.2.3
    default_name=$(echo "$default_name" | sed 's/[-_][0-9].*//')

    local app_name
    app_name=$(gui_entry "App Details" "Application name:" "$default_name") || return 1
    [[ -z "$app_name" ]] && { gui_error "Error" "App name cannot be empty."; return 1; }

    # Step 3: Version
    local app_version
    local detected_ver
    detected_ver=$(basename "$appimage_src" | grep -oP '[0-9]+\.[0-9]+[^\s.]*' | head -1 || echo "1.0")
    app_version=$(gui_entry "App Details" "Version:" "${detected_ver:-1.0}") || return 1
    app_version="${app_version:-1.0}"

    # Step 4: Categories
    local categories
    categories=$(gui_entry "App Details" "Desktop categories (e.g. Utility;Graphics;):" "Utility;") || return 1
    categories="${categories:-Utility;}"

    # Step 5: Comment
    local comment
    comment=$(gui_entry "App Details" "Short description (optional):" "") || true

    # Check if already installed
    if grep -q "^${app_name}|" "$REGISTRY" 2>/dev/null; then
        gui_question "Already Installed" \
            "'$app_name' is already installed.\nDo you want to reinstall / update it?" || return 1
    fi

    # Confirm
    gui_question "Confirm Installation" \
        "Ready to install:\n\n  Name:    $app_name\n  Version: $app_version\n  Source:  $(basename "$appimage_src")\n  Target:  $INSTALL_DIR/$app_name.AppImage\n\nProceed?" || return 1

    # ── Do the actual work ──
    local safe_name
    safe_name=$(echo "$app_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-')
    local dest="$INSTALL_DIR/${app_name}.AppImage"

    (
        echo "# Copying AppImage…"
        cp "$appimage_src" "$dest"
        chmod +x "$dest"

        echo "# Extracting icon…"
        local icon
        icon=$(extract_icon "$dest" "$safe_name")

        echo "# Creating desktop entry…"
        local desktop_file
        desktop_file=$(create_desktop_entry "$app_name" "$app_version" "$dest" "$icon" "$categories" "$comment")

        echo "# Registering…"
        registry_add "$app_name" "$app_version" "$dest" "$desktop_file" "$icon"

        echo "# Done"
    ) | gui_progress "Installing $app_name…"

    gui_info "Installation Complete" \
        "✓ '$app_name' has been installed successfully!\n\n  Location: $dest\n  Launcher: $DESKTOP_DIR/${safe_name}.desktop\n\nYou can now launch it from your application menu."
}

# ── Uninstall flow ────────────────────────────────────────────────────────────

do_uninstall() {
    registry_init

    local entries
    entries=$(registry_list)

    if [[ -z "$entries" ]]; then
        gui_info "Nothing to Uninstall" "No AppImages managed by this installer were found."
        return 0
    fi

    # Build list args
    local list_args=()
    while IFS='|' read -r name version appimage desktop icon installed; do
        list_args+=("$name" "$version" "$installed")
    done <<< "$entries"

    local selected
    selected=$(gui_list "Select AppImage to Uninstall" "${list_args[@]}") || return 1
    [[ -z "$selected" ]] && return 0

    # Clean up zenity's column separator
    selected=$(echo "$selected" | cut -d'|' -f1)

    local appimage_path desktop_path icon_path
    appimage_path=$(registry_get "$selected" 3) || true
    desktop_path=$(registry_get "$selected" 4)  || true
    icon_path=$(registry_get "$selected" 5)      || true

    gui_question "Confirm Uninstall" \
        "Remove '$selected'?\n\nThis will delete:\n  • $appimage_path\n  • $desktop_path" || return 1

    (
        echo "# Removing AppImage…"
        [[ -n "$appimage_path" && -f "$appimage_path" ]] && rm -f "$appimage_path"

        echo "# Removing desktop entry…"
        [[ -n "$desktop_path" && -f "$desktop_path" ]] && rm -f "$desktop_path"

        echo "# Removing icon…"
        [[ -n "$icon_path" && -f "$icon_path" && "$icon_path" == "$ICONS_DIR"* ]] && rm -f "$icon_path"

        echo "# Updating registry…"
        registry_remove_entry "$selected"

        command -v update-desktop-database &>/dev/null && \
            update-desktop-database "$DESKTOP_DIR" &>/dev/null || true

        echo "# Done"
    ) | gui_progress "Uninstalling $selected…"

    gui_info "Uninstall Complete" "✓ '$selected' has been removed successfully."
}

# ── List installed ────────────────────────────────────────────────────────────

do_list() {
    registry_init
    local entries
    entries=$(registry_list)

    if [[ -z "$entries" ]]; then
        gui_info "Installed AppImages" "No AppImages have been installed yet."
        return 0
    fi

    local list_args=()
    while IFS='|' read -r name version appimage desktop icon installed; do
        list_args+=("$name" "$version" "$installed")
    done <<< "$entries"

    gui_list "Installed AppImages" "${list_args[@]}" || true
}

# ── Self-install ──────────────────────────────────────────────────────────────

do_self_install() {
    local bin_dir="$HOME/.local/bin"
    mkdir -p "$bin_dir"
    local target="$bin_dir/$SCRIPT_NAME"

    cp "$(realpath "$0")" "$target"
    chmod +x "$target"

    # Add to PATH hint if needed
    local added_path=""
    if ! echo "$PATH" | grep -q "$bin_dir"; then
        added_path="\n\nNote: Add ~/.local/bin to your PATH if not already set:\n  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc"
    fi

    # Create a .desktop entry for the installer itself
    local installer_desktop="$DESKTOP_DIR/appimage-installer.desktop"
    cat > "$installer_desktop" <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=AppImage Installer
Comment=Install and manage AppImages graphically
Exec=appimage-installer
Icon=system-software-install
Categories=System;PackageManager;
Terminal=false
StartupNotify=true
EOF
    chmod 644 "$installer_desktop"
    command -v update-desktop-database &>/dev/null && update-desktop-database "$DESKTOP_DIR" &>/dev/null || true

    gui_info "Installer Installed" \
        "AppImage Installer has been installed to:\n  $target\n\nA launcher has been added to your application menu.$added_path"
}

# ── Dependency check ──────────────────────────────────────────────────────────

check_deps() {
    local missing=()
    for cmd in file cp chmod mkdir; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done

    if [[ "$GUI" == "none" ]]; then
        missing+=("zenity (or kdialog/yad)")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${RED}Missing dependencies:${NC} ${missing[*]}"
        echo "Install with: sudo apt install zenity  (or kdialog for KDE, yad for more features)"
        exit 1
    fi
}

# ── Main menu ─────────────────────────────────────────────────────────────────

main_menu() {
    while true; do
        local choice
        case "$GUI" in
            zenity)
                choice=$(zenity --list \
                    --title="AppImage Installer v$SCRIPT_VERSION" \
                    --text="What would you like to do?" \
                    --column="Action" --column="Description" \
                    --width=500 --height=340 \
                    --hide-header \
                    "install"   "Install a new AppImage" \
                    "uninstall" "Remove an installed AppImage" \
                    "list"      "View installed AppImages" \
                    "self"      "Install this tool to your system" \
                    "quit"      "Exit" 2>/dev/null) || return 0
                ;;
            yad)
                choice=$(yad --title="AppImage Installer v$SCRIPT_VERSION" \
                    --text="What would you like to do?" \
                    --list --column="Action" --column="Description" \
                    --width=500 --height=340 \
                    "install"   "Install a new AppImage" \
                    "uninstall" "Remove an installed AppImage" \
                    "list"      "View installed AppImages" \
                    "self"      "Install this tool to your system" \
                    "quit"      "Exit" 2>/dev/null) || return 0
                choice=$(echo "$choice" | cut -d'|' -f1)
                ;;
            kdialog)
                choice=$(kdialog --menu "AppImage Installer" \
                    "install"   "Install a new AppImage" \
                    "uninstall" "Remove an installed AppImage" \
                    "list"      "View installed AppImages" \
                    "self"      "Install this tool to your system" \
                    "quit"      "Exit" 2>/dev/null) || return 0
                ;;
            *)
                echo ""
                echo -e "${CYAN}AppImage Installer v$SCRIPT_VERSION${NC}"
                echo "────────────────────────────────"
                echo "  1) Install an AppImage"
                echo "  2) Uninstall an AppImage"
                echo "  3) List installed AppImages"
                echo "  4) Install this tool to system"
                echo "  5) Quit"
                echo ""
                read -r -p "Choice [1-5]: " choice
                case "$choice" in
                    1) choice="install" ;;
                    2) choice="uninstall" ;;
                    3) choice="list" ;;
                    4) choice="self" ;;
                    5) return 0 ;;
                esac
                ;;
        esac

        case "$choice" in
            install)   do_install   ;;
            uninstall) do_uninstall ;;
            list)      do_list      ;;
            self)      do_self_install ;;
            quit|"")   return 0 ;;
        esac
    done
}

# ── CLI argument handling ─────────────────────────────────────────────────────

usage() {
    cat <<EOF
AppImage Installer v$SCRIPT_VERSION — Graphical AppImage manager

Usage: $(basename "$0") [COMMAND]

Commands:
  install      Open file picker and install an AppImage
  uninstall    Show installed list and uninstall one
  list         List all installed AppImages
  self-install Install this script to ~/.local/bin
  help         Show this help

Without arguments, opens the main menu GUI.

Install GUI dependencies:
  Ubuntu/Debian:  sudo apt install zenity
  Fedora:         sudo dnf install zenity
  KDE systems:    sudo apt install kdialog
  Advanced GUI:   sudo apt install yad

EOF
}

# ── Entry point ───────────────────────────────────────────────────────────────

check_deps

case "${1:-menu}" in
    install)      registry_init; do_install ;;
    uninstall)    registry_init; do_uninstall ;;
    list)         registry_init; do_list ;;
    self-install) do_self_install ;;
    menu|"")      main_menu ;;
    help|--help|-h) usage ;;
    *)
        echo "Unknown command: $1"
        usage
        exit 1
        ;;
esac
