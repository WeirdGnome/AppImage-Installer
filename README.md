# AppImage Installer

A graphical, Windows-installer-style tool for managing AppImages on Linux.  
Installs apps to `~/Programs`, exports `.desktop` entries to your app menu, and tracks everything for clean uninstalls.

---

## Features

- **Graphical install wizard** — file picker → name/version → confirm → done
- **Clean uninstall** — removes the AppImage, desktop entry, and icon in one click
- **Desktop integration** — creates `.desktop` entries so apps appear in your launcher (GNOME, KDE, XFCE, etc.)
- **Icon extraction** — automatically pulls the icon out of the AppImage when possible
- **Registry** — tracks all managed apps in `~/.local/share/appimage-installer/registry.db`
- **Multi-GUI support** — works with `zenity` (GNOME), `kdialog` (KDE), `yad` (advanced), or plain terminal
- **Self-installs** — can install itself to `~/.local/bin` and add itself to your app menu

---

## Quick Start

### 1. Install a GUI dialog tool (one-time)

```bash
# GNOME / Ubuntu / Debian
sudo apt install zenity

# KDE / Kubuntu
sudo apt install kdialog

# Advanced (more features)
sudo apt install yad

# Fedora
sudo dnf install zenity
```

### 2. Make the installer executable

```bash
chmod +x appimage-installer.sh
```

### 3. Run it

```bash
./appimage-installer.sh
```

A graphical menu appears with options to Install, Uninstall, List, or self-install the tool.

---

## Self-Install (Optional)

To use `appimage-installer` as a system command and get an app-menu entry:

```bash
./appimage-installer.sh self-install
```

This copies the script to `~/.local/bin/appimage-installer` and creates a `.desktop` launcher.

After that, just run:

```bash
appimage-installer
```

---

## CLI Commands

```
appimage-installer              # Opens main menu GUI
appimage-installer install      # Directly open install wizard
appimage-installer uninstall    # Directly open uninstall dialog
appimage-installer list         # Show all installed AppImages
appimage-installer self-install # Install this tool to ~/.local/bin
appimage-installer help         # Show help
```

---

## What Gets Created

| Item | Location |
|------|----------|
| AppImage binary | `~/Programs/<AppName>.AppImage` |
| Desktop entry | `~/.local/share/applications/<appname>.desktop` |
| Extracted icon | `~/.local/share/icons/appimage-installer/<appname>.png` |
| Registry | `~/.local/share/appimage-installer/registry.db` |
| Installer itself | `~/.local/bin/appimage-installer` (after self-install) |

---

## Install Flow

```
Select .AppImage file
        │
        ▼
Enter name, version, categories, description
        │
        ▼
Confirm dialog
        │
        ▼
Copy to ~/Programs/<Name>.AppImage
Extract icon from AppImage
Write ~/.local/share/applications/<name>.desktop
Register in local database
        │
        ▼
✓ App appears in your launcher
```

---

## Requirements

- Bash 4+
- `file`, `cp`, `chmod` (standard on all Linux systems)
- One of: `zenity`, `kdialog`, or `yad` (for the GUI)
- AppImages must be standard Type 1 or Type 2 AppImages

---

## Troubleshooting

**App doesn't appear in launcher after install**  
Run `update-desktop-database ~/.local/share/applications/` or log out and back in.

**Icon not showing**  
The installer tries to extract icons automatically. If it fails, it falls back to a generic system icon. You can manually set `Icon=` in the `.desktop` file.

**"Missing dependencies" error**  
Install `zenity`: `sudo apt install zenity`

**PATH not including ~/.local/bin**  
Add to your shell config:
```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

---

## License

MIT — free to use, modify, and distribute.
