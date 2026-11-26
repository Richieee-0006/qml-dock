pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import "../services" as QsServices

Singleton {
    id: root

    readonly property string configPath: {
        const home = Quickshell.env("HOME")
        const xdg = Quickshell.env("XDG_CONFIG_HOME")
        const cfgHome = (xdg && xdg.length > 0) ? xdg : `${home}/.config`
        return `${cfgHome}/qml-dock/config.json`
    }

    Component.onCompleted: file.reload()

    property var data: ({})

    function _expandHome(p) {
        if (!p || typeof p !== "string") return p
        if (p.startsWith("~/")) return `${Quickshell.env("HOME")}/${p.slice(2)}`
        return p
    }

    readonly property var appearance: ({
        fontFamily: data.appearance?.fontFamily ?? "Inter",
        materialIconFont: data.appearance?.materialIconFont ?? "Material Design Icons"
    })

    readonly property var paths: ({
        pywalColors: _expandHome(data.paths?.pywalColors ?? "~/.cache/wal/colors.json"),
        pywalBarColors: _expandHome(data.paths?.pywalBarColors ?? "~/.cache/wal/colors-bar.json"),
        pywalDockColors: _expandHome(data.paths?.pywalDockColors ?? "~/.cache/wal/colors-dock.json")
    })

    readonly property DockConfig dock: DockConfig {
        enabled: root.data.dock?.enabled ?? true
        iconSize: root.data.dock?.iconSize ?? 32
        height: root.data.dock?.height ?? 52
        borderRadius: root.data.dock?.borderRadius ?? 24
        marginBottom: root.data.dock?.marginBottom ?? 12
        spacing: root.data.dock?.spacing ?? 4
        itemPadding: root.data.dock?.itemPadding ?? 6
        exclusive: root.data.dock?.exclusive ?? true
        launcherCommand: root.data.dock?.launcherCommand ?? "$HOME/.local/bin/spot-launch-apps"
        launcherIcon: root.data.dock?.launcherIcon ?? "󰀻"
        pinned: root.data.dock?.pinned ?? [
            "librewolf",
            "org.kde.dolphin",
            "kitty",
            "obsidian",
            "equibop"
        ]
        showRunning: root.data.dock?.showRunning ?? true
        onlyCurrentWorkspace: root.data.dock?.onlyCurrentWorkspace ?? false
    }

    readonly property AppearanceConfig appearanceTokens: AppearanceConfig {}

    FileView {
        id: file
        path: root.configPath
        watchChanges: true

        onLoaded: {
            try {
                const parsed = JSON.parse(text())
                root.data = parsed
                root.dock.pinned = Qt.binding(() => root.data.dock?.pinned ?? [
                    "librewolf",
                    "org.kde.dolphin",
                    "kitty",
                    "obsidian",
                    "equibop"
                ])
                QsServices.Logger.debug("Config", "config.json loaded")
            } catch (e) {
                QsServices.Logger.warn("Config", `Failed to parse config.json: ${e?.message ?? e}`)
            }
        }

        onFileChanged: file.reload()

        onLoadFailed: err => {
            if (err !== FileViewError.FileNotFound)
                QsServices.Logger.warn("Config", `Failed to read config.json: ${FileViewError.toString(err)}`)
        }
    }
}
