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

            visible: (Notifications.popupList.length > 0) && !GlobalStates.screenLocked
            screen: modelData

            WlrLayershell.namespace: "quickshell:notificationPopup"
            WlrLayershell.layer: WlrLayer.Overlay
            exclusiveZone: 0

            anchors {
                top: true
                right: true
                bottom: true
            }

            mask: Region {
                item: listview.contentItem
            }

            color: "transparent"
            implicitWidth: Appearance.sizes.notificationPopupWidth

            NotificationListView {
                id: listview
                anchors {
                    top: parent.top
                    bottom: parent.bottom
                    right: parent.right
                    rightMargin: 4
                    topMargin: 4
                }
                implicitWidth: parent.width - Appearance.sizes.elevationMargin * 2
                popup: true
            }
        }
    }
}
