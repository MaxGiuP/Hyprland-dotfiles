pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string mailScriptPath: `${Directories.scriptPath}/accounts/fetch-thunderbird-summary.py`.replace(/file:\/\//, "")
    property list<var> accounts: []
    property list<var> recentMail: []
    property string mailError: ""
    property date lastMailRefresh: new Date(0)
    readonly property bool loading: mailProcess.running || RemoteCalendarBridge.loading
    readonly property int unreadCount: accounts.reduce((sum, account) => sum + (Number(account.unread) || 0), 0)
    readonly property int openLocalTaskCount: Todo.list.filter(item => !item.done).length
    readonly property int openRemoteTaskCount: RemoteCalendarBridge.thunderbirdTasks.filter(item => !item.done).length

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
        const remoteTasks = RemoteCalendarBridge.thunderbirdTasks
            .map(item => ({
                kind: "task", source: "calendar-task", title: item.content || item.title || "",
                description: "", timestamp: Number(item.dueAt || item.entryAt) || 0,
                done: !!item.done, readOnly: true, originalIndex: -1,
                account: item.calendarName || "Calendar", externalId: item.externalId || "",
                calId: item.calId || ""
            }))
            .filter(item => !item.done && item.title.length > 0);
        const events = RemoteCalendarBridge.thunderbirdEvents
            .map(item => ({
                kind: "event", source: "calendar-event", title: item.title || "",
                description: "", timestamp: Number(item.startAt) || 0,
                endAt: Number(item.endAt) || 0, allDay: !!item.allDay,
                done: false, readOnly: true, originalIndex: -1,
                account: item.calendarName || "Calendar", externalId: item.externalId || "",
                calId: item.calId || ""
            }))
            .filter(item => item.title.length > 0 && item.timestamp >= now - 24 * 60 * 60 * 1000 && item.timestamp <= horizon);
        return local.concat(remoteTasks, events).sort((a, b) => {
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

    function refresh() {
        RemoteCalendarBridge.refresh();
        if (!mailProcess.running)
            mailProcess.running = true;
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

    function openMail() { Quickshell.execDetached(["thunderbird", "-mail"]); }
    function openCalendar() { Quickshell.execDetached(["thunderbird", "-calendar"]); }
    function openAccountSettings() { Quickshell.execDetached(["thunderbird", "-options"]); }

    Timer {
        interval: 5 * 60 * 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: if (!mailProcess.running) mailProcess.running = true
    }

    Process {
        id: mailProcess
        command: ["python3", root.mailScriptPath]
        stdout: StdioCollector {
            id: mailOutput
            onStreamFinished: {
                try {
                    const payload = JSON.parse(mailOutput.text || "{}");
                    root.accounts = payload.accounts ?? [];
                    root.recentMail = payload.messages ?? [];
                    root.mailError = payload.error ?? "";
                    root.lastMailRefresh = new Date();
                } catch (error) {
                    root.mailError = `${error}`;
                }
            }
        }
    }
}
