pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.modules.common
import qs.services
import qs.modules.ii.overlay
import qs.modules.ii.sidebarRight.pomodoro as Pomodoro

StyledOverlayWidget {
    id: root

    title: Translation.tr("Timers")
    showCenterButton: true
    minimumWidth: 500
    minimumHeight: 440

    function focusTimers() {
        timers.forceActiveFocus()
    }

    Component.onCompleted: {
        timers.currentTab = Math.max(0, Math.min(2, Number(root.persistentStateEntry.currentTab ?? 0)))
        if (GlobalStates.overlayOpen)
            Qt.callLater(root.focusTimers)
    }

    contentItem: OverlayBackground {
        radius: root.contentRadius

        TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: Qt.callLater(root.focusTimers)
        }

        Pomodoro.PomodoroWidget {
            id: timers
            anchors.fill: parent
            anchors.margins: 10
            focus: true
            onCurrentTabChanged: {
                if (Persistent.ready)
                    root.persistentStateEntry.currentTab = currentTab
            }
        }
    }
}
