pragma ComponentBehavior: Bound

import qs.modules.common.widgets
import qs.services
import QtQuick
import Quickshell

StyledListView { // Scrollable window
    id: root
    property bool popup: false
    property var customAppNameList: null
    property var customGroupsByAppName: null

    spacing: 3

    model: ScriptModel {
        values: root.customAppNameList !== null ? root.customAppNameList :
                (root.popup ? Notifications.popupAppNameList : Notifications.appNameList)
    }
    delegate: NotificationGroup {
        required property int index
        required property var modelData
        popup: root.popup
        width: ListView.view.width // https://doc.qt.io/qt-6/qml-qtquick-listview.html
        notificationGroup: {
            const groups = root.customGroupsByAppName !== null ? root.customGroupsByAppName :
                           (popup ? Notifications.popupGroupsByAppName : Notifications.groupsByAppName);
            return groups[modelData];
        }
    }
}
