import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: root
    property var tabButtonList: [
        {"icon": "event", "name": Translation.tr("Events")},
        {"name": Translation.tr("Tasks"), "icon": "assignment"}
    ]
    readonly property int dayMs: 24 * 60 * 60 * 1000
    property var thunderbirdTasks: RemoteCalendarBridge.thunderbirdTasks
    property var thunderbirdEvents: RemoteCalendarBridge.thunderbirdEvents
    property string lastError: RemoteCalendarBridge.lastError
    readonly property bool loading: RemoteCalendarBridge.loading
    readonly property bool hasAnyData: root.thunderbirdEvents.length > 0 || root.thunderbirdTasks.length > 0
    property real focusedDayStartMs: RemoteCalendarBridge.focusedDayStartMs
    property real focusedDayEndMs: RemoteCalendarBridge.focusedDayEndMs
    property string selectedEventExternalId: RemoteCalendarBridge.selectedEventExternalId
    property string selectedEventCalId: RemoteCalendarBridge.selectedEventCalId

    onFocusedDayStartMsChanged: {
        if (root.focusedDayStartMs >= 0 && root.focusedDayEndMs > root.focusedDayStartMs) {
            tabBar.setCurrentIndex(0);
            const firstMatch = root.mergedEventList.find(item =>
                (parseInt(item?.dueAt ?? 0) || 0) >= root.focusedDayStartMs
                && (parseInt(item?.dueAt ?? 0) || 0) < root.focusedDayEndMs
            );
            if (firstMatch)
                RemoteCalendarBridge.selectEvent(firstMatch);
        }
    }

    readonly property var sortedImportedTaskList: {
        return root.thunderbirdTasks
            .map(item => Object.assign({}, item, {
                originalIndex: -1,
                readOnly: true,
                source: "thunderbird",
            }))
            .sort((a, b) => {
                const aDue = parseInt(a?.dueAt ?? 0) || 0;
                const bDue = parseInt(b?.dueAt ?? 0) || 0;
                if (a.done !== b.done) return a.done ? 1 : -1;
                if (aDue === 0 && bDue > 0) return 1;
                if (bDue === 0 && aDue > 0) return -1;
                if (aDue !== bDue) return aDue - bDue;
                return `${a.content}`.localeCompare(`${b.content}`);
            });
    }

    readonly property var mergedEventList: {
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        let minTs = today.getTime();
        let maxTs = minTs + (7 * root.dayMs);
        if (root.focusedDayStartMs >= 0 && root.focusedDayEndMs > root.focusedDayStartMs) {
            minTs = Math.min(minTs, root.focusedDayStartMs);
            maxTs = Math.max(maxTs, root.focusedDayEndMs);
        }

        return root.thunderbirdEvents
            .map(event => ({
                content: event.title ?? "",
                title: event.title ?? "",
                description: "",
                dueAt: parseInt(event?.startAt ?? 0) || 0,
                endAt: parseInt(event?.endAt ?? 0) || 0,
                allDay: !!event?.allDay,
                done: false,
                readOnly: true,
                source: "thunderbird-event",
                originalIndex: -1,
                externalId: `${event?.externalId ?? ""}`,
                calId: `${event?.calId ?? ""}`,
                calendarName: `${event?.calendarName ?? ""}`,
            }))
            .filter(item =>
                item.dueAt >= minTs
                && item.dueAt < maxTs
                && `${item.content}`.trim().length > 0
            )
            .sort((a, b) => {
                if ((a.dueAt ?? 0) !== (b.dueAt ?? 0))
                    return (a.dueAt ?? 0) - (b.dueAt ?? 0);
                return `${a.content}`.localeCompare(`${b.content}`);
            });
    }

    Keys.onPressed: (event) => {
        if ((event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) && event.modifiers === Qt.NoModifier) {
            if (event.key === Qt.Key_PageDown)
                tabBar.incrementCurrentIndex();
            else if (event.key === Qt.Key_PageUp)
                tabBar.decrementCurrentIndex();
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

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: 6
            visible: root.lastError.length > 0
            text: root.lastError
            wrapMode: Text.Wrap
            color: Appearance.colors.colError
            font.pixelSize: Appearance.font.pixelSize.smaller
        }

        RowLayout {
            Layout.topMargin: root.lastError.length > 0 ? 6 : 0
            Layout.alignment: Qt.AlignHCenter
            spacing: 10
            visible: root.loading

            MaterialLoadingIndicator {
                implicitSize: 22
                loading: root.loading
            }

            StyledText {
                text: root.hasAnyData ? Translation.tr("Refreshing calendar data") : Translation.tr("Loading calendar data")
                color: Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.small
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
            visible: !root.loading || root.hasAnyData

            TaskList {
                listBottomPadding: 16
                emptyPlaceholderIcon: "event"
                emptyPlaceholderText: Translation.tr("No calendar events")
                taskList: root.mergedEventList
                highlightDayStartMs: root.focusedDayStartMs
                highlightDayEndMs: root.focusedDayEndMs
                autoScrollToHighlight: true
                accentHighlightMatches: true
                selectionEnabled: true
                selectedExternalId: root.selectedEventExternalId
                selectedCalId: root.selectedEventCalId
                onItemActivated: item => RemoteCalendarBridge.selectEvent(item)
            }

            TaskList {
                listBottomPadding: 16
                emptyPlaceholderIcon: "assignment"
                emptyPlaceholderText: Translation.tr("No calendar tasks")
                taskList: root.sortedImportedTaskList
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.loading && !root.hasAnyData
        }
    }
}
