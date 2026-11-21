import QtQuick 6.10
import Quickshell
import Quickshell.Widgets
import "../../config" as QsConfig
import "../../services" as QsServices
import "../../components"
import "../../components/effects"

Item {
    id: root

    property var itemData: null
    property var dock: null

    readonly property var config: QsConfig.Config
    readonly property var pywal: QsServices.Pywal.dock
    readonly property var hypr: QsServices.Hypr

    readonly property var liveItemData: {
        const _rev = root.dock ? root.dock.dockStateRevision : 0
        if (root.dock && root.itemIndex >= 0) {
            const list = root.isPinnedSection ? root.dock.pinnedModel : root.dock.runningModel
            if (list && root.itemIndex < list.length && list[root.itemIndex]) {
                return list[root.itemIndex]
            }
        }
        return itemData
    }

    readonly property var windows: {
        // Explicit revision dependency: liveItemData keeps the same object reference on in-place updates
        const _rev = root.dock ? root.dock.dockStateRevision : 0
        return (liveItemData && liveItemData.windows) ? liveItemData.windows : []
    }
    readonly property int windowCount: windows.length
    readonly property bool isRunning: windowCount > 0
    function normalizeAddr(addr): string {
        if (!addr) return ""
        let s = String(addr).toLowerCase().trim()
        if (s.startsWith("0x")) s = s.slice(2)
        return s
    }

    readonly property bool isActive: {
        if (!isRunning) return false
        const activeTl = hypr.activeToplevel
        const activeAddr = (activeTl && activeTl.address) ? activeTl.address : ""
        return windows.some(w => w.activated || (activeAddr.length > 0 && normalizeAddr(w.address) === normalizeAddr(activeAddr)))
    }

    readonly property string appName: (liveItemData && liveItemData.name) ? liveItemData.name : ((liveItemData && liveItemData.id) ? liveItemData.id : "App")
    readonly property string iconSource: resolveIcon()

    property int itemIndex: -1
    property bool isPinnedSection: false
    readonly property bool isBeingDragged: Boolean(root.dock && root.dock.isDraggingActive && root.dock.draggedItem === root)
    property real dragTranslationX: 0
    property real dragTranslationY: 0

    readonly property real slideOffsetX: {
        if (!root.dock || !root.dock.isDraggingActive || root.isBeingDragged) return 0
        if (!root.isPinnedSection) return 0

        const pitch = root.dock.getSlotPitch()
        const src = root.dock.dragSourceIndex
        const tgt = root.dock.dragTargetIndex

        if (root.dock.dragSourceIsPinned) {
            if (src < tgt) {
                if (root.itemIndex > src && root.itemIndex <= tgt) return -pitch
            } else if (src > tgt) {
                if (root.itemIndex >= tgt && root.itemIndex < src) return pitch
            }
        } else {
            if (tgt >= 0 && root.itemIndex >= tgt) return pitch
        }
        return 0
    }

    z: root.isBeingDragged ? 999 : (root.isHovered ? 10 : 1)

    transform: Translate {
        id: itemTranslate
        x: root.isBeingDragged ? root.dragTranslationX : root.slideOffsetX
        y: root.isBeingDragged ? root.dragTranslationY : 0

        Behavior on x {
            enabled: QsServices.UIState.animationsEnabled && !root.isBeingDragged && !(root.dock && root.dock.isDropCommitting)
            NumberAnimation {
                duration: 350
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Material3Anim.expressiveFastSpatial
            }
        }
        Behavior on y {
            enabled: QsServices.UIState.animationsEnabled && !root.isBeingDragged && !(root.dock && root.dock.isDropCommitting)
            NumberAnimation {
                duration: 350
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Material3Anim.expressiveFastSpatial
            }
        }
    }

    function resolveIcon() {
        return QsServices.IconResolver.resolveAppIcon(liveItemData)
    }

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
        color: root.isBeingDragged
            ? Qt.rgba(pywal.primary.r, pywal.primary.g, pywal.primary.b, 0.22)
            : (root.isHovered
                ? Qt.rgba(pywal.foreground.r, pywal.foreground.g, pywal.foreground.b, 0.12)
                : (root.isActive ? Qt.rgba(pywal.primary.r, pywal.primary.g, pywal.primary.b, 0.10) : "transparent"))
        opacity: (root.isBeingDragged || root.isHovered || root.isActive) ? 1.0 : 0.0
        border.color: root.isBeingDragged ? pywal.primary : "transparent"
        border.width: root.isBeingDragged ? 1 : 0

        Behavior on opacity {
            enabled: QsServices.UIState.animationsEnabled
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
        Behavior on color {
            enabled: QsServices.UIState.animationsEnabled
            ColorAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
    }

    // Icon container with smooth scale micro-interaction
    Item {
        id: iconContainer
        anchors.centerIn: parent
        anchors.verticalCenterOffset: root.isRunning ? -2 : 0
        width: config.dock.iconSize
        height: config.dock.iconSize

        scale: root.isBeingDragged ? 1.20 : (root.isPressed ? 0.92 : (root.isHovered ? 1.15 : 1.0))
        transformOrigin: Item.Bottom

        Behavior on scale {
            enabled: QsServices.UIState.animationsEnabled
            NumberAnimation {
                duration: root.isPressed ? 150 : 350
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.isPressed ? Material3Anim.expressiveFastEffects : Material3Anim.expressiveFastSpatial
            }
        }

        // App Icon
        IconImage {
            id: appIcon
            anchors.fill: parent
            source: root.iconSource
            asynchronous: false
            mipmap: true
            visible: root.iconSource.length > 0 && status === Image.Ready
        }

        // Fallback letter badge if icon image is unavailable
        Rectangle {
            anchors.fill: parent
            radius: 8
            color: Qt.rgba(pywal.primary.r, pywal.primary.g, pywal.primary.b, 0.18)
            visible: !appIcon.visible

            Text {
                anchors.centerIn: parent
                text: root.appName.length > 0 ? root.appName.slice(0, 1).toUpperCase() : "󰣆"
                font.family: root.appName.length > 0 ? config.appearance.fontFamily : "Material Design Icons"
                font.pixelSize: Math.round(config.dock.iconSize * 0.5)
                font.weight: Font.Bold
                color: pywal.primary
            }
        }
    }

    // Running indicator dot / pill
    Rectangle {
        id: runningIndicator
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 3
        anchors.horizontalCenter: parent.horizontalCenter

        visible: root.isRunning
        height: 3.5
        radius: 1.75

        width: {
            if (root.isActive) return 16
            if (root.windowCount > 1) return 8
            return 4.5
        }

        color: root.isActive
            ? pywal.primary
            : Qt.rgba(pywal.foreground.r, pywal.foreground.g, pywal.foreground.b, 0.45)

        Behavior on width {
            enabled: QsServices.UIState.animationsEnabled
            NumberAnimation {
                duration: 350
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Material3Anim.expressiveFastSpatial
            }
        }
        Behavior on color {
            enabled: QsServices.UIState.animationsEnabled
            ColorAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
    }

    // Mouse interaction handling
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.isBeingDragged ? Qt.ClosedHandCursor : Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

        property real pressMouseX: 0
        property real pressMouseY: 0
        property real pressDockX: 0
        property real pressDockY: 0
        property bool dragStarted: false

        onPressed: mouse => {
            if (mouse.button === Qt.LeftButton) {
                pressMouseX = mouse.x
                pressMouseY = mouse.y
                const pt = root.dock ? mouseArea.mapToItem(root.dock, mouse.x, mouse.y) : Qt.point(mouse.x, mouse.y)
                pressDockX = pt.x
                pressDockY = pt.y
                dragStarted = false
            } else if (dragStarted) {
                dragStarted = false
                if (root.dock) {
                    root.dock.cancelItemDrag(root)
                }
            }
        }

        onPositionChanged: mouse => {
            if (!(mouse.buttons & Qt.LeftButton)) return

            const dx = mouse.x - pressMouseX
            const dy = mouse.y - pressMouseY

            if (!dragStarted) {
                if (Math.hypot(dx, dy) >= 6) {
                    dragStarted = true
                    root.dragTranslationX = 0
                    root.dragTranslationY = 0
                    if (root.dock) {
                        root.dock.startItemDrag(root, root.liveItemData, root.itemIndex, root.isPinnedSection)
                    }
                }
            }

            if (dragStarted && root.isBeingDragged && root.dock) {
                const pt = mouseArea.mapToItem(root.dock, mouse.x, mouse.y)
                root.dragTranslationX = pt.x - pressDockX
                root.dragTranslationY = Math.max(-30, Math.min(30, pt.y - pressDockY))
                root.dock.updateItemDrag(root)
            }
        }

        onReleased: mouse => {
            if (dragStarted) {
                dragStarted = false
                if (root.dock) {
                    root.dock.finishItemDrag(root)
                }
                return
            }

            if (mouse.button === Qt.LeftButton) {
                if (root.dock && root.dock.isMenuOpen) {
                    root.dock.closeContextMenu()
                }
                root.handleActivate()
            } else if (mouse.button === Qt.MiddleButton) {
                if (root.dock && root.dock.isMenuOpen) {
                    root.dock.closeContextMenu()
                }
                root.handleCloseWindow()
            } else if (mouse.button === Qt.RightButton) {
                if (root.dock) {
                    root.dock.openContextMenu(root, root.liveItemData, "app")
                }
            }
        }

        onCanceled: {
            if (dragStarted) {
                dragStarted = false
                if (root.dock) {
                    root.dock.cancelItemDrag(root)
                }
            }
        }
    }

    function handleActivate() {
        if (root.isRunning && root.windows.length > 0) {
            const activeAddr = (hypr.activeToplevel && hypr.activeToplevel.address) ? hypr.activeToplevel.address : ""
            const activeIdx = root.windows.findIndex(w => w.activated || (activeAddr.length > 0 && root.normalizeAddr(w.address) === root.normalizeAddr(activeAddr)))
            
            if (activeIdx !== -1 && root.windows.length > 1) {
                // Cycle to the next window of this app
                const nextIdx = (activeIdx + 1) % root.windows.length
                hypr.focusWindow(root.windows[nextIdx].address)
            } else {
                // Focus the most recent or first window
                hypr.focusWindow(root.windows[0].address)
            }
        } else {
            launchNewInstance()
        }
    }

    function launchNewInstance() {
        if (root.dock) {
            root.dock.launchApp(liveItemData)
        }
    }

    function handleCloseWindow() {
        if (root.isRunning && root.windows.length > 0) {
            const activeAddr = (hypr.activeToplevel && hypr.activeToplevel.address) ? hypr.activeToplevel.address : ""
            const target = root.windows.find(w => w.activated || (activeAddr.length > 0 && root.normalizeAddr(w.address) === root.normalizeAddr(activeAddr))) ?? root.windows[0]
            hypr.closeWindow(target.address)
        }
    }

    StyledToolTip {
        visible: root.isHovered && !root.isBeingDragged && !(root.dock && root.dock.isDraggingActive) && !(root.dock && root.dock.isMenuOpen)
        placement: "top"
        offset: 10
        text: {
            if (root.isRunning && root.windows.length > 0) {
                const activeAddr = (hypr.activeToplevel && hypr.activeToplevel.address) ? hypr.activeToplevel.address : ""
                const activeWin = root.windows.find(w => w.activated || (activeAddr.length > 0 && root.normalizeAddr(w.address) === root.normalizeAddr(activeAddr))) ?? root.windows[0]
                const title = (activeWin && activeWin.title) ? activeWin.title : ""
                if (title.length > 0 && title !== root.appName) {
                    return `${root.appName} — ${title.length > 42 ? title.slice(0, 39) + "..." : title}`
                }
            }
            return root.appName
        }
    }
}
