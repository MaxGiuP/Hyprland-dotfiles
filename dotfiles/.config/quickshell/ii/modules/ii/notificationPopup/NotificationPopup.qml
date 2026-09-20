import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland

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

            visible: (Notifications.popupList.length > 0) && !GlobalStates.screenLocked && !tvModeVisible
            screen: modelData

            WlrLayershell.namespace: "quickshell:notificationPopup"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusiveZone: 0

            anchors {
                top: true
                right: true
                bottom: true
            }

            mask: Region {
                // Keep popup hitboxes out of a fullscreen app's mouse input.
                item: root.fullscreenOnMonitor ? null : listview.contentItem
            }

            color: "transparent"
            implicitWidth: Appearance.sizes.notificationPopupWidth

            NotificationListView {
                id: listview
                // Keep dismissing notifications from bleeding into the
                // screen-edge buffer while they animate to the right.
                clip: true
                anchors {
                    top: parent.top
                    bottom: parent.bottom
                    right: parent.right
                    rightMargin: Appearance.sizes.elevationMargin
                    topMargin: 4
                }
                implicitWidth: parent.width - Appearance.sizes.elevationMargin * 2
                popup: true
            }
        }
    }
}
