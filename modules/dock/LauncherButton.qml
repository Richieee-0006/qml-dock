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

        // Spot geometric emblem (circular pill + spotlight ring + core dot)
        Rectangle {
            id: spotLogo
            anchors.centerIn: parent
            width: Math.round(config.dock.iconSize * 0.88)
            height: width
            radius: width / 2
            color: Qt.rgba(pywal.background.r, pywal.background.g, pywal.background.b, 0.92)
            border.width: 2
            border.color: root.isHovered ? pywal.foreground : pywal.primary
            antialiasing: true

            Behavior on border.color {
                enabled: QsServices.UIState.animationsEnabled
                ColorAnimation { duration: 150 }
            }

            Rectangle {
                anchors.centerIn: parent
                width: Math.round(parent.width * 0.56)
                height: width
                radius: width / 2
                color: Qt.rgba(pywal.primary.r, pywal.primary.g, pywal.primary.b, root.isHovered ? 0.34 : 0.2)
                antialiasing: true

                Behavior on color {
                    enabled: QsServices.UIState.animationsEnabled
                    ColorAnimation { duration: 150 }
                }
            }

            Rectangle {
                anchors.centerIn: parent
                width: Math.round(parent.width * 0.28)
                height: width
                radius: width / 2
                color: root.isHovered ? pywal.primary : pywal.foreground
                antialiasing: true

                Behavior on color {
                    enabled: QsServices.UIState.animationsEnabled
                    ColorAnimation { duration: 150 }
                }
            }
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
                const cmd = config.dock.launcherCommand || "$HOME/.local/bin/spot-launch-apps"
                Quickshell.execDetached(["sh", "-c", "export PATH=\"$HOME/.local/bin:$PATH\"; " + cmd])
            } else if (mouse.button === Qt.RightButton) {
                if (root.dock) {
                    root.dock.openContextMenu(root, { type: "launcher" }, "launcher")
                } else if (root.launcher && typeof root.launcher.openLauncher === "function") {
                    root.launcher.openLauncher()
                } else {
                    const cmd = config.dock.launcherCommand || "$HOME/.local/bin/spot-launch-apps"
                    Quickshell.execDetached(["sh", "-c", "export PATH=\"$HOME/.local/bin:$PATH\"; " + cmd])
                }
            }
        }
    }

    StyledToolTip {
        visible: root.isHovered && !(root.dock && root.dock.isMenuOpen)
        placement: "top"
        offset: 10
        text: "Spot (Super + Space)"
    }
}
