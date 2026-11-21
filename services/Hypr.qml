pragma Singleton

import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick 6.10

Singleton {
    id: root

    signal workspacesRefreshed()
    signal toplevelsRefreshed()

    readonly property var rawToplevels: Hyprland.toplevels
    readonly property var workspaces: Hyprland.workspaces
    readonly property var monitors: Hyprland.monitors

    readonly property var activeToplevel: Hyprland.activeToplevel
    readonly property var focusedWorkspace: Hyprland.focusedWorkspace
    readonly property var focusedMonitor: Hyprland.focusedMonitor
    readonly property int activeWsId: (focusedWorkspace && focusedWorkspace.id !== undefined) ? focusedWorkspace.id : 1

    property var verifiedToplevels: []
    property var closedAddresses: new Map()
    property bool isProcRunning: false
    property bool needsRerun: false

    QtObject {
        id: toplevelsObj
        readonly property var values: root.verifiedToplevels
    }
    readonly property alias toplevels: toplevelsObj

    function normalizeAddr(addr) {
        if (!addr) return ""
        let s = String(addr).toLowerCase().trim()
        if (s.startsWith("0x")) s = s.slice(2)
        return s
    }

    function requestClientsRefresh() {
        if (clientsProc.running || isProcRunning) {
            needsRerun = true
            return
        }
        isProcRunning = true
        clientsProc.running = true
    }

    Process {
        id: clientsProc
        command: ["hyprctl", "-j", "clients"]
        running: false

        onExited: (exitCode, exitStatus) => {
            root.isProcRunning = false
        }

        stdout: StdioCollector {
            onStreamFinished: {
                root.isProcRunning = false
                root.parseClientsJson(text)
                if (root.needsRerun) {
                    root.needsRerun = false
                    root.requestClientsRefresh()
                }
            }
        }
    }

    function parseClientsJson(rawJson) {
        if (!rawJson || rawJson.trim().length === 0) return
        try {
            const list = JSON.parse(rawJson)
            if (!Array.isArray(list)) return

            const liveMap = new Map()
            const liveAddrs = new Set()

            for (const c of list) {
                if (c.mapped === false) continue
                const norm = normalizeAddr(c.address)
                if (!norm || root.closedAddresses.has(norm)) continue
                liveAddrs.add(norm)
                liveMap.set(norm, c)
            }

            // Prune closedAddresses that no longer exist in Hyprland at all, or that are older than 5000ms
            const now = Date.now()
            const stillExisting = new Set()
            for (const c of list) {
                stillExisting.add(normalizeAddr(c.address))
            }
            for (const [closedAddr, timestamp] of root.closedAddresses.entries()) {
                if (!stillExisting.has(closedAddr) || (now - timestamp > 5000)) {
                    root.closedAddresses.delete(closedAddr)
                }
            }

            const qsList = (Hyprland.toplevels && Hyprland.toplevels.values) ? Hyprland.toplevels.values : []
            const activeAddr = normalizeAddr((Hyprland.activeToplevel && Hyprland.activeToplevel.address) ? Hyprland.activeToplevel.address : "")
            const verified = []

            for (const norm of liveAddrs) {
                const client = liveMap.get(norm)
                let qsTl = null
                for (const tl of qsList) {
                    if (tl && normalizeAddr(tl.address) === norm) {
                        qsTl = tl
                        break
                    }
                }

                const isActive = (activeAddr.length > 0 && norm === activeAddr) || ((qsTl && qsTl.activated) ? true : false)
                const winTitle = (client.title && client.title.length > 0) ? client.title : ((qsTl && qsTl.title) ? qsTl.title : "")

                const ipcObj = {
                    address: client.address,
                    class: client.class ? client.class : "",
                    initialClass: client.initialClass ? client.initialClass : (client.class ? client.class : ""),
                    title: winTitle,
                    initialTitle: client.initialTitle ? client.initialTitle : winTitle,
                    workspace: client.workspace ? client.workspace : {},
                    pid: (client.pid !== undefined) ? client.pid : 0,
                    mapped: (client.mapped !== undefined) ? client.mapped : true,
                    hidden: (client.hidden !== undefined) ? client.hidden : false,
                    floating: (client.floating !== undefined) ? client.floating : false,
                    monitor: (client.monitor !== undefined) ? client.monitor : 0
                }

                verified.push({
                    address: client.address,
                    rawAddress: norm,
                    title: winTitle,
                    activated: isActive,
                    lastIpcObject: ipcObj,
                    workspace: client.workspace,
                    wayland: (qsTl && qsTl.wayland) ? qsTl.wayland : null
                })
            }

            root.verifiedToplevels = verified
            root.toplevelsRefreshed()
        } catch (e) {
            console.error("Hypr parseClientsJson error:", e)
        }
    }

    function initFromQsToplevels() {
        const qsList = (Hyprland.toplevels && Hyprland.toplevels.values) ? Hyprland.toplevels.values : []
        if (qsList.length === 0) return
        const activeAddr = normalizeAddr((Hyprland.activeToplevel && Hyprland.activeToplevel.address) ? Hyprland.activeToplevel.address : "")
        const verified = []
        for (const tl of qsList) {
            if (!tl) continue
            const norm = normalizeAddr(tl.address)
            if (!norm || root.closedAddresses.has(norm)) continue
            const isActive = (activeAddr.length > 0 && norm === activeAddr) || ((tl && tl.activated) ? true : false)
            const ipcObj = (tl && tl.lastIpcObject) ? tl.lastIpcObject : {}
            const winTitle = (tl.title && tl.title.length > 0) ? tl.title : (ipcObj.title ? ipcObj.title : "")
            verified.push({
                address: tl.address,
                rawAddress: norm,
                title: winTitle,
                activated: isActive,
                lastIpcObject: {
                    address: tl.address,
                    class: ipcObj.class ? ipcObj.class : "",
                    initialClass: ipcObj.initialClass ? ipcObj.initialClass : (ipcObj.class ? ipcObj.class : ""),
                    title: winTitle,
                    initialTitle: ipcObj.initialTitle ? ipcObj.initialTitle : winTitle,
                    workspace: ipcObj.workspace ? ipcObj.workspace : (tl.workspace ? tl.workspace : {}),
                    pid: (ipcObj.pid !== undefined) ? ipcObj.pid : 0,
                    mapped: (ipcObj.mapped !== undefined) ? ipcObj.mapped : true,
                    hidden: (ipcObj.hidden !== undefined) ? ipcObj.hidden : false,
                    floating: (ipcObj.floating !== undefined) ? ipcObj.floating : false,
                    monitor: (ipcObj.monitor !== undefined) ? ipcObj.monitor : 0
                },
                workspace: tl.workspace,
                wayland: (tl && tl.wayland) ? tl.wayland : null
            })
        }
        if (verified.length > 0) {
            root.verifiedToplevels = verified
            root.toplevelsRefreshed()
        }
    }

    Timer {
        id: periodicSyncTimer
        interval: 2000
        running: true
        repeat: true
        onTriggered: root.requestClientsRefresh()
    }

    Component.onCompleted: {
        Hyprland.refreshWorkspaces()
        Hyprland.refreshMonitors()
        Hyprland.refreshToplevels()
        root.initFromQsToplevels()
        root.requestClientsRefresh()
        root.workspacesRefreshed()
        root.toplevelsRefreshed()
    }

    function dispatch(request) {
        if (request.startsWith("workspace ")) {
            const ws = request.slice(10).trim()
            if (Hyprland.usingLua) {
                Hyprland.dispatch(`hl.dsp.focus({ workspace = '${ws}' })`)
            } else {
                Hyprland.dispatch(`workspace ${ws}`)
            }
            return
        }
        Hyprland.dispatch(request)
    }

    function focusWindow(address) {
        if (!address) return
        const addr = address.startsWith("0x") ? address : `0x${address}`
        if (Hyprland.usingLua) {
            Hyprland.dispatch(`hl.dsp.focus({ window = 'address:${addr}' })`)
        } else {
            Hyprland.dispatch(`focuswindow address:${addr}`)
        }
    }

    function closeWindow(address) {
        if (!address) return
        const norm = normalizeAddr(address)
        if (norm.length > 0) {
            root.closedAddresses.set(norm, Date.now())
            root.verifiedToplevels = root.verifiedToplevels.filter(w => normalizeAddr(w.address) !== norm)
            root.toplevelsRefreshed()
        }

        const addr = address.startsWith("0x") ? address : `0x${address}`
        if (Hyprland.usingLua) {
            Hyprland.dispatch(`hl.dsp.window.close({ window = 'address:${addr}' })`)
        } else {
            Hyprland.dispatch(`closewindow address:${addr}`)
        }
        root.requestClientsRefresh()
    }

    function focusWorkspace(workspaceId) {
        if (Hyprland.usingLua) {
            Hyprland.dispatch(`hl.dsp.focus({ workspace = '${workspaceId}' })`)
        } else {
            Hyprland.dispatch(`workspace ${workspaceId}`)
        }
    }

    function monitorFor(screen) {
        return Hyprland.monitorFor(screen)
    }

    // Get occupied workspaces (workspaces with windows)
    function getOccupiedWorkspaces() {
        const occupied = {}
        for (const ws of workspaces.values) {
            occupied[ws.id] = (ws.lastIpcObject && ws.lastIpcObject.windows !== undefined) ? (ws.lastIpcObject.windows > 0) : false
        }
        return occupied
    }

    // Event-driven updates from Hyprland socket2
    Connections {
        target: Hyprland

        function onRawEvent(event) {
            const n = event.name
            const data = event.data ?? ""

            if (n === "closewindow") {
                const addr = root.normalizeAddr(data)
                if (addr.length > 0) {
                    root.closedAddresses.set(addr, Date.now())
                    root.verifiedToplevels = root.verifiedToplevels.filter(w => root.normalizeAddr(w.address) !== addr)
                    root.toplevelsRefreshed()
                }
                Hyprland.refreshWorkspaces()
                root.workspacesRefreshed()
                root.requestClientsRefresh()
                return
            }

            if (n.endsWith("v2"))
                return

            // Target refreshes based on event type
            if (["workspace", "moveworkspace", "activespecial", "focusedmon", "destroyworkspace", "createworkspace", "renameworkspace"].includes(n)) {
                Hyprland.refreshWorkspaces()
                Hyprland.refreshMonitors()
                root.workspacesRefreshed()
                root.requestClientsRefresh()
            } else if (["activewindow"].includes(n)) {
                Hyprland.refreshMonitors()
                root.requestClientsRefresh()
            } else if (n === "openwindow") {
                const parts = (data || "").split(",")
                const openAddr = root.normalizeAddr(parts[0])
                if (openAddr.length > 0) {
                    root.closedAddresses.delete(openAddr)
                }
                Hyprland.refreshToplevels()
                Hyprland.refreshWorkspaces()
                root.workspacesRefreshed()
                root.requestClientsRefresh()
            } else if (n === "movewindow") {
                Hyprland.refreshWorkspaces()
                root.workspacesRefreshed()
                root.requestClientsRefresh()
            } else if (n === "windowtitle") {
                root.requestClientsRefresh()
            }
        }
    }
}
