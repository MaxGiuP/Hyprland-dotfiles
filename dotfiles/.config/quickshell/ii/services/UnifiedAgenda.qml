pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string bridgeScriptPath: `${Directories.scriptPath}/accounts/fetch-lightbird-snapshot.py`.replace(/file:\/\//, "")
    readonly property string launcherScriptPath: `${Directories.scriptPath}/accounts/open-lightbird-mail.sh`.replace(/file:\/\//, "")
    property list<var> accounts: []
    property list<var> recentMail: []
    property list<var> remoteTasks: []
    property list<var> remoteEvents: []
    property var syncStatus: ({})
    property bool serviceAvailable: false
    property bool syncRequested: false
    property string lastError: ""
    readonly property string mailError: lastError
    property date lastRefresh: new Date(0)
    property real focusedDayStartMs: -1
    property real focusedDayEndMs: -1
    property string selectedEventExternalId: ""
    property string selectedEventCalId: ""
    readonly property bool loading: snapshotProcess.running
    readonly property int unreadCount: accounts.reduce((sum, account) => sum + (Number(account.unread) || 0), 0)
    readonly property int openLocalTaskCount: Todo.list.filter(item => !item.done).length
    readonly property int openRemoteTaskCount: remoteTasks.filter(item => !item.done).length

    readonly property var agendaItems: {
        const now = Date.now();
        const horizon = now + 14 * 24 * 60 * 60 * 1000;
        const local = Todo.list
            .map((item, index) => ({
                kind: "task", source: item.source || "local", title: item.title,
                description: item.description || "", timestamp: Number(item.dueAt) || 0,
                done: !!item.done, readOnly: false, originalIndex: index,
                account: item.account || "", externalId: item.externalId || ""
            }))
            .filter(item => !item.done);
        const importedTasks = root.remoteTasks
            .map(item => ({
                kind: "task", source: "lightbird-task", title: item.content || item.title || "",
                description: item.description || "", timestamp: Number(item.dueAt || item.entryAt) || 0,
                done: !!item.done, readOnly: true, originalIndex: -1,
                account: item.calendarName || "Lightbird", externalId: item.externalId || item.id || "",
                calId: item.calId || ""
            }))
            .filter(item => !item.done && item.title.length > 0);
        const events = root.remoteEvents
            .map(item => ({
                kind: "event", source: "lightbird-event", title: item.title || "",
                description: item.description || "", timestamp: Number(item.startAt) || 0,
                endAt: Number(item.endAt) || 0, allDay: !!item.allDay,
                done: false, readOnly: true, originalIndex: -1,
                account: item.calendarName || "Lightbird", externalId: item.externalId || item.id || "",
                calId: item.calId || ""
            }))
            .filter(item => item.title.length > 0 && item.timestamp >= now - 24 * 60 * 60 * 1000 && item.timestamp <= horizon);
        return local.concat(importedTasks, events).sort((a, b) => {
            const aTime = a.timestamp > 0 ? a.timestamp : Number.MAX_SAFE_INTEGER;
            const bTime = b.timestamp > 0 ? b.timestamp : Number.MAX_SAFE_INTEGER;
            if (aTime !== bTime) return aTime - bTime;
            return a.title.localeCompare(b.title);
        });
    }

    readonly property var todayItems: {
        const start = new Date();
        start.setHours(0, 0, 0, 0);
        const end = new Date(start);
        end.setDate(end.getDate() + 1);
        return agendaItems.filter(item => item.timestamp === 0 || (item.timestamp >= start.getTime() && item.timestamp < end.getTime()));
    }

    function refresh(requestSync = true) {
        if (snapshotProcess.running)
            return;
        root.syncRequested = requestSync;
        snapshotProcess.running = true;
    }

    function focusDay(dayDate) {
        const start = new Date(dayDate);
        start.setHours(0, 0, 0, 0);
        const end = new Date(start);
        end.setDate(end.getDate() + 1);
        root.focusedDayStartMs = start.getTime();
        root.focusedDayEndMs = end.getTime();
        root.selectedEventExternalId = "";
        root.selectedEventCalId = "";
    }

    function selectEvent(eventItem) {
        const nextExternalId = `${eventItem?.externalId ?? ""}`;
        const nextCalId = `${eventItem?.calId ?? ""}`;
        if (root.selectedEventExternalId === nextExternalId && root.selectedEventCalId === nextCalId) {
            root.selectedEventExternalId = "";
            root.selectedEventCalId = "";
            return;
        }
        root.selectedEventExternalId = nextExternalId;
        root.selectedEventCalId = nextCalId;
    }

    function addMailAsTask(message) {
        const externalId = `mail:${message.accountId}:${message.id}`;
        if (Todo.list.some(item => item.externalId === externalId))
            return;
        Todo.addTask(
            `Reply: ${message.title}`,
            message.author ? `From ${message.author}` : `From ${message.account}`,
            0,
            "mail",
            { externalId, account: message.account }
        );
    }

    function addEventAsTask(eventItem) {
        const externalId = `event:${eventItem.externalId}`;
        if (Todo.list.some(item => item.externalId === externalId))
            return;
        const account = eventItem.account || eventItem.calendarName || "Calendar";
        const timestamp = Number(eventItem.timestamp || eventItem.dueAt) || 0;
        Todo.addTask(eventItem.title, `From ${account}`, timestamp, "calendar", { externalId, account });
    }

    function hasTaskForExternalId(externalId) {
        return Todo.list.some(item => item.externalId === externalId);
    }

    function launch(view) {
        Quickshell.execDetached(["bash", root.launcherScriptPath, view || "mail"]);
    }

    function openMail() { root.launch("mail"); }
    function openCalendar() { root.launch("calendar"); }
    function openAccountSettings() { root.launch("accounts"); }

    Timer {
        interval: 5 * 60 * 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh(false)
    }

    Process {
        id: snapshotProcess
        command: root.syncRequested
            ? ["python3", root.bridgeScriptPath, "--sync"]
            : ["python3", root.bridgeScriptPath]

        stdout: StdioCollector {
            id: snapshotOutput
            onStreamFinished: {
                try {
                    const payload = JSON.parse(snapshotOutput.text || "{}");
                    root.accounts = payload.accounts ?? [];
                    root.recentMail = payload.messages ?? [];
                    root.remoteTasks = payload.tasks ?? [];
                    root.remoteEvents = payload.events ?? [];
                    root.syncStatus = payload.sync ?? ({});
                    root.serviceAvailable = !!payload.available;
                    root.lastError = payload.error ?? "";
                    root.lastRefresh = new Date();
                } catch (error) {
                    root.serviceAvailable = false;
                    root.lastError = `${error}`;
                }
            }
        }
    }

    IpcHandler {
        target: "lightbirdMail"

        function open(): void { root.openMail(); }
        function calendar(): void { root.openCalendar(); }
        function accounts(): void { root.openAccountSettings(); }
        function refresh(): void { root.refresh(true); }
    }
}
