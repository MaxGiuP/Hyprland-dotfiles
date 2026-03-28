pragma Singleton
pragma ComponentBehavior: Bound

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
    property real focusedDayStartMs: -1
    property real focusedDayEndMs: -1
    property string selectedEventExternalId: ""
    property string selectedEventCalId: ""

    property string fetchScriptPath: {
        const url = Qt.resolvedUrl("./fetch_google_caldav_primary.py").toString();
        return url.startsWith("file://") ? url.slice(7) : url;
    }

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

        onRunningChanged: root.loading = running

        stdout: StdioCollector {
            id: collector
            onStreamFinished: {
                const txt = collector.text || "";
                if (!txt || txt.trim().length === 0)
                    return;
                try {
                    const payload = JSON.parse(txt.trim());
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

        onExited: (exitCode) => {
            if (exitCode !== 0 && !root.lastError)
                root.lastError = `Calendar fetch failed (code ${exitCode})`;
        }
    }

    function refresh() {
        root.lastError = "";
        fetchProc.running = false;
        fetchProc.running = true;
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
}
