import QtQuick 6.10
import QtQuick.Layouts 6.10
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Io
import "../../config" as QsConfig
import "../../services" as QsServices
import "../../components"
import "../../components/effects"

PopupWindow {
    id: root

    property var dockWindow
    property var dock: null

    property var currentTarget: null
    property var currentItemData: null
    property string menuType: "app" // "app" or "launcher"
    property bool powerSubmenuExpanded: false

    readonly property var config: QsConfig.Config
    readonly property var pywal: QsServices.Pywal.dock
    readonly property var hypr: QsServices.Hypr

    readonly property var windows: (currentItemData && currentItemData.windows) ? currentItemData.windows : []
    readonly property int windowCount: windows.length
    readonly property bool isRunning: windowCount > 0
    readonly property bool isPinned: Boolean(currentItemData && currentItemData.isPinned)
    readonly property string appName: (currentItemData && currentItemData.name) ? currentItemData.name : ((currentItemData && currentItemData.id) ? currentItemData.id : "App")
    function normalizeAddr(addr) {
        if (!addr) return ""
        let s = String(addr).toLowerCase().trim()
        if (s.startsWith("0x")) s = s.slice(2)
        return s
    }

    readonly property bool isActive: {
        if (!isRunning) return false
        const activeAddr = (hypr.activeToplevel && hypr.activeToplevel.address) ? hypr.activeToplevel.address : ""
        return windows.some(w => w.activated || (activeAddr.length > 0 && normalizeAddr(w.address) === normalizeAddr(activeAddr)))
    }

    anchor.window: dockWindow
    anchor.edges: Edges.Top
    anchor.gravity: Edges.Top
    anchor.adjustment: PopupAdjustment.SlideX | PopupAdjustment.SlideY
    anchor.margins.bottom: 10
    color: "transparent"

    property bool shouldShow: false
    visible: shouldShow || menuContainer.opacity > 0

    readonly property bool isDockHovered: Boolean(root.dock && root.dock.isHovered)
    readonly property bool isMenuHovered: Boolean(menuHoverHandler.hovered)
    readonly property bool isPointerInside: isMenuHovered || isDockHovered

    Timer {
        id: hoverCloseTimer
        interval: 600
        repeat: false
        onTriggered: {
            if (!root.isPointerInside && root.shouldShow) {
                root.closeMenu()
            }
        }
    }

    onIsPointerInsideChanged: {
        if (isPointerInside) {
            hoverCloseTimer.stop()
        } else if (root.shouldShow) {
            hoverCloseTimer.restart()
        }
    }

    Connections {
        target: hypr

        function onFocusedWorkspaceChanged() {
            QsServices.Logger.debug("DockContextMenu", `onFocusedWorkspaceChanged fired, shouldShow: ${root.shouldShow}`)
            if (root.shouldShow) {
                root.closeMenu()
            }
        }

        function onFocusedMonitorChanged() {
            QsServices.Logger.debug("DockContextMenu", `onFocusedMonitorChanged fired, shouldShow: ${root.shouldShow}`)
            if (root.shouldShow) {
                root.closeMenu()
            }
        }

        function onToplevelsRefreshed() {
            if (root.shouldShow && root.currentItemData) {
                root.syncWindowsWithDock()
            }
        }
    }

    Connections {
        target: root.dock

        function onDockStateRevisionChanged() {
            if (root.shouldShow && root.currentItemData) {
                root.syncWindowsWithDock()
            }
        }
    }

    function normalizeAppId(id) {
        return (id || "").toLowerCase().replace(/\.desktop$/, "")
    }

    function syncWindowsWithDock() {
        if (!currentItemData || !dock) return
        const appId = currentItemData.id
        const norm = normalizeAppId(appId)
        const allItems = [...(dock.pinnedModel || []), ...(dock.runningModel || [])]
        const match = allItems.find(item => item && normalizeAppId(item.id) === norm)
        if (match) {
            currentItemData.windows = match.windows || []
            root.currentItemData = Object.assign({}, root.currentItemData)
        } else {
            currentItemData.windows = []
            root.currentItemData = Object.assign({}, root.currentItemData)
        }
    }

    property var programActions: []

    function resolveActions(itemData) {
        if (!itemData) return []
        const list = []
        
        // 1. Check if itemData already has actions from DesktopEntry
        const existingActions = itemData.actions ?? []
        for (let i = 0; i < existingActions.length; i++) {
            const a = existingActions[i]
            if (a && a.name && a.name.length > 0) {
                list.push(a)
            }
        }

        // 2. If empty, check DesktopEntries lookup
        if (list.length === 0) {
            const entry = itemData.entry
                       || (itemData.id ? (DesktopEntries.byId(itemData.id) || DesktopEntries.byId(itemData.id + ".desktop") || DesktopEntries.heuristicLookup(itemData.id)) : null)
            if (entry && entry.actions) {
                for (let i = 0; i < entry.actions.length; i++) {
                    const a = entry.actions[i]
                    if (a && a.name && a.name.length > 0) {
                        list.push({
                            name: a.name,
                            icon: a.icon || "",
                            execString: a.execString || "",
                            command: a.command || [],
                            execute: () => {
                                if (typeof a.execute === "function") {
                                    a.execute()
                                } else if (a.command && a.command.length > 0) {
                                    Quickshell.execDetached(a.command)
                                } else if (a.execString && a.execString.length > 0) {
                                    Quickshell.execDetached(["sh", "-c", a.execString])
                                }
                            }
                        })
                    }
                }
            }
        }

        // 3. Smart actions for apps whose .desktop file doesn't define any actions
        if (list.length === 0) {
            const id = (itemData.id ?? "").toLowerCase()
            const name = (itemData.name ?? "").toLowerCase()

            if (id.includes("equibop") || id.includes("vesktop") || id.includes("discord") || name.includes("equibop") || name.includes("discord")) {
                list.push({
                    name: "Mute / Unmute Mic",
                    icon: "",
                    execString: "equibop --toggle-mic",
                    execute: () => Quickshell.execDetached(["equibop", "--toggle-mic"])
                })
                list.push({
                    name: "Deafen / Undeafen Audio",
                    icon: "",
                    execString: "equibop --toggle-deafen",
                    execute: () => Quickshell.execDetached(["equibop", "--toggle-deafen"])
                })
                list.push({
                    name: "Start Minimized",
                    icon: "",
                    execString: "equibop --start-minimized",
                    execute: () => Quickshell.execDetached(["equibop", "--start-minimized"])
                })
            } else if (id.includes("obsidian") || name.includes("obsidian")) {
                list.push({
                    name: "New Note",
                    icon: "",
                    execString: "obsidian obsidian://new",
                    execute: () => Quickshell.execDetached(["obsidian", "obsidian://new"])
                })
                list.push({
                    name: "Open University Vault",
                    icon: "",
                    execString: "obsidian obsidian://open?vault=Obsidian%20-%20University",
                    execute: () => Quickshell.execDetached(["obsidian", "obsidian://open?vault=Obsidian - University"])
                })
            } else if (id.includes("dolphin") || name.includes("dolphin")) {
                list.push({
                    name: "Home Directory",
                    icon: "",
                    execString: "dolphin ~",
                    execute: () => Quickshell.execDetached(["dolphin", Quickshell.env("HOME")])
                })
                list.push({
                    name: "Downloads",
                    icon: "",
                    execString: "dolphin ~/Downloads",
                    execute: () => Quickshell.execDetached(["dolphin", `${Quickshell.env("HOME")}/Downloads`])
                })
            }
        }

        return list
    }

    function getActionMdiIcon(name, execString) {
        const text = `${name} ${execString}`.toLowerCase()
        if (text.includes("incognito") || text.includes("private") || text.includes("anonym")) return "󰗹"
        if (text.includes("mic") || text.includes("mute")) return "󰍬"
        if (text.includes("deafen") || text.includes("audio") || text.includes("sound")) return "󰟎"
        if (text.includes("note") || text.includes("poznámk")) return "󰏫"
        if (text.includes("vault")) return "󰠮"
        if (text.includes("home") || text.includes("domů")) return "󰋜"
        if (text.includes("download") || text.includes("stažen")) return "󰇚"
        if (text.includes("minimiz")) return "󰍁"
        if (text.includes("terminal") || text.includes("console")) return "󰞷"
        if (text.includes("window")) return "󰐕"
        if (text.includes("tab")) return "󰓩"
        if (text.includes("profile")) return "󰀉"
        if (text.includes("setting") || text.includes("pref") || text.includes("nastavení")) return "󰒓"
        if (text.includes("history") || text.includes("historie")) return "󰋚"
        if (text.includes("bookmark") || text.includes("záložk")) return "󰃃"
        if (text.includes("clean") || text.includes("clear")) return "󰃢"
        if (text.includes("friend") || text.includes("přátelé")) return "󰍡"
        if (text.includes("library") || text.includes("knihovn")) return "󰂺"
        if (text.includes("store") || text.includes("obchod")) return "󰄲"
        if (text.includes("play") || text.includes("spustit")) return "󰐊"
        return "󰄲"
    }

    implicitWidth: root.menuType === "launcher" ? 310 : 260
    implicitHeight: menuLayout.implicitHeight + 20

    IpcHandler {
        target: "dockmenu"

        function openLauncher() {
            if (root.dock && root.dock.launcherButton) {
                root.openMenu(root.dock.launcherButton, { type: "launcher" }, "launcher")
            }
        }

        function toggleSubmenu() {
            root.powerSubmenuExpanded = !root.powerSubmenuExpanded
        }

        function close() {
            root.closeMenu()
        }

        function getStatus(): string {
            return JSON.stringify({
                shouldShow: root.shouldShow,
                visible: root.visible,
                grabActive: Boolean(menuContainer && menuContainer.activeFocus),
                menuType: root.menuType,
                hasTarget: Boolean(root.currentTarget)
            })
        }
    }

    function openMenu(targetItem, itemData, type = "app") {
        QsServices.Logger.debug("DockContextMenu", `openMenu called, type: ${type}`)
        if (shouldShow && currentTarget === targetItem) {
            closeMenu()
            return
        }
        currentTarget = targetItem
        currentItemData = itemData
        menuType = type || "app"
        powerSubmenuExpanded = false
        programActions = (menuType === "app") ? resolveActions(itemData) : []
        anchor.item = targetItem
        hoverCloseTimer.stop()
        shouldShow = true
    }

    function closeMenu() {
        QsServices.Logger.debug("DockContextMenu", "closeMenu called")
        hoverCloseTimer.stop()
        shouldShow = false
        powerSubmenuExpanded = false
    }

    onClosed: {
        closeMenu()
    }

    onShouldShowChanged: {
        QsServices.Logger.debug("DockContextMenu", `shouldShow changed: ${shouldShow}`)
    }

    onVisibleChanged: {
        QsServices.Logger.debug("DockContextMenu", `visible changed: ${visible}`)
        if (visible) {
            menuContainer.forceActiveFocus()
        } else {
            hoverCloseTimer.stop()
            shouldShow = false
            currentTarget = null
            currentItemData = null
            programActions = []
            powerSubmenuExpanded = false
        }
    }

    function resolveIcon(item) {
        return QsServices.IconResolver.resolveAppIcon(item)
    }

    component WinXButton: Rectangle {
        id: btnRoot
        property string icon: ""
        property color iconColor: pywal.primary
        property string text: ""
        property string shortcut: ""
        property bool hasSubmenu: false
        property bool isExpanded: false
        property var action: null

        Layout.fillWidth: true
        Layout.preferredHeight: 28
        implicitHeight: 28
        radius: 7
        color: btnMouse.containsMouse
            ? Qt.rgba(pywal.foreground.r, pywal.foreground.g, pywal.foreground.b, 0.08)
            : (btnRoot.isExpanded ? Qt.rgba(pywal.primary.r, pywal.primary.g, pywal.primary.b, 0.12) : "transparent")

        Behavior on color { ColorAnimation { duration: 100 } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 9

            Text {
                Layout.preferredWidth: 18
                horizontalAlignment: Text.AlignHCenter
                text: btnRoot.icon
                font.family: "Material Design Icons"
                font.pixelSize: 15
                color: btnRoot.iconColor
            }

            Text {
                Layout.fillWidth: true
                text: btnRoot.text
                font.family: config.appearance.fontFamily
                font.pixelSize: 12
                font.weight: Font.Medium
                color: pywal.foreground
                elide: Text.ElideRight
            }

            Text {
                visible: btnRoot.shortcut.length > 0 && !btnRoot.hasSubmenu
                text: btnRoot.shortcut
                font.family: config.appearance.fontFamily
                font.pixelSize: 10
                color: pywal.onSurfaceMuted
            }

            Text {
                visible: btnRoot.hasSubmenu
                text: btnRoot.isExpanded ? "󰅀" : "󰅂"
                font.family: "Material Design Icons"
                font.pixelSize: 13
                color: btnRoot.isExpanded ? pywal.primary : pywal.onSurfaceMuted
            }
        }

        MouseArea {
            id: btnMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor

            onClicked: {
                if (btnRoot.hasSubmenu) {
                    root.powerSubmenuExpanded = !root.powerSubmenuExpanded
                } else if (btnRoot.action) {
                    btnRoot.action()
                }
            }
        }
    }

    component WinXSubmenuButton: Rectangle {
        id: subBtnRoot
        property string icon: ""
        property color iconColor: pywal.primary
        property string text: ""
        property string shortcut: ""
        property var action: null

        Layout.fillWidth: true
        Layout.preferredHeight: 26
        implicitHeight: 26
        radius: 6
        color: subMouse.containsMouse
            ? Qt.rgba(pywal.foreground.r, pywal.foreground.g, pywal.foreground.b, 0.10)
            : "transparent"

        Behavior on color { ColorAnimation { duration: 100 } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 8

            Text {
                Layout.preferredWidth: 16
                horizontalAlignment: Text.AlignHCenter
                text: subBtnRoot.icon
                font.family: "Material Design Icons"
                font.pixelSize: 14
                color: subBtnRoot.iconColor
            }

            Text {
                Layout.fillWidth: true
                text: subBtnRoot.text
                font.family: config.appearance.fontFamily
                font.pixelSize: 11
                font.weight: Font.Normal
                color: pywal.foreground
                elide: Text.ElideRight
            }

            Text {
                visible: subBtnRoot.shortcut.length > 0
                text: subBtnRoot.shortcut
                font.family: config.appearance.fontFamily
                font.pixelSize: 9
                color: pywal.onSurfaceMuted
            }
        }

        MouseArea {
            id: subMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor

            onClicked: {
                if (subBtnRoot.action) {
                    subBtnRoot.action()
                }
            }
        }
    }

    component WinXDivider: Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 3
        Layout.bottomMargin: 3
        height: 1
        color: Qt.rgba(pywal.foreground.r, pywal.foreground.g, pywal.foreground.b, 0.08)
    }

    // Outer animated wrapper
    FocusScope {
        id: menuContainer
        anchors.fill: parent
        focus: root.visible

        HoverHandler {
            id: menuHoverHandler
            margin: 15
        }

        Keys.onEscapePressed: {
            root.closeMenu()
        }

        scale: root.shouldShow ? 1.0 : 0.94
        opacity: root.shouldShow ? 1.0 : 0.0
        transformOrigin: Item.Bottom

        Behavior on scale {
            NumberAnimation {
                duration: root.shouldShow ? 350 : 180
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.shouldShow ? Material3Anim.expressiveFastSpatial : Material3Anim.emphasizedAccel
            }
        }
        Behavior on opacity {
            NumberAnimation {
                duration: root.shouldShow ? 150 : 180
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.shouldShow ? Material3Anim.expressiveFastEffects : Material3Anim.emphasizedAccel
            }
        }

        AuroraSurface {
            id: menuSurface
            anchors.fill: parent
            radius: 18
            color: pywal.surfaceContainerHighest
            strokeColor: pywal.outlineVariant
            borderWidth: 1
            accentColor: pywal.primary
            elevation: 5

            ColumnLayout {
                id: menuLayout
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 10
                spacing: root.menuType === "launcher" ? 2 : 4

                // ═══════════════════════════════════════════════════════════
                // HEADER SECTION (Only for Apps)
                // ═══════════════════════════════════════════════════════════
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.menuType === "app"
                    Layout.leftMargin: 4
                    Layout.rightMargin: 4
                    Layout.topMargin: 2
                    Layout.bottomMargin: 4
                    spacing: 10

                    // App Icon
                    Item {
                        Layout.preferredWidth: 26
                        Layout.preferredHeight: 26

                        IconImage {
                            id: menuHeaderIcon
                            anchors.fill: parent
                            visible: source.toString().length > 0 && status === Image.Ready
                            source: root.resolveIcon(root.currentItemData)
                            asynchronous: true
                            mipmap: true
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: !menuHeaderIcon.visible
                            text: root.appName.length > 0 ? root.appName.slice(0, 1).toUpperCase() : "󰣆"
                            font.family: config.appearance.fontFamily
                            font.pixelSize: 14
                            font.weight: Font.Bold
                            color: pywal.primary
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            text: root.appName
                            font.family: config.appearance.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            color: pywal.foreground
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            font.family: config.appearance.fontFamily
                            font.pixelSize: 11
                            color: root.isActive ? pywal.primary : pywal.onSurfaceMuted
                            elide: Text.ElideRight
                            text: {
                                if (root.isActive) return "Active now"
                                if (root.windowCount > 1) return `${root.windowCount} windows open`
                                if (root.windowCount === 1) return "1 window open"
                                return "Pinned to dock"
                            }
                        }
                    }
                }

                // Divider
                Rectangle {
                    Layout.fillWidth: true
                    visible: root.menuType === "app"
                    height: 1
                    color: Qt.rgba(pywal.foreground.r, pywal.foreground.g, pywal.foreground.b, 0.08)
                }

                // ═══════════════════════════════════════════════════════════
                // OPEN WINDOWS LIST (if app has windows)
                // ═══════════════════════════════════════════════════════════
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.menuType === "app" && root.windowCount > 0
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        Layout.leftMargin: 6
                        Layout.topMargin: 4
                        Layout.bottomMargin: 2
                        text: "OPEN WINDOWS"
                        font.family: config.appearance.fontFamily
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        color: pywal.onSurfaceMuted
                    }

                    Repeater {
                        model: root.windows

                        delegate: Rectangle {
                            id: winDelegate
                            required property var modelData
                            required property int index

                            Layout.fillWidth: true
                            Layout.preferredHeight: 30
                            radius: 8

                            readonly property bool isWinActive: {
                                if (!modelData) return false
                                const activeAddr = (hypr.activeToplevel && hypr.activeToplevel.address) ? hypr.activeToplevel.address : ""
                                return Boolean(modelData.activated || (activeAddr.length > 0 && root.normalizeAddr(modelData.address) === root.normalizeAddr(activeAddr)))
                            }
                            readonly property bool isItemHovered: winMouse.containsMouse

                            color: isItemHovered
                                ? Qt.rgba(pywal.foreground.r, pywal.foreground.g, pywal.foreground.b, 0.10)
                                : (isWinActive ? Qt.rgba(pywal.primary.r, pywal.primary.g, pywal.primary.b, 0.08) : "transparent")

                            Behavior on color { ColorAnimation { duration: 120 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 6
                                spacing: 8

                                // Active indicator dot
                                Rectangle {
                                    Layout.preferredWidth: 6
                                    Layout.preferredHeight: 6
                                    radius: 3
                                    color: winDelegate.isWinActive ? pywal.primary : Qt.rgba(pywal.foreground.r, pywal.foreground.g, pywal.foreground.b, 0.3)
                                }

                                // Window title
                                Text {
                                    Layout.fillWidth: true
                                    text: {
                                        const t = (winDelegate.modelData && winDelegate.modelData.title) ? winDelegate.modelData.title : ""
                                        return t.length > 0 ? t : (root.appName + " (Window " + (winDelegate.index + 1) + ")")
                                    }
                                    font.family: config.appearance.fontFamily
                                    font.pixelSize: 11
                                    font.weight: winDelegate.isWinActive ? Font.Medium : Font.Normal
                                    color: winDelegate.isWinActive ? pywal.foreground : pywal.onSurfaceMuted
                                    elide: Text.ElideRight
                                }

                                // Close this specific window button
                                Rectangle {
                                    id: closeBtn
                                    Layout.preferredWidth: 20
                                    Layout.preferredHeight: 20
                                    radius: 6
                                    color: closeMouse.containsMouse
                                        ? Qt.rgba(pywal.error.r, pywal.error.g, pywal.error.b, 0.20)
                                        : "transparent"

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰅖"
                                        font.family: "Material Design Icons"
                                        font.pixelSize: 13
                                        color: closeMouse.containsMouse ? pywal.error : pywal.onSurfaceMuted
                                    }

                                    MouseArea {
                                        id: closeMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            const addr = winDelegate.modelData ? winDelegate.modelData.address : null
                                            if (addr) {
                                                hypr.closeWindow(addr)
                                            }
                                            if (root.currentItemData && Array.isArray(root.currentItemData.windows)) {
                                                root.currentItemData.windows = root.currentItemData.windows.filter(w => root.normalizeAddr(w.address) !== root.normalizeAddr(addr))
                                                root.currentItemData = Object.assign({}, root.currentItemData)
                                            }
                                            if ((root.currentItemData && root.currentItemData.windows && root.currentItemData.windows.length > 0 ? root.currentItemData.windows.length : 0) <= 0 && !root.isPinned) {
                                                root.closeMenu()
                                            }
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: winMouse
                                anchors.fill: parent
                                anchors.rightMargin: 24 // leave room for close button
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (winDelegate.modelData && winDelegate.modelData.address) {
                                        hypr.focusWindow(winDelegate.modelData.address)
                                    }
                                    root.closeMenu()
                                }
                            }
                        }
                    }

                    // Divider after windows
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        Layout.bottomMargin: 2
                        height: 1
                        color: Qt.rgba(pywal.foreground.r, pywal.foreground.g, pywal.foreground.b, 0.08)
                    }
                }

                // ═══════════════════════════════════════════════════════════
                // PROGRAM DESKTOP ACTIONS (e.g. Chromium Incognito, New Terminal...)
                // ═══════════════════════════════════════════════════════════
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.menuType === "app" && root.programActions.length > 0
                    spacing: 2

                    Repeater {
                        model: root.programActions

                        delegate: Rectangle {
                            id: actDelegate
                            required property var modelData
                            required property int index

                            Layout.fillWidth: true
                            Layout.preferredHeight: 30
                            radius: 8
                            color: actMouse.containsMouse
                                ? Qt.rgba(pywal.foreground.r, pywal.foreground.g, pywal.foreground.b, 0.08)
                                : "transparent"

                            Behavior on color { ColorAnimation { duration: 120 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 8

                                Item {
                                    Layout.preferredWidth: 16
                                    Layout.preferredHeight: 16

                                    IconImage {
                                        anchors.fill: parent
                                        visible: status === Image.Ready
                                        source: (actDelegate.modelData && actDelegate.modelData.icon) ? QsServices.IconResolver.tryIconName(actDelegate.modelData.icon) : ""
                                        asynchronous: true
                                        mipmap: true
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        visible: !parent.children[0].visible
                                        text: root.getActionMdiIcon((actDelegate.modelData && actDelegate.modelData.name) ? actDelegate.modelData.name : "", (actDelegate.modelData && actDelegate.modelData.execString) ? actDelegate.modelData.execString : "")
                                        font.family: "Material Design Icons"
                                        font.pixelSize: 15
                                        color: {
                                            const lower = ((actDelegate.modelData && actDelegate.modelData.name) ? actDelegate.modelData.name : "").toLowerCase()
                                            if (lower.includes("incognito") || lower.includes("private") || lower.includes("anonym")) return pywal.secondary
                                            return pywal.primary
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: (actDelegate.modelData && actDelegate.modelData.name) ? actDelegate.modelData.name : ""
                                    font.family: config.appearance.fontFamily
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                    color: pywal.foreground
                                    elide: Text.ElideRight
                                }
                            }

                            MouseArea {
                                id: actMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!actDelegate.modelData) return
                                    if (typeof actDelegate.modelData.execute === "function") {
                                        actDelegate.modelData.execute()
                                    } else if (actDelegate.modelData.command && actDelegate.modelData.command.length > 0) {
                                        Quickshell.execDetached(actDelegate.modelData.command)
                                    } else if (actDelegate.modelData.execString) {
                                        Quickshell.execDetached(["sh", "-c", actDelegate.modelData.execString])
                                    }
                                    root.closeMenu()
                                }
                            }
                        }
                    }

                    // Divider after desktop actions
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 2
                        Layout.bottomMargin: 2
                        height: 1
                        color: Qt.rgba(pywal.foreground.r, pywal.foreground.g, pywal.foreground.b, 0.08)
                    }
                }

                // ═══════════════════════════════════════════════════════════
                // APP ACTIONS (Launch, Close, Pin/Unpin)
                // ═══════════════════════════════════════════════════════════
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.menuType === "app"
                    spacing: 2

                    // Action 1: Generic New Window (only if app doesn't have custom desktop actions)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 30
                        radius: 8
                        visible: root.programActions.length === 0
                        color: newWinMouse.containsMouse ? Qt.rgba(pywal.foreground.r, pywal.foreground.g, pywal.foreground.b, 0.08) : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            Text {
                                text: "󰐕"
                                font.family: "Material Design Icons"
                                font.pixelSize: 15
                                color: pywal.primary
                            }

                            Text {
                                Layout.fillWidth: true
                                text: root.isRunning ? "New Window" : "Launch App"
                                font.family: config.appearance.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.Medium
                                color: pywal.foreground
                            }
                        }

                        MouseArea {
                            id: newWinMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.dock) {
                                    root.dock.launchApp(root.currentItemData)
                                }
                                root.closeMenu()
                            }
                        }
                    }

                    // Action 2: Close Active Window (only if running)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 30
                        radius: 8
                        visible: root.isRunning
                        color: closeWinMouse.containsMouse ? Qt.rgba(pywal.error.r, pywal.error.g, pywal.error.b, 0.12) : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            Text {
                                text: "󰅙"
                                font.family: "Material Design Icons"
                                font.pixelSize: 15
                                color: closeWinMouse.containsMouse ? pywal.error : pywal.onSurfaceMuted
                            }

                            Text {
                                Layout.fillWidth: true
                                text: "Close Window"
                                font.family: config.appearance.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.Medium
                                color: closeWinMouse.containsMouse ? pywal.error : pywal.foreground
                            }

                            Text {
                                text: "Middle-click"
                                font.family: config.appearance.fontFamily
                                font.pixelSize: 10
                                color: pywal.onSurfaceMuted
                            }
                        }

                        MouseArea {
                            id: closeWinMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.windows.length > 0) {
                                    const activeAddr = (hypr.activeToplevel && hypr.activeToplevel.address) ? hypr.activeToplevel.address : ""
                                    const target = root.windows.find(w => w.activated || (activeAddr.length > 0 && root.normalizeAddr(w.address) === root.normalizeAddr(activeAddr))) ?? root.windows[0]
                                    hypr.closeWindow(target.address)
                                }
                                root.closeMenu()
                            }
                        }
                    }

                    // Action 3: Close All Windows (only if > 1 window)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 30
                        radius: 8
                        visible: root.windowCount > 1
                        color: closeAllMouse.containsMouse ? Qt.rgba(pywal.error.r, pywal.error.g, pywal.error.b, 0.12) : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            Text {
                                text: "󰅗"
                                font.family: "Material Design Icons"
                                font.pixelSize: 15
                                color: closeAllMouse.containsMouse ? pywal.error : pywal.onSurfaceMuted
                            }

                            Text {
                                Layout.fillWidth: true
                                text: `Close All Windows (${root.windowCount})`
                                font.family: config.appearance.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.Medium
                                color: closeAllMouse.containsMouse ? pywal.error : pywal.foreground
                            }
                        }

                        MouseArea {
                            id: closeAllMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                for (const w of root.windows) {
                                    hypr.closeWindow(w.address)
                                }
                                root.closeMenu()
                            }
                        }
                    }

                    // Action 4: Toggle Pin to Dock
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 30
                        radius: 8
                        color: pinMouse.containsMouse ? Qt.rgba(pywal.foreground.r, pywal.foreground.g, pywal.foreground.b, 0.08) : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            Text {
                                text: root.isPinned ? "󰤲" : "󰤱"
                                font.family: "Material Design Icons"
                                font.pixelSize: 15
                                color: root.isPinned ? pywal.primary : pywal.onSurfaceMuted
                            }

                            Text {
                                Layout.fillWidth: true
                                text: root.isPinned ? "Unpin from Dock" : "Pin to Dock"
                                font.family: config.appearance.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.Medium
                                color: pywal.foreground
                            }
                        }

                        MouseArea {
                            id: pinMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.dock && root.currentItemData) {
                                    root.dock.togglePin(root.currentItemData.id)
                                }
                                root.closeMenu()
                            }
                        }
                    }

                    // Action 5: Move Left in Dock
                    Rectangle {
                        id: moveLeftBtn
                        readonly property var pinnedList: root.config.dock.pinned ?? []
                        readonly property int currentPinnedIdx: {
                            if (root.currentTarget && root.currentTarget.isPinnedSection && root.currentTarget.itemIndex >= 0) {
                                return root.currentTarget.itemIndex
                            }
                            if (!root.currentItemData || !root.currentItemData.id) return -1
                            const norm = (root.currentItemData.id || "").toLowerCase().replace(/\.desktop$/, "")
                            return pinnedList.findIndex(id => (id || "").toLowerCase().replace(/\.desktop$/, "") === norm)
                        }
                        readonly property bool canMoveLeft: root.isPinned && currentPinnedIdx > 0

                        visible: canMoveLeft
                        Layout.fillWidth: true
                        Layout.preferredHeight: canMoveLeft ? 30 : 0
                        radius: 8
                        color: moveLeftMouse.containsMouse ? Qt.rgba(pywal.foreground.r, pywal.foreground.g, pywal.foreground.b, 0.08) : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            Text {
                                text: "󰅁"
                                font.family: "Material Design Icons"
                                font.pixelSize: 15
                                color: pywal.primary
                            }

                            Text {
                                Layout.fillWidth: true
                                text: "Move Left in Dock"
                                font.family: config.appearance.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.Medium
                                color: pywal.foreground
                            }
                        }

                        MouseArea {
                            id: moveLeftMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.dock && moveLeftBtn.canMoveLeft) {
                                    root.dock.movePinnedItem(moveLeftBtn.currentPinnedIdx, moveLeftBtn.currentPinnedIdx - 1)
                                }
                                root.closeMenu()
                            }
                        }
                    }

                    // Action 6: Move Right in Dock
                    Rectangle {
                        id: moveRightBtn
                        readonly property var pinnedList: root.config.dock.pinned ?? []
                        readonly property int currentPinnedIdx: {
                            if (root.currentTarget && root.currentTarget.isPinnedSection && root.currentTarget.itemIndex >= 0) {
                                return root.currentTarget.itemIndex
                            }
                            if (!root.currentItemData || !root.currentItemData.id) return -1
                            const norm = (root.currentItemData.id || "").toLowerCase().replace(/\.desktop$/, "")
                            return pinnedList.findIndex(id => (id || "").toLowerCase().replace(/\.desktop$/, "") === norm)
                        }
                        readonly property bool canMoveRight: root.isPinned && currentPinnedIdx >= 0 && currentPinnedIdx < pinnedList.length - 1

                        visible: canMoveRight
                        Layout.fillWidth: true
                        Layout.preferredHeight: canMoveRight ? 30 : 0
                        radius: 8
                        color: moveRightMouse.containsMouse ? Qt.rgba(pywal.foreground.r, pywal.foreground.g, pywal.foreground.b, 0.08) : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            Text {
                                text: "󰅂"
                                font.family: "Material Design Icons"
                                font.pixelSize: 15
                                color: pywal.primary
                            }

                            Text {
                                Layout.fillWidth: true
                                text: "Move Right in Dock"
                                font.family: config.appearance.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.Medium
                                color: pywal.foreground
                            }
                        }

                        MouseArea {
                            id: moveRightMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.dock && moveRightBtn.canMoveRight) {
                                    root.dock.movePinnedItem(moveRightBtn.currentPinnedIdx, moveRightBtn.currentPinnedIdx + 1)
                                }
                                root.closeMenu()
                            }
                        }
                    }
                }

                // ═══════════════════════════════════════════════════════════
                // LAUNCHER ACTIONS (Windows Super+X / Power User Menu)
                // ═══════════════════════════════════════════════════════════
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.menuType === "launcher"
                    spacing: 2

                    // ═══════════════════════════════════════════════════════════
                    // GROUP 1: DAILY TOOLS
                    // ═══════════════════════════════════════════════════════════
                    WinXButton {
                        icon: "󰍉"
                        iconColor: pywal.primary
                        text: "Search & Apps"
                        shortcut: "Super + Space"
                        action: () => {
                            Quickshell.execDetached(["vicinae", "toggle"])
                            root.closeMenu()
                        }
                    }

                    WinXButton {
                        icon: "󰞷"
                        iconColor: pywal.primary
                        text: "Terminal"
                        shortcut: "Super + Return"
                        action: () => {
                            Quickshell.execDetached(["alacritty"])
                            root.closeMenu()
                        }
                    }

                    WinXButton {
                        icon: "󰉋"
                        iconColor: pywal.secondary
                        text: "File Explorer"
                        shortcut: "Super + E"
                        action: () => {
                            Quickshell.execDetached(["dolphin"])
                            root.closeMenu()
                        }
                    }

                    WinXButton {
                        icon: "󰄪"
                        iconColor: pywal.info
                        text: "Task Manager"
                        action: () => {
                            Quickshell.execDetached(["alacritty", "-T", "Task Manager", "-e", "btop"])
                            root.closeMenu()
                        }
                    }

                    WinXButton {
                        icon: "󰒓"
                        iconColor: pywal.primary
                        text: "Settings & Control Center"
                        shortcut: "Super + I"
                        action: () => {
                            Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/hypr-settings.sh"])
                            root.closeMenu()
                        }
                    }

                    WinXDivider {}

                    // ═══════════════════════════════════════════════════════════
                    // GROUP 2: SYSTEM MANAGEMENT & HARDWARE
                    // ═══════════════════════════════════════════════════════════
                    WinXButton {
                        icon: "󰍹"
                        iconColor: pywal.secondary
                        text: "System Info"
                        action: () => {
                            Quickshell.execDetached(["kitty", "--hold", "-T", "System Info", "-e", "fastfetch"])
                            root.closeMenu()
                        }
                    }

                    WinXButton {
                        icon: "󰓃"
                        iconColor: pywal.primary
                        text: "Device Manager"
                        action: () => {
                            Quickshell.execDetached(["kitty", "--class=pulsemixer-float", "-T", "Audio Mixer (Pulsemixer)", "-e", "pulsemixer"])
                            root.closeMenu()
                        }
                    }

                    WinXButton {
                        icon: "󰤨"
                        iconColor: pywal.info
                        text: "Network Connections (Gazelle)"
                        action: () => {
                            Quickshell.execDetached(["kitty", "--class=gazelle-float", "-T", "Wi-Fi Connections (Gazelle)", "-e", "gazelle"])
                            root.closeMenu()
                        }
                    }

                    WinXButton {
                        icon: "󰋊"
                        iconColor: pywal.secondary
                        text: "Disk Management"
                        action: () => {
                            Quickshell.execDetached(["partitionmanager"])
                            root.closeMenu()
                        }
                    }

                    WinXButton {
                        icon: "󰌱"
                        iconColor: pywal.info
                        text: "System Logs"
                        action: () => {
                            Quickshell.execDetached(["alacritty", "-T", "System Logs", "-e", "journalctl", "-xe", "-f"])
                            root.closeMenu()
                        }
                    }

                    WinXDivider {}

                    // ═══════════════════════════════════════════════════════════
                    // GROUP 3: DESKTOP & POWER
                    // ═══════════════════════════════════════════════════════════
                    WinXButton {
                        icon: "󰇄"
                        iconColor: pywal.primary
                        text: "Desktop"
                        shortcut: "Super + S"
                        action: () => {
                            Quickshell.execDetached(["sh", "-c", "hyprctl dispatch 'hl.dsp.workspace.toggle_special(\"magic\")'"])
                            root.closeMenu()
                        }
                    }

                    WinXButton {
                        icon: "󰐥"
                        iconColor: pywal.error
                        text: "Shut down or sign out"
                        hasSubmenu: true
                        isExpanded: root.powerSubmenuExpanded
                    }

                    // Submenu Panel
                    Rectangle {
                        id: powerSubmenuContainer
                        Layout.fillWidth: true
                        visible: root.powerSubmenuExpanded
                        Layout.leftMargin: 2
                        Layout.rightMargin: 2
                        Layout.topMargin: 1
                        Layout.bottomMargin: 2
                        radius: 8
                        color: Qt.rgba(pywal.foreground.r, pywal.foreground.g, pywal.foreground.b, 0.04)
                        border.width: 1
                        border.color: Qt.rgba(pywal.foreground.r, pywal.foreground.g, pywal.foreground.b, 0.08)
                        Layout.preferredHeight: root.powerSubmenuExpanded ? (powerSubmenuLayout.implicitHeight + 8) : 0
                        implicitHeight: root.powerSubmenuExpanded ? (powerSubmenuLayout.implicitHeight + 8) : 0

                        ColumnLayout {
                            id: powerSubmenuLayout
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 4
                            spacing: 2

                            WinXSubmenuButton {
                                icon: "󰍃"
                                iconColor: pywal.success
                                text: "Sign out"
                                shortcut: "Super + Shift + E"
                                action: () => {
                                    Quickshell.execDetached(["sh", "-c", "hyprctl dispatch 'hl.dsp.exec_cmd(\"hyprctl dispatch exit\")'"])
                                    root.closeMenu()
                                }
                            }

                            WinXSubmenuButton {
                                icon: "󰤄"
                                iconColor: pywal.info
                                text: "Sleep"
                                action: () => {
                                    Quickshell.execDetached(["systemctl", "suspend"])
                                    root.closeMenu()
                                }
                            }

                            WinXSubmenuButton {
                                icon: "󰜉"
                                iconColor: pywal.warning
                                text: "Restart"
                                action: () => {
                                    Quickshell.execDetached(["systemctl", "reboot"])
                                    root.closeMenu()
                                }
                            }

                            WinXSubmenuButton {
                                icon: "󰐥"
                                iconColor: pywal.error
                                text: "Shut down"
                                action: () => {
                                    Quickshell.execDetached(["systemctl", "poweroff"])
                                    root.closeMenu()
                                }
                            }

                            WinXSubmenuButton {
                                icon: "󰌾"
                                iconColor: pywal.primary
                                text: "Lock"
                                shortcut: "Super + L"
                                action: () => {
                                    Quickshell.execDetached(["sh", "-c", "pgrep -f 'quickshell-caelestia/shell' >/dev/null && quickshell -p \"$HOME/.config/quickshell-caelestia/shell\" ipc call lock lock || hyprlock"])
                                    root.closeMenu()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
