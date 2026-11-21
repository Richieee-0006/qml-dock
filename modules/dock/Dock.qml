import QtQuick 6.10
import QtQuick.Layouts 6.10
import Quickshell
import Quickshell.Io
import "../../config" as QsConfig
import "../../services" as QsServices
import "../../components"
import "../../components/effects"

Item {
    id: root

    property var screen
    property var dockWindow
    property var launcher

    readonly property var config: QsConfig.Config
    readonly property var pywal: QsServices.Pywal.dock
    readonly property var hypr: QsServices.Hypr

    property var pinnedModel: buildPinnedModel()
    property var runningModel: buildRunningModel(pinnedModel)
    property int dockStateRevision: 0

    // Minecraft & app instance cache
    property var instanceCache: ({})
    property var pendingResolutions: []

    Process {
        id: instanceResolverProc
        property int resolvingPid: 0
        command: []
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                if (text && text.trim().length > 0) {
                    try {
                        const res = JSON.parse(text)
                        if (res && res.pid) {
                            const newCache = Object.assign({}, root.instanceCache)
                            newCache[res.pid] = res
                            root.instanceCache = newCache
                            root.updateDockItems()
                        }
                    } catch (e) {}
                }
                root.runNextInstanceResolution()
            }
        }
        onExited: {
            root.runNextInstanceResolution()
        }
    }

    function runNextInstanceResolution() {
        if (instanceResolverProc.running) return
        if (root.pendingResolutions.length === 0) return
        const item = root.pendingResolutions.shift()
        instanceResolverProc.resolvingPid = item.pid
        const script = Qt.resolvedUrl("../../services/resolve-instance.py").toString().replace(/^file:\/\//, "")
        instanceResolverProc.command = [script, String(item.pid), item.title || "", item.cls || ""]
        instanceResolverProc.running = true
    }

    function requestInstanceResolution(pid, title, cls) {
        if (!pid || root.instanceCache[pid]) return
        if (!root.pendingResolutions.some(p => p.pid === pid)) {
            root.pendingResolutions.push({ pid: pid, title: title || "", cls: cls || "" })
        }
        runNextInstanceResolution()
    }

    HoverHandler {
        id: dockRootHoverHandler
    }

    // Drag & Drop reordering state
    property bool isDraggingActive: false
    property var draggedItem: null
    property int dragSourceIndex: -1
    property int dragTargetIndex: -1
    property bool dragSourceIsPinned: false
    property bool isDropCommitting: false

    function normalizeAppId(id) {
        return (id || "").toLowerCase().replace(/\.desktop$/, "")
    }

    function getSlotPitch() {
        return config.dock.iconSize + 16 + config.dock.spacing
    }

    function startItemDrag(item, itemData, index, isPinned) {
        root.closeContextMenu()
        root.draggedItem = item
        root.dragSourceIsPinned = isPinned
        root.dragSourceIndex = isPinned ? index : -1
        root.dragTargetIndex = isPinned ? index : -1
        root.isDraggingActive = true
    }

    function updateItemDrag(item) {
        if (!root.isDraggingActive || !item) return

        const centerPt = item.mapToItem(pinnedContainer, item.width / 2, item.height / 2)
        const pitch = root.getSlotPitch()
        const pinnedCount = root.pinnedModel.length

        if (root.dragSourceIsPinned) {
            if (pinnedCount <= 1) {
                root.dragTargetIndex = 0
                return
            }
            const rawSlot = Math.round((centerPt.x - item.width / 2) / pitch)
            root.dragTargetIndex = Math.max(0, Math.min(rawSlot, pinnedCount - 1))
        } else {
            // Unpinned item dragged towards or within pinned items
            if (centerPt.x < -pitch * 0.5 || centerPt.x > (pinnedCount + 0.5) * pitch) {
                // Outside pinned section
                root.dragTargetIndex = -1
            } else {
                const rawSlot = Math.round((centerPt.x - item.width / 2) / pitch)
                root.dragTargetIndex = Math.max(0, Math.min(rawSlot, pinnedCount))
            }
        }
    }

    function finishItemDrag(item) {
        if (!root.isDraggingActive) return

        const src = root.dragSourceIndex
        const tgt = root.dragTargetIndex
        const isPinned = root.dragSourceIsPinned
        const appId = (item && item.itemData) ? item.itemData.id : null

        if (isPinned) {
            if (src >= 0 && tgt >= 0 && src !== tgt) {
                root.isDropCommitting = true
                root.isDraggingActive = false
                root.draggedItem = null
                root.dragSourceIndex = -1
                root.dragTargetIndex = -1
                if (item) {
                    item.dragTranslationX = 0
                    item.dragTranslationY = 0
                }
                root.movePinnedItem(src, tgt)
                root.isDropCommitting = false
                return
            }
        } else if (appId && tgt >= 0) {
            root.isDropCommitting = true
            root.isDraggingActive = false
            root.draggedItem = null
            root.dragSourceIndex = -1
            root.dragTargetIndex = -1
            if (item) {
                item.dragTranslationX = 0
                item.dragTranslationY = 0
            }
            root.pinItemAt(appId, tgt)
            root.isDropCommitting = false
            return
        }

        // Cancelled or dropped back in original slot
        root.isDraggingActive = false
        root.draggedItem = null
        root.dragSourceIndex = -1
        root.dragTargetIndex = -1
        if (item) {
            item.dragTranslationX = 0
            item.dragTranslationY = 0
        }
        Qt.callLater(root.updateDockItems)
    }

    function cancelItemDrag(item) {
        root.isDraggingActive = false
        root.draggedItem = null
        root.dragSourceIndex = -1
        root.dragTargetIndex = -1
        if (item) {
            item.dragTranslationX = 0
            item.dragTranslationY = 0
        }
        Qt.callLater(root.updateDockItems)
    }

    function movePinnedItem(fromIndex, toIndex) {
        const currentPinned = [...(config.dock.pinned ?? [])]
        if (fromIndex < 0 || fromIndex >= currentPinned.length) return
        const safeTo = Math.max(0, Math.min(toIndex, currentPinned.length - 1))
        if (fromIndex === safeTo) return

        const item = currentPinned.splice(fromIndex, 1)[0]
        currentPinned.splice(safeTo, 0, item)

        config.dock.pinned = currentPinned
        updateDockItems()
        savePinnedToShellJson(currentPinned)
    }

    function pinItemAt(appId, targetIndex) {
        if (!appId) return
        const currentPinned = [...(config.dock.pinned ?? [])]
        const norm = normalizeAppId(appId)
        const existingIdx = currentPinned.findIndex(id => normalizeAppId(id) === norm)
        if (existingIdx !== -1) {
            currentPinned.splice(existingIdx, 1)
        }
        const safeTo = Math.max(0, Math.min(targetIndex, currentPinned.length))
        currentPinned.splice(safeTo, 0, appId)

        config.dock.pinned = currentPinned
        updateDockItems()
        savePinnedToShellJson(currentPinned)
    }

    Shortcut {
        sequence: "Escape"
        enabled: root.isDraggingActive
        onActivated: root.cancelItemDrag(root.draggedItem)
    }

    IpcHandler {
        target: "dock"

        function movePinned(fromIndex: int, toIndex: int) {
            root.movePinnedItem(fromIndex, toIndex)
        }

        function moveApp(appId: string, targetIndex: int) {
            const currentPinned = [...(config.dock.pinned ?? [])]
            const norm = root.normalizeAppId(appId)
            const fromIdx = currentPinned.findIndex(id => root.normalizeAppId(id) === norm)
            if (fromIdx !== -1) {
                root.movePinnedItem(fromIdx, targetIndex)
            }
        }

        function getPinned(): string {
            return JSON.stringify(config.dock.pinned ?? [])
        }

        function togglePin(appId: string) {
            root.togglePin(appId)
        }

        function pinAt(appId: string, targetIndex: int) {
            root.pinItemAt(appId, targetIndex)
        }

        function closeWindow(address: string) {
            hypr.closeWindow(address)
        }

        function getDebugState(): string {
            const tl = hypr.toplevels.values ?? []
            return JSON.stringify({
                toplevelCount: tl.length,
                toplevels: tl.map(t => ({
                    address: t.address,
                    title: t.title,
                    cls: (t.lastIpcObject && t.lastIpcObject.class) ? t.lastIpcObject.class : "",
                    initCls: (t.lastIpcObject && t.lastIpcObject.initialClass) ? t.lastIpcObject.initialClass : ""
                })),
                pinned: root.pinnedModel.map(p => ({
                    id: p.id,
                    winCount: p.windows ? p.windows.length : 0,
                    wins: (p.windows || []).map(w => ({ addr: w.address, title: w.title }))
                })),
                running: root.runningModel.map(r => ({
                    id: r.id,
                    winCount: r.windows ? r.windows.length : 0,
                    wins: (r.windows || []).map(w => ({ addr: w.address, title: w.title }))
                }))
            })
        }
    }

    readonly property alias surfaceItem: surface
    readonly property alias launcherButton: launcherBtn
    readonly property bool isHovered: dockHoverHandler.hovered || dockRootHoverHandler.hovered

    implicitWidth: surface.width
    implicitHeight: surface.height

    property bool isMenuOpen: false
    signal contextMenuRequested(var targetItem, var itemData, string type)
    signal closeContextMenuRequested()

    function openContextMenu(targetItem, itemData, type = "app") {
        if (type === "app" && itemData) {
            if (!itemData.actions || itemData.actions.length === 0) {
                const entry = itemData.entry
                           || DesktopEntries.byId(itemData.id)
                           || DesktopEntries.byId(itemData.id + ".desktop")
                           || DesktopEntries.heuristicLookup(itemData.id)
                if (entry) {
                    itemData.entry = entry
                    itemData.actions = extractActions(entry)
                }
            }
        }
        contextMenuRequested(targetItem, itemData, type)
    }

    function closeContextMenu() {
        closeContextMenuRequested()
    }

    function launchApp(itemData) {
        if (!itemData) return
        const appId = itemData.id || ""
        let entry = itemData.entry || null
        // Re-lookup live DesktopEntry if cached QObject became stale across DesktopEntries reload
        if ((!entry || (!entry.command && !entry.id)) && appId.length > 0) {
            entry = DesktopEntries.heuristicLookup(appId)
                 || DesktopEntries.byId(appId)
                 || DesktopEntries.byId(appId + ".desktop")
        }
        if (entry) {
            if (entry.runInTerminal && entry.command && entry.command.length > 0) {
                const term = config.launcher.terminalCommand ?? ["foot"]
                Quickshell.execDetached([...term, ...entry.command])
                return
            }
            if (entry.command && entry.command.length > 0) {
                Quickshell.execDetached({
                    command: entry.command,
                    workingDirectory: entry.workingDirectory
                })
                return
            }
            if (entry.id && entry.id.length > 0) {
                Quickshell.execDetached([entry.id.replace(/\.desktop$/, "")])
                return
            }
        }
        if (appId.length > 0) {
            Quickshell.execDetached([appId.replace(/\.desktop$/, "")])
        }
    }

    function togglePin(appId) {
        if (!appId) return
        const currentPinned = [...(config.dock.pinned ?? [])]
        const norm = normalizeAppId(appId)
        const idx = currentPinned.findIndex(id => normalizeAppId(id) === norm)

        if (idx !== -1) {
            currentPinned.splice(idx, 1)
        } else {
            currentPinned.push(appId)
        }

        config.dock.pinned = currentPinned
        updateDockItems()
        savePinnedToShellJson(currentPinned)
    }

    function savePinnedToShellJson(pinnedList) {
        const jsonPath = config.configPath
        const listStr = JSON.stringify(pinnedList)
        const pyScript = [
            "import sys, json, os, tempfile",
            "path = sys.argv[1]",
            "pinned = json.loads(sys.argv[2])",
            "try:",
            "    with open(path, 'r', encoding='utf-8') as f:",
            "        data = json.load(f)",
            "except Exception:",
            "    data = {}",
            "if 'dock' not in data or not isinstance(data['dock'], dict):",
            "    data['dock'] = {}",
            "data['dock']['pinned'] = pinned",
            "dname = os.path.dirname(path)",
            "os.makedirs(dname, exist_ok=True)",
            "with tempfile.NamedTemporaryFile('w', dir=dname, delete=False, encoding='utf-8') as tf:",
            "    json.dump(data, tf, indent=2, ensure_ascii=False)",
            "    tf.write(chr(10))",
            "    tmp = tf.name",
            "os.replace(tmp, path)"
        ].join("\n")
        Quickshell.execDetached(["python3", "-c", pyScript, jsonPath, listStr])
    }

    function matchesApp(tl, appId, entry) {
        if (!tl) return false
        const cls = (tl.lastIpcObject && tl.lastIpcObject.class ? tl.lastIpcObject.class : "").toLowerCase()
        const initCls = (tl.lastIpcObject && tl.lastIpcObject.initialClass ? tl.lastIpcObject.initialClass : "").toLowerCase()
        const idLower = appId.toLowerCase().replace(/\.desktop$/, "")

        if (cls.length > 0 && (cls === idLower || initCls === idLower)) return true
        if (cls.length > 0 && idLower.length > 2 && (cls.includes(idLower) || idLower.includes(cls))) return true

        const pid = (tl.lastIpcObject && tl.lastIpcObject.pid) ? tl.lastIpcObject.pid : 0
        if (pid > 0 && root.instanceCache[pid]) {
            const inst = root.instanceCache[pid]
            if (inst.name && inst.name.toLowerCase() === idLower) return true
        }

        if (entry) {
            const entryId = (entry && entry.id ? entry.id : "").toLowerCase().replace(/\.desktop$/, "")
            if (entryId.length > 0 && (entryId === cls || entryId === initCls || cls.includes(entryId))) return true
            if (entry.startupClass && entry.startupClass.toLowerCase() === cls) return true
            if (entry.name && entry.name.toLowerCase() === cls) return true
            const title = (tl.lastIpcObject && tl.lastIpcObject.title ? tl.lastIpcObject.title : "").toLowerCase()
            if (entryId.length > 2 && title.length > 0 && (title.includes(entryId) || entryId.includes(title))) return true
        }
        return false
    }

    function extractActions(entry) {
        if (!entry || !entry.actions) return []
        const list = []
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
        return list
    }

    function buildPinnedModel() {
        const toplevels = hypr.toplevels.values ?? []
        const pinnedList = config.dock.pinned ?? []

        // 1. Build Pinned Model
        const newPinned = []
        for (const pinnedId of pinnedList) {
            const entry = QsServices.IconResolver.lookupDesktopEntry(pinnedId)

            // Find all open windows matching this pinned app
            const matchingWins = toplevels.filter(tl => matchesApp(tl, pinnedId, entry))
            const acts = extractActions(entry)

            newPinned.push({
                id: pinnedId,
                name: (entry && entry.name) ? entry.name : pinnedId,
                entry: entry,
                icon: (entry && entry.icon) ? entry.icon : pinnedId,
                windows: matchingWins,
                isPinned: true,
                actions: acts
            })
        }
        return newPinned
    }

    function buildRunningModel(pinned) {
        // 2. Build Running Unpinned Model
        if (!config.dock.showRunning) {
            return []
        }

        const toplevels = hypr.toplevels.values ?? []
        const unpinned = []
        const handledClasses = new Set()

        for (const tl of toplevels) {
            const cls = (tl.lastIpcObject && tl.lastIpcObject.class ? tl.lastIpcObject.class : "")
            if (!cls || handledClasses.has(cls.toLowerCase())) continue

            // Check if already represented in pinned apps
            let isPinned = false
            for (const p of pinned) {
                if (matchesApp(tl, p.id, p.entry)) {
                    isPinned = true
                    break
                }
            }
            if (isPinned) continue

            handledClasses.add(cls.toLowerCase())

            const wins = toplevels.filter(w => ((w.lastIpcObject && w.lastIpcObject.class ? w.lastIpcObject.class : "").toLowerCase() === cls.toLowerCase()))
            const entry = QsServices.IconResolver.lookupDesktopEntry(cls)
            const acts = extractActions(entry)

            let appName = (entry && entry.name) ? entry.name : cls
            let appIcon = (entry && entry.icon) ? entry.icon : cls

            // Universal dynamic resolution for custom apps, scripts, or games without standard desktop entries
            const pid = (wins[0] && wins[0].lastIpcObject && wins[0].lastIpcObject.pid) ? wins[0].lastIpcObject.pid : 0
            const winTitle = (wins[0] && wins[0].lastIpcObject && wins[0].lastIpcObject.title) ? wins[0].lastIpcObject.title : ""
            const hasResolvedIcon = QsServices.IconResolver.tryIconName(appIcon).length > 0
            const isGenericClass = !entry || !entry.icon || !hasResolvedIcon || cls.toLowerCase().startsWith("python") || cls.toLowerCase().startsWith("java") || cls.toLowerCase().includes("minecraft") || cls.toLowerCase().includes("mojang")

            if (pid > 0 && isGenericClass) {
                if (root.instanceCache[pid]) {
                    const inst = root.instanceCache[pid]
                    if (inst.name && inst.name.length > 0) appName = inst.name
                    if (inst.icon && inst.icon.length > 0) appIcon = inst.icon
                } else {
                    root.requestInstanceResolution(pid, winTitle, cls)
                }
            }

            unpinned.push({
                id: cls,
                name: appName,
                entry: entry,
                icon: appIcon,
                windows: wins,
                isPinned: false,
                actions: acts
            })
        }
        return unpinned
    }

    function sameItemIdentity(a, b) {
        if (!a || !b) return false
        return a.id === b.id
            && a.name === b.name
            && a.icon === b.icon
            && a.isPinned === b.isPinned
            && ((a.entry && a.entry.id) ? a.entry.id : "") === ((b.entry && b.entry.id) ? b.entry.id : "")
    }

    function sameWindowList(w1, w2) {
        const a = w1 || []
        const b = w2 || []
        if (a.length !== b.length) return false
        for (let i = 0; i < a.length; i++) {
            if (a[i].address !== b[i].address
                || a[i].title !== b[i].title
                || Boolean(a[i].activated) !== Boolean(b[i].activated)) {
                return false
            }
        }
        return true
    }

    function applyModelUpdate(currentList, nextList) {
        if (!Array.isArray(currentList) || currentList.length !== nextList.length) {
            return { list: nextList, replaced: true, changed: true }
        }
        for (let i = 0; i < nextList.length; i++) {
            if (!sameItemIdentity(currentList[i], nextList[i])) {
                return { list: nextList, replaced: true, changed: true }
            }
        }
        let changed = false
        for (let i = 0; i < nextList.length; i++) {
            const cur = currentList[i]
            const nxt = nextList[i]
            if (!sameWindowList(cur.windows, nxt.windows)) {
                cur.windows = nxt.windows
                changed = true
            }
            if (cur.entry !== nxt.entry) {
                cur.entry = nxt.entry
                changed = true
            }
            cur.actions = nxt.actions
        }
        return { list: currentList, replaced: false, changed: changed }
    }

    function updateDockItems() {
        // Avoid tearing down Repeater delegates mid-drag or while steady-state items are hovered
        if (root.isDraggingActive) return

        const newPinned = buildPinnedModel()
        const newRunning = buildRunningModel(newPinned)

        const pinnedRes = applyModelUpdate(root.pinnedModel, newPinned)
        if (pinnedRes.replaced) {
            root.pinnedModel = pinnedRes.list
        }

        const runningRes = applyModelUpdate(root.runningModel, newRunning)
        if (runningRes.replaced) {
            root.runningModel = runningRes.list
        }

        if (pinnedRes.changed || runningRes.changed) {
            root.dockStateRevision++
        }
    }

    Component.onCompleted: {
        updateDockItems()
    }

    // React to window structure or focus changes
    Connections {
        target: hypr
        function onToplevelsRefreshed() { root.updateDockItems() }
        function onWorkspacesRefreshed() { root.updateDockItems() }
    }

    Timer {
        id: desktopRefreshTimer
        interval: 50
        running: false
        repeat: false
        onTriggered: root.updateDockItems()
    }

    // React to desktop entry changes (debounced during initial bulk scan)
    Connections {
        target: DesktopEntries
        function onApplicationsChanged() { desktopRefreshTimer.restart() }
    }
    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { desktopRefreshTimer.restart() }
    }

    // React to configuration changes (e.g. pinned list reload)
    Connections {
        target: config.dock
        function onPinnedChanged() { root.updateDockItems() }
    }

    // Re-check during startup settling phase before surfaces are revealed
    Timer {
        interval: 200
        running: true
        repeat: false
        onTriggered: root.updateDockItems()
    }

    // Periodic safety check to ensure dock stays synchronized with live windows
    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: root.updateDockItems()
    }

    // Main Dock Surface (Pill shape matching Bar.qml)
    AuroraSurface {
        id: surface
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        height: config.dock.height
        width: contentRow.implicitWidth + 18

        radius: config.dock.borderRadius
        color: pywal.surfaceContainerHigh
        strokeColor: pywal.outlineVariant
        borderWidth: 1
        accentColor: pywal.primary
        elevation: 4

        Behavior on color {
            enabled: QsServices.UIState.animationsEnabled
            ColorAnimation { duration: 300; easing.type: Easing.OutCubic }
        }

        HoverHandler {
            id: dockHoverHandler
        }

        MouseArea {
            anchors.fill: parent
            z: -1
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onClicked: root.closeContextMenu()
        }

        RowLayout {
            id: contentRow
            anchors.centerIn: parent
            spacing: config.dock.spacing

            // Section 1: Launcher Button
            LauncherButton {
                id: launcherBtn
                Layout.alignment: Qt.AlignVCenter
                launcher: root.launcher
                dock: root
            }

            // Separator 1
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                width: 1
                height: 18
                radius: 0.5
                color: Qt.rgba(pywal.foreground.r, pywal.foreground.g, pywal.foreground.b, 0.14)
            }

            // Section 2: Pinned Applications
            Item {
                id: pinnedContainer
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: pinnedRow.implicitWidth
                implicitHeight: pinnedRow.implicitHeight
                z: (root.isDraggingActive && root.dragSourceIsPinned) ? 100 : 1

                Row {
                    id: pinnedRow
                    spacing: config.dock.spacing

                    Repeater {
                        id: pinnedRepeater
                        model: root.pinnedModel

                        delegate: DockItem {
                            required property var modelData
                            required property int index
                            Layout.alignment: Qt.AlignVCenter
                            itemData: modelData
                            itemIndex: index
                            isPinnedSection: true
                            dock: root
                        }
                    }
                }
            }

            // Separator 2 (visible only if there are unpinned running apps)
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: runningRepeater.count > 0
                width: 1
                height: 18
                radius: 0.5
                color: Qt.rgba(pywal.foreground.r, pywal.foreground.g, pywal.foreground.b, 0.14)
            }

            // Section 3: Running Unpinned Applications
            Item {
                id: runningContainer
                visible: runningRepeater.count > 0
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: runningRow.implicitWidth
                implicitHeight: runningRow.implicitHeight
                z: (root.isDraggingActive && !root.dragSourceIsPinned) ? 100 : 1

                Row {
                    id: runningRow
                    spacing: config.dock.spacing

                    Repeater {
                        id: runningRepeater
                        model: root.runningModel

                        delegate: DockItem {
                            required property var modelData
                            required property int index
                            Layout.alignment: Qt.AlignVCenter
                            itemData: modelData
                            itemIndex: index
                            isPinnedSection: false
                            dock: root
                        }
                    }
                }
            }
        }
    }
}
