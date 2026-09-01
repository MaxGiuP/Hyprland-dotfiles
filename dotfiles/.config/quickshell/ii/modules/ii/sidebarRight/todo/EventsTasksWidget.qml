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
        {"icon": "event_upcoming", "name": Translation.tr("Agenda")},
        {"name": Translation.tr("Tasks"), "icon": "assignment"},
        {"name": Translation.tr("Mail"), "icon": "mail"}
    ]
    readonly property int dayMs: 24 * 60 * 60 * 1000
    property var remoteTasks: UnifiedAgenda.remoteTasks ?? []
    property var remoteEvents: UnifiedAgenda.remoteEvents ?? []
    property string lastError: UnifiedAgenda.lastError
    readonly property bool loading: UnifiedAgenda.loading
    readonly property bool hasAnyData: UnifiedAgenda.agendaItems.length > 0 || UnifiedAgenda.recentMail.length > 0
    property real focusedDayStartMs: UnifiedAgenda.focusedDayStartMs
    property real focusedDayEndMs: UnifiedAgenda.focusedDayEndMs
    property string selectedEventExternalId: UnifiedAgenda.selectedEventExternalId
    property string selectedEventCalId: UnifiedAgenda.selectedEventCalId

    onFocusedDayStartMsChanged: {
        if (root.focusedDayStartMs >= 0 && root.focusedDayEndMs > root.focusedDayStartMs) {
            tabBar.setCurrentIndex(0);
            const firstMatch = root.mergedEventList.find(item =>
                (parseInt(item?.dueAt ?? 0) || 0) >= root.focusedDayStartMs
                && (parseInt(item?.dueAt ?? 0) || 0) < root.focusedDayEndMs
            );
            if (firstMatch)
                UnifiedAgenda.selectEvent(firstMatch);
        }
    }

    readonly property var sortedTaskList: {
        const localTasks = Todo.list.map((item, index) => Object.assign({}, item, {
            originalIndex: index,
            readOnly: false,
            source: item.source || "local",
        }));
        const importedTasks = root.remoteTasks
            .map(item => Object.assign({}, item, {
                originalIndex: -1,
                readOnly: true,
                source: "calendar-task",
                kind: "task",
            }));
        return localTasks.concat(importedTasks)
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

    readonly property var unifiedAgendaList: UnifiedAgenda.agendaItems.map(item => ({
        content: item.title,
        title: item.title,
        description: item.description || "",
        dueAt: Number(item.timestamp) || 0,
        endAt: Number(item.endAt) || 0,
        allDay: !!item.allDay,
        done: !!item.done,
        readOnly: !!item.readOnly,
        source: item.source,
        kind: item.kind,
        originalIndex: item.originalIndex,
        externalId: item.externalId || "",
        calId: item.calId || "",
        calendarName: item.account || "",
        account: item.account || "",
    }))

    readonly property var mailList: UnifiedAgenda.recentMail.map(message => ({
        content: message.title || Translation.tr("Untitled message"),
        title: message.title || Translation.tr("Untitled message"),
        description: message.author ? Translation.tr("From %1").arg(message.author) : "",
        dueAt: Number(message.timestamp) || 0,
        done: !!message.read,
        readOnly: true,
        source: "mail",
        kind: "mail",
        originalIndex: -1,
        externalId: `mail:${message.accountId}:${message.id}`,
        account: message.account || message.provider || "QuickMail",
        mailMessage: message,
    }))

    function importReadOnlyItem(item) {
        if (item.kind === "event") {
            UnifiedAgenda.addEventAsTask(item);
            return;
        }
        const externalId = `task:${item.externalId}`;
        if (!UnifiedAgenda.hasTaskForExternalId(externalId))
            Todo.addTask(item.title, item.calendarName ? Translation.tr("From %1").arg(item.calendarName) : "", item.dueAt, "calendar", { externalId, account: item.calendarName || "" });
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

        return root.remoteEvents
            .map(event => ({
                content: event.title ?? "",
                title: event.title ?? "",
                description: "",
                dueAt: parseInt(event?.startAt ?? 0) || 0,
                endAt: parseInt(event?.endAt ?? 0) || 0,
                allDay: !!event?.allDay,
                done: false,
                readOnly: true,
                source: "quickmail-event",
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
                text: root.hasAnyData ? Translation.tr("Refreshing agenda and mail") : Translation.tr("Loading agenda and mail")
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
                emptyPlaceholderIcon: "event_available"
                emptyPlaceholderText: Translation.tr("Your agenda is clear")
                taskList: root.unifiedAgendaList
                highlightDayStartMs: root.focusedDayStartMs
                highlightDayEndMs: root.focusedDayEndMs
                autoScrollToHighlight: true
                accentHighlightMatches: true
                selectionEnabled: true
                readOnlyActionIcon: "add_task"
                selectedExternalId: root.selectedEventExternalId
                selectedCalId: root.selectedEventCalId
                onItemActivated: item => {
                    if (item.kind === "event")
                        UnifiedAgenda.selectEvent(item);
                }
                onReadOnlyAction: item => root.importReadOnlyItem(item)
            }

            TaskList {
                listBottomPadding: 16
                emptyPlaceholderIcon: "assignment"
                emptyPlaceholderText: Translation.tr("No tasks")
                taskList: root.sortedTaskList
                readOnlyActionIcon: "add_task"
                onReadOnlyAction: item => root.importReadOnlyItem(item)
            }

            TaskList {
                listBottomPadding: 16
                emptyPlaceholderIcon: "mark_email_read"
                emptyPlaceholderText: Translation.tr("No recent inbox messages")
                taskList: root.mailList
                readOnlyActionIcon: "add_task"
                onReadOnlyAction: item => UnifiedAgenda.addMailAsTask(item.mailMessage)
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.loading && !root.hasAnyData
        }
    }
}
