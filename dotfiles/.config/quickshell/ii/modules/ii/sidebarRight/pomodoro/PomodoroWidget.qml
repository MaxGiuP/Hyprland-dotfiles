import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    property var tabButtonList: [
        {"name": Translation.tr("Countdown"), "icon": "hourglass_top"},
        {"name": Translation.tr("Stopwatch"), "icon": "timer"},
        {"name": Translation.tr("Pomodoro"), "icon": "search_activity"}
    ]

    Keys.onPressed: event => {
        if ((event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) && event.modifiers === Qt.NoModifier) {
            if (event.key === Qt.Key_PageDown) {
                tabBar.incrementCurrentIndex();
            } else if (event.key === Qt.Key_PageUp) {
                tabBar.decrementCurrentIndex();
            }
            event.accepted = true;
        } else if (event.key === Qt.Key_Space || event.key === Qt.Key_S) {
            if (tabBar.currentIndex === 0) {
                TimerService.toggleCountdown();
            } else if (tabBar.currentIndex === 1) {
                TimerService.toggleStopwatch();
            } else {
                TimerService.togglePomodoro();
            }
            event.accepted = true;
        } else if (event.key === Qt.Key_R) {
            if (tabBar.currentIndex === 0) {
                TimerService.resetCountdown();
            } else if (tabBar.currentIndex === 1) {
                TimerService.stopwatchReset();
            } else {
                TimerService.resetPomodoro();
            }
            event.accepted = true;
        } else if (event.key === Qt.Key_L && tabBar.currentIndex === 1) {
            TimerService.stopwatchRecordLap();
            event.accepted = true;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        SecondaryTabBar {
            id: tabBar
            currentIndex: swipeView.currentIndex

            Repeater {
                model: root.tabButtonList
                delegate: SecondaryTabButton {
                    buttonText: modelData.name
                    buttonIcon: modelData.icon
                }
            }
        }

        SwipeView {
            id: swipeView
            Layout.topMargin: 10
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10
            clip: true
            currentIndex: tabBar.currentIndex

            CountdownTimer {}
            Stopwatch {}
            PomodoroTimer {}
        }
    }
}
