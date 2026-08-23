pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * Provides access to some Hyprland data not available in Quickshell.Hyprland.
 */
Singleton {
    id: root
    property var browserFullscreenRestoreState: ({})
    property var windowList: []
    property var addresses: []
    property var windowByAddress: ({})
    property var workspaces: []
    property var workspaceIds: []
    property var workspaceById: ({})
    property var activeWorkspace: null
    property var monitors: []
    property var layers: ({})
    property bool windowRefreshPending: false
    property bool monitorRefreshPending: false
    property var activeWorkspaceIdsByMonitor: ({})
    property var workspaceEventTimesByMonitor: ({})
    property string eventFocusedMonitorName: ""
    readonly property string workspaceEventSocketPath: `${Quickshell.env("XDG_RUNTIME_DIR")}/hypr/${Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")}/.socket2.sock`

    // Convenient stuff

    function toplevelAddress(toplevel) {
        const rawAddress = toplevel?.HyprlandToplevel?.address;
        return rawAddress == null ? "" : `0x${rawAddress}`;
    }

    function windowHasValidSize(win) {
        const size = win?.size ?? [];
        const width = Number(size[0] ?? 0);
        const height = Number(size[1] ?? 0);
        return isFinite(width) && isFinite(height) && width > 0 && height > 0;
    }

    function toplevelHasValidSize(toplevel) {
        return root.windowHasValidSize(root.clientForToplevel(toplevel));
    }

    function captureSourceForToplevel(toplevel) {
        return root.toplevelHasValidSize(toplevel) ? toplevel : null;
    }

    function toplevelsForWorkspace(workspace) {
        return ToplevelManager.toplevels.values.filter(toplevel => {
            const address = root.toplevelAddress(toplevel);
            var win = HyprlandData.windowByAddress[address];
            return win?.workspace?.id === workspace;
        })
    }

    function hyprlandClientsForWorkspace(workspace) {
        return root.windowList.filter(win => win.workspace.id === workspace);
    }

    function clientForToplevel(toplevel) {
        const address = root.toplevelAddress(toplevel);
        if (!address) {
            return null;
        }
        return root.windowByAddress[address];
    }

    function isTrackedBrowserWindow(win) {
        const klass = `${win?.class ?? ""}`;
        return /^(Brave-browser|brave-browser|Google-chrome|google-chrome|Chromium|chromium|chromium-browser)$/.test(klass);
    }

    function isVideoFullscreenState(state) {
        return state === 2 || state === 3;
    }

    function restoreBrowserWindowState(address, restoreState) {
        const normalizedState = restoreState === 1 ? 1 : 0;
        Quickshell.execDetached([
            "hyprctl",
            "--batch",
            `dispatch focuswindow address:${address}; dispatch fullscreenstate ${normalizedState} ${normalizedState} set`
        ]);
    }

    function syncBrowserFullscreenStates(previousByAddress, nextByAddress) {
        const pendingStates = Object.assign({}, root.browserFullscreenRestoreState ?? {});

        for (const [address, nextWindow] of Object.entries(nextByAddress)) {
            if (!root.isTrackedBrowserWindow(nextWindow)) {
                delete pendingStates[address];
                continue;
            }

            const previousWindow = previousByAddress?.[address];
            if (!previousWindow)
                continue;

            const previousState = Number(previousWindow.fullscreen ?? 0);
            const nextState = Number(nextWindow.fullscreen ?? 0);
            const wasFullscreen = root.isVideoFullscreenState(previousState);
            const isFullscreen = root.isVideoFullscreenState(nextState);

            if (!wasFullscreen && isFullscreen) {
                // Browser video/fullscreen transitions can briefly report
                // Hyprland state 1 (maximized), the same state Super+D uses.
                // Restoring that on exit leaves the window maximized instead
                // of returning to the pre-fullscreen tiled view.
                pendingStates[address] = 0;
                continue;
            }

            if (wasFullscreen && !isFullscreen) {
                const restoreState = pendingStates[address];
                if (restoreState !== undefined && nextState !== restoreState)
                    root.restoreBrowserWindowState(address, restoreState);
                delete pendingStates[address];
            }
        }

        for (const address of Object.keys(pendingStates)) {
            if (!nextByAddress[address])
                delete pendingStates[address];
        }

        root.browserFullscreenRestoreState = pendingStates;
    }

    // Internals

    function validWorkspaceId(value) {
        const id = Number(value ?? 0);
        return Number.isFinite(id) && id > 0 ? Math.round(id) : 0;
    }

    function workspaceIdFromEvent(value) {
        const numericId = root.validWorkspaceId(value);
        if (numericId > 0)
            return numericId;
        const name = `${value ?? ""}`;
        return root.validWorkspaceId(root.workspaces.find(ws => `${ws.name}` === name)?.id);
    }

    function setEventWorkspace(monitorName, workspaceId) {
        const name = `${monitorName ?? ""}`;
        const id = root.validWorkspaceId(workspaceId);
        if (!name || id <= 0)
            return;

        const ids = Object.assign({}, root.activeWorkspaceIdsByMonitor);
        const times = Object.assign({}, root.workspaceEventTimesByMonitor);
        const changed = ids[name] !== id;
        ids[name] = id;
        times[name] = Date.now();
        if (changed)
            root.activeWorkspaceIdsByMonitor = ids;
        root.workspaceEventTimesByMonitor = times;
    }

    function handleWorkspaceEvent(event) {
        const name = event.name;
        const parts = `${event.data ?? ""}`.split(",");

        if (name === "focusedmon") {
            const monitorName = parts.shift() ?? "";
            root.eventFocusedMonitorName = monitorName;
            root.setEventWorkspace(monitorName, root.workspaceIdFromEvent(parts.join(",")));
            return;
        }

        if (name !== "workspace" && name !== "workspacev2")
            return;

        if (!root.eventFocusedMonitorName)
            root.eventFocusedMonitorName = root.monitors.find(m => m.focused)?.name ?? "";
        const workspaceId = name === "workspacev2"
            ? root.workspaceIdFromEvent(parts[0])
            : root.workspaceIdFromEvent(event.data);
        root.setEventWorkspace(root.eventFocusedMonitorName, workspaceId);
    }

    function handleWorkspaceSocketLine(line) {
        const separator = line.indexOf(">>");
        if (separator <= 0)
            return;
        root.handleWorkspaceEvent({
            name: line.substring(0, separator),
            data: line.substring(separator + 2)
        });
    }

    function reconcileMonitorWorkspaceState(nextMonitors) {
        const now = Date.now();
        const ids = Object.assign({}, root.activeWorkspaceIdsByMonitor);
        const times = root.workspaceEventTimesByMonitor;
        let changed = false;

        for (const monitor of nextMonitors) {
            const name = `${monitor?.name ?? ""}`;
            const id = root.validWorkspaceId(monitor?.activeWorkspace?.id);
            if (name && id > 0 && ids[name] !== id
                    && (ids[name] === undefined || now - Number(times[name] ?? 0) >= 500)) {
                ids[name] = id;
                changed = true;
            }
            if (monitor?.focused)
                root.eventFocusedMonitorName = name;
        }

        if (changed)
            root.activeWorkspaceIdsByMonitor = ids;
    }

    function updateWindowList() {
        if (getClients.running) {
            root.windowRefreshPending = true;
            return;
        }
        getClients.running = true;
    }

    function updateLayers() {
        if (!getLayers.running)
            getLayers.running = true;
    }

    function updateMonitors() {
        if (getMonitors.running) {
            // Do not lose a workspace/monitor event just because an older
            // hyprctl request is still finishing. One trailing refresh is
            // enough to converge on the compositor's newest state.
            root.monitorRefreshPending = true;
            return;
        }
        getMonitors.running = true;
    }

    function updateWorkspaces() {
        if (!getWorkspaces.running)
            getWorkspaces.running = true;
        if (!getActiveWorkspace.running)
            getActiveWorkspace.running = true;
    }

    function updateAll() {
        updateWindowList();
        updateMonitors();
        updateLayers();
        updateWorkspaces();
    }

    function biggestWindowForWorkspace(workspaceId) {
        const windowsInThisWorkspace = HyprlandData.windowList.filter(w => w.workspace.id == workspaceId);
        return windowsInThisWorkspace.reduce((maxWin, win) => {
            const maxArea = (maxWin?.size?.[0] ?? 0) * (maxWin?.size?.[1] ?? 0);
            const winArea = (win?.size?.[0] ?? 0) * (win?.size?.[1] ?? 0);
            return winArea > maxArea ? win : maxWin;
        }, null);
    }

    function windowIsFullscreen(win) {
        return Number(win?.fullscreen ?? 0) !== 0;
    }

    function windowHidesShell(win) {
        return root.isVideoFullscreenState(Number(win?.fullscreen ?? 0));
    }

    function activeWorkspaceHasFullscreenForMonitor(monitorName) {
        if (!monitorName)
            return false;

        const monitor = root.monitors.find(m => m.name === monitorName);
        const activeWorkspaceId = monitor?.activeWorkspace?.id;
        if (activeWorkspaceId == null)
            return false;

        const monitorId = monitor?.id;

        if (root.windowList.some(win =>
            win.workspace?.id === activeWorkspaceId
            && (monitorId == null || win.monitor === monitorId)
            && root.windowHidesShell(win)
        )) {
            return true;
        }

        return false;
    }

    function monitorShowsTvSpecialWorkspace(monitorName) {
        if (!monitorName)
            return false;

        const monitor = root.monitors.find(m => m.name === monitorName);
        const specialName = `${monitor?.specialWorkspace?.name ?? ""}`;
        return specialName === "special:tv" || specialName === "special:tv-app";
    }

    Component.onCompleted: {
        updateAll();
    }

    Connections {
        target: Hyprland

        function onFocusedWorkspaceChanged() {
            updateMonitors();
            updateWorkspaces();
        }

        function onRawEvent(event) {
            const name = event.name;

            // Window titles can change many times per second (for example a
            // terminal spinner). They must never congest workspace/monitor
            // refreshes; only the client metadata depends on these events.
            if (["windowtitle", "windowtitlev2"].includes(name)) {
                windowTitleRefresh.restart();
                return;
            }

            if (["workspace", "workspacev2", "focusedmon", "activespecial",
                    "moveworkspace", "moveworkspacev2", "createworkspace",
                    "createworkspacev2", "destroyworkspace", "destroyworkspacev2",
                    "renameworkspace"].includes(name)) {
                root.handleWorkspaceEvent(event);
                // Keep Quickshell's native objects current as well as the
                // richer hyprctl-backed data used elsewhere in the shell.
                Hyprland.refreshWorkspaces();
                Hyprland.refreshMonitors();
                root.updateMonitors();
                root.updateWorkspaces();
                root.updateWindowList();
                return;
            }

            if (["openlayer", "closelayer", "screencast"].includes(name))
            {
                if (name !== "screencast")
                    root.updateLayers();
                return;
            }

            if (["openwindow", "closewindow", "movewindow", "movewindowv2",
                    "activewindow", "activewindowv2", "fullscreen", "pin",
                    "changefloatingmode", "minimize", "togglegroup", "moveintogroup",
                    "moveoutofgroup", "changegroupactive", "lockgroups"].includes(name)) {
                root.updateWindowList();
                return;
            }

            if (["monitoradded", "monitoraddedv2", "monitorremoved"].includes(name)) {
                Hyprland.refreshMonitors();
                root.updateMonitors();
                root.updateWorkspaces();
                return;
            }

            if (name === "configreloaded")
                root.updateAll();
        }
    }

    Timer {
        id: windowTitleRefresh
        interval: 200
        repeat: false
        onTriggered: root.updateWindowList()
    }

    // Quickshell's built-in Hyprland event connection can remain disconnected
    // after PeerClosedError. Keep workspace highlighting independent from that
    // connection and filter the noisy event stream before it reaches QML.
    Process {
        id: workspaceEventSocket
        running: root.workspaceEventSocketPath.length > 0
        command: [
            "bash", "-c",
            `socat -u UNIX-CONNECT:${root.workspaceEventSocketPath} - | grep --line-buffered -E '^(workspace|workspacev2|focusedmon)>>'`
        ]
        stdout: SplitParser {
            onRead: line => root.handleWorkspaceSocketLine(line)
        }
        onExited: workspaceEventSocketRestart.restart()
    }

    Timer {
        id: workspaceEventSocketRestart
        interval: 250
        repeat: false
        onTriggered: {
            if (!workspaceEventSocket.running && root.workspaceEventSocketPath.length > 0)
                workspaceEventSocket.running = true;
        }
    }

    // Fallback polling for cases where the Hyprland event stream stalls for this shell instance.
    Timer {
        interval: 400
        running: true
        repeat: true
        onTriggered: {
            root.updateMonitors();
            root.updateWorkspaces();
        }
    }

    Timer {
        interval: 900
        running: true
        repeat: true
        onTriggered: {
            root.updateWindowList();
        }
    }

    Process {
        id: getClients
        command: ["hyprctl", "clients", "-j"]
        onRunningChanged: {
            if (!running && root.windowRefreshPending)
                windowRefreshRetry.restart();
        }
        stdout: StdioCollector {
            id: clientsCollector
            onStreamFinished: {
                const previousByAddress = root.windowByAddress;
                root.windowList = JSON.parse(clientsCollector.text)
                let tempWinByAddress = {};
                for (var i = 0; i < root.windowList.length; ++i) {
                    var win = root.windowList[i];
                    tempWinByAddress[win.address] = win;
                }
                root.syncBrowserFullscreenStates(previousByAddress, tempWinByAddress);
                root.windowByAddress = tempWinByAddress;
                root.addresses = root.windowList.map(win => win.address);
            }
        }
    }

    Timer {
        id: windowRefreshRetry
        interval: 0
        repeat: false
        onTriggered: {
            if (getClients.running)
                return;
            root.windowRefreshPending = false;
            getClients.running = true;
        }
    }

    Process {
        id: getMonitors
        command: ["hyprctl", "monitors", "-j"]
        onRunningChanged: {
            if (!running && root.monitorRefreshPending)
                monitorRefreshRetry.restart();
        }
        stdout: StdioCollector {
            id: monitorsCollector
            onStreamFinished: {
                const nextMonitors = JSON.parse(monitorsCollector.text);
                root.reconcileMonitorWorkspaceState(nextMonitors);
                root.monitors = nextMonitors;
            }
        }
    }

    Timer {
        id: monitorRefreshRetry
        interval: 0
        repeat: false
        onTriggered: {
            if (getMonitors.running)
                return;
            root.monitorRefreshPending = false;
            getMonitors.running = true;
        }
    }

    Process {
        id: getLayers
        command: ["hyprctl", "layers", "-j"]
        stdout: StdioCollector {
            id: layersCollector
            onStreamFinished: {
                root.layers = JSON.parse(layersCollector.text);
            }
        }
    }

    Process {
        id: getWorkspaces
        command: ["hyprctl", "workspaces", "-j"]
        stdout: StdioCollector {
            id: workspacesCollector
            onStreamFinished: {
                root.workspaces = JSON.parse(workspacesCollector.text);
                let tempWorkspaceById = {};
                for (var i = 0; i < root.workspaces.length; ++i) {
                    var ws = root.workspaces[i];
                    tempWorkspaceById[ws.id] = ws;
                }
                root.workspaceById = tempWorkspaceById;
                root.workspaceIds = root.workspaces.map(ws => ws.id);
            }
        }
    }

    Process {
        id: getActiveWorkspace
        command: ["hyprctl", "activeworkspace", "-j"]
        stdout: StdioCollector {
            id: activeWorkspaceCollector
            onStreamFinished: {
                root.activeWorkspace = JSON.parse(activeWorkspaceCollector.text);
            }
        }
    }
}
