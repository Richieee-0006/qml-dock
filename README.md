# qml-dock

Standalone Hyprland dock built with Quickshell and Qt Quick 6.10.

## Features

- Pinned and running window tracking via Hyprland IPC
- Drag-and-drop reordering for pinned apps (persisted to `config.json`)
- Context menu with window list, desktop actions, pin/unpin, and power controls
- Pywal color palette integration (`~/.cache/wal/colors.json`, `colors-dock.json`)
- Icon lookup across `DesktopEntries`, icon themes, `/usr/share/pixmaps`, Flatpak exports, and process inspection (`services/resolve-instance.py`)

## Run

```bash
quickshell -p ~/.config/qml-dock
```

## Configuration

Edit `~/.config/qml-dock/config.json`:

- `dock.pinned`: array of `.desktop` IDs or window classes
- `dock.iconSize`, `dock.height`, `dock.borderRadius`, `dock.marginBottom`, `dock.exclusive`
- `dock.launcherCommand`, `dock.launcherIcon`
- `paths.pywalColors`, `paths.pywalDockColors`
