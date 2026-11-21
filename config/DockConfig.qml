import QtQuick 6.10

QtObject {
    // Dock visibility
    property bool enabled: true

    // Sizing and layout (matching nwg-dock settings: -i 32 -mb 12 -x)
    property int iconSize: 32
    property int height: 52
    property int borderRadius: 24
    property int marginBottom: 12
    property int spacing: 4
    property int itemPadding: 6

    // Exclusive zone reserves space at screen bottom so tiled windows don't overlap
    property bool exclusive: true

    // Launcher command (-c 'vicinae toggle')
    property string launcherCommand: "vicinae toggle"
    property string launcherIcon: "󰀻"

    // Default pinned applications
    property var pinned: [
        "librewolf",
        "org.kde.dolphin",
        "kitty",
        "obsidian",
        "equibop"
    ]

    // Behavior
    property bool showRunning: true
    property bool onlyCurrentWorkspace: false
    property int animationDuration: 220
}
