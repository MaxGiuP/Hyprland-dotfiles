pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.modules.common
import qs.services
import qs.modules.ii.overlay
import qs.modules.ii.systemApps as SystemApps

StyledOverlayWidget {
    id: root

    title: Translation.tr("System Dashboard")
    showCenterButton: true
    minimumWidth: 760
    minimumHeight: 580

    Component.onCompleted: {
        dashboard.currentTab = Math.max(0, Math.min(4, Number(root.persistentStateEntry.currentTab ?? 0)))
    }

    contentItem: OverlayBackground {
        radius: root.contentRadius

        SystemApps.SystemDashboard {
            id: dashboard
            anchors.fill: parent
            anchors.margins: 8
            onCurrentTabChanged: {
                if (Persistent.ready)
                    root.persistentStateEntry.currentTab = currentTab
            }
        }
    }
}
