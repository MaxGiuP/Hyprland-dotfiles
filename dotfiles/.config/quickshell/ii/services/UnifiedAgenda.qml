pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string bridgeScriptPath: `${Directories.scriptPath}/accounts/fetch-quickmail-snapshot.py`.replace(/file:\/\//, "")
    readonly property string mutationScriptPath: `${Directories.scriptPath}/accounts/mutate-quickmail-task.py`.replace(/file:\/\//, "")
    readonly property string launcherScriptPath: `${Directories.scriptPath}/accounts/open-quickmail.sh`.replace(/file:\/\//, "")
    property list<var> accounts: []
    property list<var> recentMail: []
    property list<var> remoteTasks: []
    property list<var> remoteEvents: []
    property var syncStatus: ({})
    property bool serviceAvailable: false
    property bool syncRequested: false
    property bool refreshQueued: false
    property bool syncQueued: false
    property string lastError: ""
    readonly property string mailError: lastError
    property date lastRefresh: new Date(0)
    property real focusedDayStartMs: -1
    property real focusedDayEndMs: -1
    property string selectedEventExternalId: ""
    property string selectedEventCalId: ""
    property var mutationQueue: []
    property var activeMutation: null
    property string mutationError: ""
    readonly property bool loading: snapshotProcess.running
    readonly property bool mutationBusy: mutationProcess.running || !!activeMutation || mutationQueue.length > 0
    readonly property int unreadCount: accounts.reduce((sum, account) => sum + (Number(account.unread) || 0), 0)
    readonly property int openLocalTaskCount: Todo.list.filter(item => !item.done).length
    readonly property int openRemoteTaskCount: remoteTasks.filter(item => !item.done).length
    readonly property var writableTaskDestinations: accounts
        .filter(account => !!account.taskWritable && `${account.id ?? ""}`.length > 0)
        .map(account => ({
            id: `${account.id}`,
            displayName: `${account.provider || "QuickMail"} · ${account.address || account.displayName || account.id}`,
            provider: `${account.provider || "QuickMail"}`,
            icon: `${account.provider || ""}`.toLowerCase().includes("outlook") ? "business_center" : "mail",
            dateOnlyDue: !!account.taskDateOnly || /gmail|google/.test(`${account.provider || ""}`.toLowerCase()),
            remote: true,
        }))

    readonly property var agendaItems: {
        const now = Date.now();
        const horizon = now + 14 * 24 * 60 * 60 * 1000;
        const dayMs = 24 * 60 * 60 * 1000;
        const nowDate = new Date(now);
        const horizonDate = new Date(horizon);
        const todayCalendarDay = Math.floor(Date.UTC(
            nowDate.getFullYear(),
            nowDate.getMonth(),
            nowDate.getDate()
        ) / dayMs);
        const horizonCalendarDay = Math.floor(Date.UTC(
            horizonDate.getFullYear(),
            horizonDate.getMonth(),
            horizonDate.getDate()
        ) / dayMs);
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
                kind: "task", source: "quickmail-task", title: item.content || item.title || "",
                description: item.description || "", timestamp: Number(item.dueAt) || 0,
                allDay: !!item.dateOnly, done: !!item.done, readOnly: !!item.readOnly, originalIndex: -1,
                account: item.calendarName || "QuickMail", externalId: item.externalId || item.id || "",
                accountId: item.accountId || "", provider: item.provider || "QuickMail",
                writable: !!item.writable, dateOnly: !!item.dateOnly,
                id: item.id || "", calId: item.calId || ""
            }))
            .filter(item => !item.done && item.title.length > 0);
        const events = root.remoteEvents
            .map(item => ({
                kind: "event", source: "quickmail-event", title: item.title || "",
                description: item.description || "", timestamp: Number(item.startAt) || 0,
                endAt: Number(item.endAt) || 0, allDay: !!item.allDay,
                done: false, readOnly: true, originalIndex: -1,
                account: item.calendarName || "QuickMail", externalId: item.externalId || item.id || "",
                accountId: item.accountId || "", provider: item.provider || "QuickMail",
                writable: !!item.writable, id: item.id || "", calId: item.calId || ""
            }))
            .filter(item => {
                if (item.title.length === 0 || item.timestamp <= 0)
                    return false;
                if (item.allDay) {
                    const startDay = Math.floor(item.timestamp / dayMs);
                    let endDay = Math.floor(item.endAt / dayMs);
                    if (item.endAt <= item.timestamp || endDay <= startDay)
                        endDay = startDay + 1;
                    return startDay <= horizonCalendarDay && endDay > todayCalendarDay;
                }
                if (item.timestamp > horizon)
                    return false;
                const end = item.endAt > item.timestamp ? item.endAt : item.timestamp + 1;
                return end > now;
            });
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
        if (snapshotProcess.running) {
            root.refreshQueued = true;
            root.syncQueued = root.syncQueued || requestSync;
            return;
        }
        root.syncRequested = requestSync === true;
        snapshotProcess.running = true;
    }

    function enqueueMutation(method, payload, action, taskId = "") {
        root.mutationError = "";
        const nextQueue = root.mutationQueue.slice();
        nextQueue.push({
            method: method,
            payload: payload,
            action: action,
            taskId: `${taskId || ""}`,
        });
        root.mutationQueue = nextQueue;
        root.runNextMutation();
        return true;
    }

    function runNextMutation() {
        if (mutationProcess.running || root.activeMutation || root.mutationQueue.length === 0)
            return;
        const nextQueue = root.mutationQueue.slice();
        root.activeMutation = nextQueue.shift();
        root.mutationQueue = nextQueue;
        mutationProcess.command = [
            "python3",
            root.mutationScriptPath,
            root.activeMutation.method,
            JSON.stringify(root.activeMutation.payload),
        ];
        mutationProcess.running = true;
    }

    function createRemoteTask(accountId, title, description = "", dueAt = 0) {
        const cleanAccountId = `${accountId || ""}`.trim();
        const cleanTitle = `${title || ""}`.trim();
        if (cleanAccountId.length === 0) {
            root.mutationError = Translation.tr("No writable QuickMail account is selected");
            return false;
        }
        if (cleanTitle.length === 0)
            return false;
        const dueTimestamp = Math.max(0, parseInt(dueAt) || 0);
        return root.enqueueMutation("task.create", {
            id: "",
            title: cleanTitle,
            description: `${description || ""}`.trim(),
            done: false,
            dueAt: dueTimestamp > 0 ? dueTimestamp : null,
            createdAt: Date.now(),
            source: "quickmail-task",
            externalId: "",
            account: cleanAccountId,
        }, "create");
    }

    function completeRemoteTask(taskId, done) {
        const cleanTaskId = `${taskId || ""}`.trim();
        if (cleanTaskId.length === 0)
            return false;
        return root.enqueueMutation("task.complete", {
            taskId: cleanTaskId,
            done: !!done,
        }, "complete", cleanTaskId);
    }

    function deleteRemoteTask(taskId) {
        const cleanTaskId = `${taskId || ""}`.trim();
        if (cleanTaskId.length === 0)
            return false;
        return root.enqueueMutation("task.delete", {
            taskId: cleanTaskId,
        }, "delete", cleanTaskId);
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

    function openMail() { root.launch("show"); }
    function openCompose() { root.launch("compose"); }
    function openCalendarApp() { root.launch("calendar"); }
    function openSidebarCalendar() { GlobalStates.openCalendar(); }
    function openCalendar() { root.openCalendarApp(); }
    function openAccountSettings() { root.launch("accounts"); }

    signal taskMutationFinished(string action, string taskId, bool success, string errorMessage)

    Timer {
        interval: 5 * 60 * 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh(true)
    }

    Timer {
        id: agendaWatchRefresh
        interval: 150
        repeat: false
        onTriggered: root.refresh(false)
    }

    Timer {
        id: agendaWatchRestart
        interval: 3000
        repeat: false
        onTriggered: {
            if (!agendaWatchProcess.running)
                agendaWatchProcess.running = true;
        }
    }

    Process {
        id: agendaWatchProcess
        running: true
        command: ["python3", root.bridgeScriptPath, "--watch"]

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                try {
                    const message = JSON.parse(line);
                    if (`${message?.method ?? ""}` === "agenda.changed")
                        agendaWatchRefresh.restart();
                } catch (error) {
                    // A malformed notification must not stop cache polling.
                }
            }
        }

        onExited: agendaWatchRestart.restart()
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
                    const available = !!payload.available;
                    if (available) {
                        root.accounts = payload.accounts ?? [];
                        root.recentMail = payload.messages ?? [];
                        root.remoteTasks = payload.tasks ?? [];
                        root.remoteEvents = payload.events ?? [];
                        root.syncStatus = payload.sync ?? ({});
                        root.lastRefresh = new Date();
                    }
                    root.serviceAvailable = available;
                    root.lastError = payload.error ?? "";
                } catch (error) {
                    root.serviceAvailable = false;
                    root.lastError = `${error}`;
                }
            }
        }

        onExited: {
            const shouldRefresh = root.refreshQueued;
            const shouldSync = root.syncQueued;
            root.syncRequested = false;
            root.refreshQueued = false;
            root.syncQueued = false;
            if (shouldRefresh)
                Qt.callLater(() => root.refresh(shouldSync));
        }
    }

    Timer {
        id: mutationRefreshTimer
        interval: 250
        repeat: false
        onTriggered: {
            if (snapshotProcess.running || mutationProcess.running || root.activeMutation || root.mutationQueue.length > 0)
                mutationRefreshTimer.restart();
            else
                root.refresh(false);
        }
    }

    Process {
        id: mutationProcess

        stdout: StdioCollector {
            id: mutationOutput
        }
        stderr: StdioCollector {
            id: mutationErrorOutput
        }
        onExited: (exitCode, exitStatus) => {
            const finished = root.activeMutation || ({});
            const success = exitCode === 0;
            let errorMessage = "";
            if (!success) {
                const detail = `${mutationErrorOutput.text || mutationOutput.text || ""}`.trim()
                    || Translation.tr("Unknown QuickMail error");
                errorMessage = Translation.tr("QuickMail task update failed: %1").arg(detail);
                root.mutationError = errorMessage;
            } else {
                root.mutationError = "";
                mutationRefreshTimer.restart();
            }
            root.taskMutationFinished(
                `${finished.action || ""}`,
                `${finished.taskId || ""}`,
                success,
                errorMessage
            );
            root.activeMutation = null;
            Qt.callLater(() => root.runNextMutation());
        }
    }

    IpcHandler {
        target: "quickMail"

        function open(): void { root.openMail(); }
        function show(): void { root.openMail(); }
        function compose(): void { root.openCompose(); }
        function calendar(): void { root.openCalendarApp(); }
        function sidebarCalendar(): void { root.openSidebarCalendar(); }
        function accounts(): void { root.openAccountSettings(); }
        function refresh(): void { root.refresh(true); }
    }
}
