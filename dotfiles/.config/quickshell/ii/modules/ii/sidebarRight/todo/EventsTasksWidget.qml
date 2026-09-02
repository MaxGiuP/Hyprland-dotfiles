import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../calendar/agenda_dates.js" as AgendaDates
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
    property var remoteTasks: UnifiedAgenda.remoteTasks ?? []
    property var remoteEvents: UnifiedAgenda.remoteEvents ?? []
    property string lastError: UnifiedAgenda.mutationError || UnifiedAgenda.lastError
    readonly property bool loading: UnifiedAgenda.loading
    readonly property bool hasAnyData: UnifiedAgenda.agendaItems.length > 0
        || root.remoteEvents.length > 0
        || root.remoteTasks.length > 0
        || UnifiedAgenda.recentMail.length > 0
    property real focusedDayStartMs: UnifiedAgenda.focusedDayStartMs
    property real focusedDayEndMs: UnifiedAgenda.focusedDayEndMs
    property string selectedEventExternalId: UnifiedAgenda.selectedEventExternalId
    property string selectedEventCalId: UnifiedAgenda.selectedEventCalId

    function applyFocusedDay() {
        if (root.focusedDayStartMs >= 0 && root.focusedDayEndMs > root.focusedDayStartMs) {
            tabBar.setCurrentIndex(0);
            const firstMatch = root.remoteEvents.find(item => AgendaDates.eventIntersectsRange(
                item,
                root.focusedDayStartMs,
                root.focusedDayEndMs
            ));
            if (firstMatch
                && (`${firstMatch?.externalId ?? ""}` !== root.selectedEventExternalId
                    || `${firstMatch?.calId ?? ""}` !== root.selectedEventCalId))
                UnifiedAgenda.selectEvent(firstMatch);
        }
    }

    onFocusedDayStartMsChanged: focusDaySelectionTimer.restart()
    onFocusedDayEndMsChanged: focusDaySelectionTimer.restart()
    onRemoteEventsChanged: focusDaySelectionTimer.restart()

    Timer {
        id: focusDaySelectionTimer
        interval: 0
        repeat: false
        onTriggered: root.applyFocusedDay()
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
                readOnly: item.readOnly !== false,
                source: "quickmail-task",
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

    function normalizedAgendaEvent(event) {
        return {
            content: event?.title ?? "",
            title: event?.title ?? "",
            description: event?.description ?? "",
            dueAt: parseInt(event?.startAt ?? 0) || 0,
            endAt: parseInt(event?.endAt ?? 0) || 0,
            allDay: !!event?.allDay,
            done: false,
            readOnly: true,
            source: "quickmail-event",
            kind: "event",
            originalIndex: -1,
            id: `${event?.id ?? ""}`,
            externalId: `${event?.externalId ?? event?.id ?? ""}`,
            calId: `${event?.calId ?? ""}`,
            calendarName: `${event?.calendarName ?? ""}`,
            account: `${event?.calendarName ?? event?.account ?? ""}`,
            accountId: `${event?.accountId ?? ""}`,
            provider: `${event?.provider ?? "QuickMail"}`,
            writable: !!event?.writable,
            dateOnly: false,
        };
    }

    function eventKey(item) {
        return `${item?.calId ?? ""}\u0000${item?.externalId ?? item?.id ?? ""}`;
    }

    readonly property var unifiedAgendaList: {
        const items = UnifiedAgenda.agendaItems.map(item => ({
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
            id: item.id || "",
            externalId: item.externalId || "",
            calId: item.calId || "",
            calendarName: item.account || "",
            account: item.account || "",
            accountId: item.accountId || "",
            provider: item.provider || "QuickMail",
            writable: !!item.writable,
            dateOnly: !!item.dateOnly,
        }));

        if (root.focusedDayStartMs >= 0 && root.focusedDayEndMs > root.focusedDayStartMs) {
            const existingEvents = new Set(items
                .filter(item => item.kind === "event")
                .map(item => root.eventKey(item)));
            root.remoteEvents
                .filter(event => AgendaDates.eventIntersectsRange(
                    event,
                    root.focusedDayStartMs,
                    root.focusedDayEndMs
                ))
                .map(event => root.normalizedAgendaEvent(event))
                .forEach(event => {
                    if (!existingEvents.has(root.eventKey(event)))
                        items.push(event);
                });
        }

        return items.sort((a, b) => {
            const aTime = (parseInt(a?.dueAt ?? 0) || 0) > 0
                ? parseInt(a.dueAt)
                : Number.MAX_SAFE_INTEGER;
            const bTime = (parseInt(b?.dueAt ?? 0) || 0) > 0
                ? parseInt(b.dueAt)
                : Number.MAX_SAFE_INTEGER;
            if (aTime !== bTime)
                return aTime - bTime;
            return `${a?.title ?? ""}`.localeCompare(`${b?.title ?? ""}`);
        });
    }

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
            visible: root.loading || UnifiedAgenda.mutationBusy

            MaterialLoadingIndicator {
                implicitSize: 22
                loading: root.loading || UnifiedAgenda.mutationBusy
            }

            StyledText {
                text: UnifiedAgenda.mutationBusy
                    ? Translation.tr("Syncing QuickMail task…")
                    : root.hasAnyData
                        ? Translation.tr("Refreshing agenda and mail")
                        : Translation.tr("Loading agenda and mail")
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
