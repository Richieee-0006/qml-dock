import QtQuick 6.10
import Quickshell
import Quickshell.Widgets
import "../../config" as QsConfig
import "../../services" as QsServices
import "../../components"
import "../../components/effects"

Item {
    id: root

    property var launcher: null
    property var dock: null

    readonly property var config: QsConfig.Config
    readonly property var pywal: QsServices.Pywal.dock

    readonly property bool isHovered: mouseArea.containsMouse
    readonly property bool isPressed: mouseArea.pressed

    implicitWidth: config.dock.iconSize + 16
    implicitHeight: config.dock.iconSize + 16

    // Hover background pill
    Rectangle {
        id: hoverBg
        anchors.fill: parent
        anchors.margins: 4
        radius: 14
        color: root.isHovered
            ? Qt.rgba(pywal.primary.r, pywal.primary.g, pywal.primary.b, 0.16)
            : "transparent"

        Behavior on color {
            enabled: QsServices.UIState.animationsEnabled
            ColorAnimation {
                duration: 200
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Material3Anim.expressiveDefaultEffects
            }
        }
    }

    // Launcher icon container (centered symmetrically)
    Item {
        id: iconContainer
        anchors.centerIn: parent
        width: config.dock.iconSize
        height: config.dock.iconSize

        scale: root.isPressed ? 0.90 : (root.isHovered ? 1.15 : 1.0)
        transformOrigin: Item.Center

        Behavior on scale {
            enabled: QsServices.UIState.animationsEnabled
            NumberAnimation {
                duration: root.isPressed ? 150 : 350
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.isPressed ? Material3Anim.expressiveFastEffects : Material3Anim.expressiveFastSpatial
            }
        }

        // Vicinae official logo
        IconImage {
            id: vicinaeLogo
            anchors.centerIn: parent
            width: config.dock.iconSize
            height: config.dock.iconSize
            source: QsServices.IconResolver.tryIconName("vicinae") || "file:///usr/share/icons/hicolor/512x512/apps/vicinae.png"
            asynchronous: false
            mipmap: true
            visible: status === Image.Ready
        }

        // Fallback icon if image is unavailable
        Text {
            anchors.centerIn: parent
            visible: !vicinaeLogo.visible
            text: config.dock.launcherIcon || "󰀻"
            font.family: "Material Design Icons"
            font.pixelSize: Math.round(config.dock.iconSize * 0.72)
            color: pywal.primary
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onClicked: mouse => {
            if (mouse.button === Qt.LeftButton) {
                if (root.dock && root.dock.isMenuOpen) {
                    root.dock.closeContextMenu()
                }
                // Execute configured launcher command (e.g. "vicinae toggle")
                const cmd = config.dock.launcherCommand || "vicinae toggle"
                Quickshell.execDetached(["sh", "-c", cmd])
            } else if (mouse.button === Qt.RightButton) {
                if (root.dock) {
                    root.dock.openContextMenu(root, { type: "launcher" }, "launcher")
                } else if (root.launcher && typeof root.launcher.openLauncher === "function") {
                    root.launcher.openLauncher()
                } else {
                    Quickshell.execDetached(["sh", "-c", config.dock.launcherCommand || "vicinae toggle"])
                }
            }
        }
    }

    StyledToolTip {
        visible: root.isHovered && !(root.dock && root.dock.isMenuOpen)
        placement: "top"
        offset: 10
        text: "Vicinae (Super + Space)"
    }
}
