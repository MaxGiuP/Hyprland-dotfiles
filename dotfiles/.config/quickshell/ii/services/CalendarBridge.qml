pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property list<var> thunderbirdTasks: []
    property list<var> thunderbirdEvents: []
    property string sourceProfile: ""
    property bool loading: false
    property string lastError: ""
    property date lastRefresh: new Date(0)

    property string fetchScriptPath: `${Directories.scriptPath}/calendar/fetch_thunderbird_calendar.py`.replace(/file:\/\//, "")

    Timer {
        id: refreshTimer
        interval: 5 * 60 * 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: fetchProc
        command: ["python3", root.fetchScriptPath]

        onRunningChanged: {
            root.loading = running;
        }

        stdout: StdioCollector {
            id: collector
            onStreamFinished: {
                if (!collector.text || collector.text.trim().length === 0) return;
                try {
                    const payload = JSON.parse(collector.text.trim());
                    root.sourceProfile = payload.profile ?? "";
                    root.thunderbirdTasks = payload.tasks ?? [];
                    root.thunderbirdEvents = payload.events ?? [];
                    root.lastError = payload.error ?? "";
                    root.lastRefresh = new Date();
                } catch (e) {
                    root.lastError = `${e}`;
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 && !root.lastError) {
                root.lastError = `Calendar fetch failed (code ${exitCode})`;
            }
        }
    }

    function refresh() {
        fetchProc.running = false;
        fetchProc.running = true;
    }

    function dateRangeForDay(dayDate) {
        const start = new Date(dayDate);
        start.setHours(0, 0, 0, 0);
        const end = new Date(start);
        end.setDate(end.getDate() + 1);
        return {
            "startMs": start.getTime(),
            "endMs": end.getTime(),
        };
    }

    function isTimestampInDay(timestampMs, dayDate) {
        const range = dateRangeForDay(dayDate);
        return timestampMs >= range.startMs && timestampMs < range.endMs;
    }

    function getEventsForDay(dayDate) {
        const range = dateRangeForDay(dayDate);
        return thunderbirdEvents
            .filter(event => {
                const start = event.startAt ?? 0;
                const end = event.endAt ?? start;
                if (start <= 0) return false;
                return start < range.endMs && (end <= 0 ? start : end) >= range.startMs;
            })
            .sort((a, b) => (a.startAt ?? 0) - (b.startAt ?? 0));
    }

    function getTasksForDay(dayDate) {
        return thunderbirdTasks
            .filter(task => {
                if (task.done) return false;
                const due = task.dueAt ?? 0;
                const entry = task.entryAt ?? 0;
                const ts = due > 0 ? due : entry;
                return ts > 0 && isTimestampInDay(ts, dayDate);
            })
            .sort((a, b) => ((a.dueAt ?? a.entryAt ?? 0) - (b.dueAt ?? b.entryAt ?? 0)));
    }

    function getUpcomingEvents(daysAhead = 7) {
        const now = Date.now();
        const max = now + daysAhead * 24 * 60 * 60 * 1000;
        return thunderbirdEvents
            .filter(event => (event.startAt ?? 0) >= now && (event.startAt ?? 0) <= max)
            .sort((a, b) => (a.startAt ?? 0) - (b.startAt ?? 0));
    }

    function getUpcomingTasks(daysAhead = 7) {
        const now = Date.now();
        const max = now + daysAhead * 24 * 60 * 60 * 1000;
        return thunderbirdTasks
            .filter(task => {
                if (task.done) return false;
                const ts = task.dueAt ?? task.entryAt ?? 0;
                return ts >= now && ts <= max;
            })
            .sort((a, b) => ((a.dueAt ?? a.entryAt ?? 0) - (b.dueAt ?? b.entryAt ?? 0)));
    }
}
