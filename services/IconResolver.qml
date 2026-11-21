pragma Singleton

import Quickshell
import QtQuick

Singleton {
    id: root

    // Try a single icon identifier/path; returns "" when not found instead of a broken default texture.
    function tryIconName(candidate) {
        if (!candidate) return ""
        const raw = String(candidate).trim()
        if (raw.length === 0) return ""
        if (raw.startsWith("file://")) return raw
        if (raw.startsWith("/")) return "file://" + raw

        const direct = Quickshell.iconPath(raw, true)
        if (direct && direct.length > 0) return direct

        const lower = raw.toLowerCase()
        if (lower !== raw) {
            const lowerHit = Quickshell.iconPath(lower, true)
            if (lowerHit && lowerHit.length > 0) return lowerHit
        }

        const stripped = raw.replace(/\.(png|svg|xpm|ico)$/i, "")
        if (stripped !== raw && stripped.length > 0) {
            const strippedHit = Quickshell.iconPath(stripped, true)
            if (strippedHit && strippedHit.length > 0) return strippedHit
            const strippedLowerHit = Quickshell.iconPath(stripped.toLowerCase(), true)
            if (strippedLowerHit && strippedLowerHit.length > 0) return strippedLowerHit
        }

        return ""
    }

    function lookupDesktopEntry(appId) {
        if (!appId) return null
        const raw = String(appId).trim()
        if (raw.length === 0) return null
        const base = raw.replace(/\.desktop$/i, "")
        const lower = base.toLowerCase()
        return DesktopEntries.heuristicLookup(raw)
            || DesktopEntries.byId(raw)
            || DesktopEntries.byId(base + ".desktop")
            || (lower !== base ? (DesktopEntries.heuristicLookup(lower) || DesktopEntries.byId(lower) || DesktopEntries.byId(lower + ".desktop")) : null)
            || null
    }

    function resolveAppIcon(item) {
        if (!item) return ""
        const entry = item.entry
        const candidates = []

        if (item.icon) candidates.push(item.icon)
        if (entry && entry.icon) candidates.push(entry.icon)
        if (entry && entry.id) candidates.push(String(entry.id).replace(/\.desktop$/i, ""))
        if (item.id) candidates.push(String(item.id).replace(/\.desktop$/i, ""))

        if (item.windows && item.windows.length > 0) {
            const ipc = item.windows[0].lastIpcObject
            if (ipc) {
                if (ipc.class) candidates.push(ipc.class)
                if (ipc.initialClass) candidates.push(ipc.initialClass)
            }
        }

        for (let i = 0; i < candidates.length; i++) {
            const resolved = tryIconName(candidates[i])
            if (resolved.length > 0) return resolved
        }
        return ""
    }
}
