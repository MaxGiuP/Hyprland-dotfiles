import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.waffle.looks
import qs.modules.waffle.notificationCenter

Scope {
    id: notificationPopup

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: root
            required property var modelData
            readonly property string screenName: modelData?.name ?? ""
            readonly property bool tvModeVisible: HyprlandData.monitorShowsTvModeWorkspace(screenName)
            readonly property bool fullscreenOnMonitor: HyprlandData.monitorShouldSuppressShell(screenName)

            readonly property bool popupsVisible: (Notifications.popupList.length > 0) && !GlobalStates.screenLocked && !tvModeVisible

            // Unmapping even a non-focusable layer makes Hyprland refocus
            // under the pointer. Keep the surface mapped between popups.
            visible: true
            screen: modelData

            WlrLayershell.namespace: "quickshell:notificationPopup"
            // An empty surface must not obstruct fullscreen presentation.
            WlrLayershell.layer: popupsVisible ? WlrLayer.Overlay : WlrLayer.Bottom
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusiveZone: 0

            anchors {
                top: true
                right: true
                bottom: true
            }

            mask: Region {
                // Keep popup hitboxes out of a fullscreen app's mouse input.
                item: root.popupsVisible && !root.fullscreenOnMonitor ? listview.contentItem : null
            }

            color: "transparent"
            implicitWidth: listview.implicitWidth

            WListView {
                id: listview
                visible: root.popupsVisible
                anchors {
                    bottom: parent.bottom
                    right: parent.right
                    left: parent.left
                }
                leftMargin: 16
                rightMargin: 16
                topMargin: 16
                bottomMargin: 16

                height: Math.min(contentItem.height + topMargin + bottomMargin, parent.height)
                width: parent.width - Appearance.sizes.elevationMargin * 2

                implicitWidth: 396
                spacing:12

                model: ScriptModel {
                    values: Notifications.popupList
                }
                delegate: WSingleNotification {
                    required property var modelData
                    notification: modelData
                    width: ListView.view.width - ListView.view.leftMargin - ListView.view.rightMargin
                }
            }
        }
    }
}
