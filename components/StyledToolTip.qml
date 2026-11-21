// StyledToolTip.qml - Modern Material 3 Expressive Hover Tooltip
// Styled with Pywal palette, rounded corners, soft shadow, and bouncy micro-animations

import QtQuick 6.10
import QtQuick.Controls 6.10 as QQC
import QtQuick.Layouts 6.10
import QtQuick.Effects
import "effects"
import "../services" as QsServices
import "../config" as QsConfig

QQC.ToolTip {
    id: control

    readonly property var pywal: QsServices.Pywal
    readonly property var config: QsConfig.Config

    // Public customizable properties
    property string icon: ""
    property color accentColor: pywal ? pywal.primary : "#89b4fa"
    property color surfaceColor: pywal ? Qt.rgba(pywal.surfaceContainerHighest.r, pywal.surfaceContainerHighest.g, pywal.surfaceContainerHighest.b, 0.96) : "#1e1e2e"
    property color textColor: pywal ? pywal.foreground : "#ffffff"
    property color borderColor: Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.28)
    property string placement: "bottom" // "bottom", "top", "left", "right"
    property real offset: 8

    delay: 350
    timeout: 5000

    padding: 0
    topPadding: 6
    bottomPadding: 6
    leftPadding: 12
    rightPadding: 12

    focus: false
    closePolicy: QQC.Popup.NoAutoClose

    // Smart horizontal positioning with window boundary clamping
    x: {
        const _vis = control.visible
        if (!parent) return 0
        const _px = parent.x
        const _py = parent.y
        if (placement === "left") return -implicitWidth - offset
        if (placement === "right") return parent.width + offset

        let centered = Math.round((parent.width - implicitWidth) / 2)
        try {
            if (parent.Window && parent.Window.window) {
                const winWidth = parent.Window.window.width
                const parentWinX = parent.mapToItem(null, 0, 0).x
                const tipWinRight = parentWinX + centered + implicitWidth
                const margin = 10
                if (tipWinRight > winWidth - margin) {
                    centered -= Math.round(tipWinRight - (winWidth - margin))
                }
                const tipWinLeft = parentWinX + centered
                if (tipWinLeft < margin) {
                    centered += Math.round(margin - tipWinLeft)
                }
            }
        } catch (e) {}
        return centered
    }

    // Smart vertical positioning with auto-flip on window overflow
    y: {
        const _vis = control.visible
        if (!parent) return 0
        const _px = parent.x
        const _py = parent.y
        if (placement === "left" || placement === "right") {
            return Math.round((parent.height - implicitHeight) / 2)
        }

        let targetY = (placement === "top") ? (-implicitHeight - offset) : (parent.height + offset)
        try {
            if (parent.Window && parent.Window.window) {
                const winHeight = parent.Window.window.height
                const parentWinY = parent.mapToItem(null, 0, 0).y
                const margin = 8
                if (targetY > 0 && (parentWinY + targetY + implicitHeight > winHeight - margin)) {
                    if (parentWinY - implicitHeight - offset >= margin) {
                        targetY = -implicitHeight - offset
                    }
                } else if (targetY < 0 && (parentWinY + targetY < margin)) {
                    if (parentWinY + parent.height + offset + implicitHeight <= winHeight - margin) {
                        targetY = parent.height + offset
                    }
                }
            }
        } catch (e) {}
        return targetY
    }

    contentItem: RowLayout {
        enabled: false
        spacing: 6

        Text {
            visible: control.icon !== ""
            text: control.icon
            font.family: "Material Design Icons"
            font.pixelSize: 13
            color: control.accentColor
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            text: control.text
            font.family: (control.config && control.config.appearance) ? control.config.appearance.fontFamily : "Inter"
            font.pixelSize: 11
            font.weight: Font.Medium
            color: control.textColor
            Layout.alignment: Qt.AlignVCenter
        }
    }

    background: Rectangle {
        enabled: false
        implicitHeight: 28
        implicitWidth: contentItem.implicitWidth + 24
        radius: 10
        color: control.surfaceColor
        border.width: 1
        border.color: control.borderColor

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.45)
            shadowBlur: 0.35
            shadowVerticalOffset: 2
        }
    }

    enter: Transition {
        ParallelAnimation {
            NumberAnimation {
                property: "opacity"
                from: 0.0
                to: 1.0
                duration: Material3Anim.short3
                easing.bezierCurve: Material3Anim.standardDecelerate
            }
            NumberAnimation {
                property: "scale"
                from: 0.88
                to: 1.0
                duration: Material3Anim.short4
                easing.bezierCurve: Material3Anim.emphasizedDecelerate
            }
        }
    }

    exit: Transition {
        ParallelAnimation {
            NumberAnimation {
                property: "opacity"
                from: 1.0
                to: 0.0
                duration: Material3Anim.short2
                easing.bezierCurve: Material3Anim.standardAccelerate
            }
            NumberAnimation {
                property: "scale"
                from: 1.0
                to: 0.94
                duration: Material3Anim.short2
                easing.bezierCurve: Material3Anim.standardAccelerate
            }
        }
    }
}
