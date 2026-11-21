import Quickshell
import Quickshell.Wayland
import QtQuick 6.10
import "."
import "../../config" as QsConfig
import "../../services" as QsServices

Scope {
    id: root

    readonly property var config: QsConfig.Config

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: dockWindow

            property var modelData
            screen: modelData

            anchors {
                bottom: true
            }

            margins {
                bottom: config.dock.marginBottom
            }

            // Reserve space at bottom so tiled windows don't overlap the dock (matching -x)
            exclusiveZone: config.dock.exclusive ? (config.dock.height + config.dock.marginBottom) : 0

            implicitWidth: dock.implicitWidth
            implicitHeight: (dock.surfaceItem ? dock.surfaceItem.height : config.dock.height) + 48
            color: "transparent"

            WlrLayershell.namespace: "quickshell-dock"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: (contextMenu && contextMenu.shouldShow) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

            mask: Region {
                item: (dock.isDraggingActive) ? dock : dock.surfaceItem
            }

            Dock {
                id: dock
                anchors.fill: parent
                screen: modelData
                dockWindow: dockWindow
                opacity: QsServices.UIState.startupComplete ? 1.0 : 0.0
                enabled: QsServices.UIState.startupComplete
            }

            DockContextMenu {
                id: contextMenu
                dockWindow: dockWindow
                dock: dock

                onShouldShowChanged: {
                    dock.isMenuOpen = shouldShow
                }
            }

            Connections {
                target: dock
                function onContextMenuRequested(targetItem, itemData, type) {
                    contextMenu.openMenu(targetItem, itemData, type)
                }
                function onCloseContextMenuRequested() {
                    contextMenu.closeMenu()
                }
            }
        }
    }
}
