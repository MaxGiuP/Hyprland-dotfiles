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

    // Convenient stuff

    function toplevelsForWorkspace(workspace) {
        return ToplevelManager.toplevels.values.filter(toplevel => {
            const address = `0x${toplevel.HyprlandToplevel?.address}`;
            var win = HyprlandData.windowByAddress[address];
            return win?.workspace?.id === workspace;
        })
    }

    function hyprlandClientsForWorkspace(workspace) {
        return root.windowList.filter(win => win.workspace.id === workspace);
    }

    function clientForToplevel(toplevel) {
        if (!toplevel || !toplevel.HyprlandToplevel) {
            return null;
        }
        const address = `0x${toplevel?.HyprlandToplevel?.address}`;
        return root.windowByAddress[address];
    }

    function isTrackedBrowserWindow(win) {
        const klass = `${win?.class ?? ""}`;
        return /^(Brave-browser|brave-browser|Google-chrome|google-chrome|Chromium|chromium|chromium-browser)$/.test(klass);
    }

    function isVideoFullscreenState(state) {
        return state === 2 || state === 3;
    }

    function normalizedRestoreState(state) {
        return (state === 1 || state === 3) ? 1 : 0;
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
                pendingStates[address] = root.normalizedRestoreState(previousState);
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

    function updateWindowList() {
        if (!getClients.running)
            getClients.running = true;
    }

    function updateLayers() {
        if (!getLayers.running)
            getLayers.running = true;
    }

    function updateMonitors() {
        if (!getMonitors.running)
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
            && root.windowIsFullscreen(win)
        )) {
            return true;
        }

        return root.workspaces.some(workspace =>
            workspace.monitor === monitorName &&
            workspace.id === activeWorkspaceId &&
            workspace.hasfullscreen === true
        );
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
            // console.log("Hyprland raw event:", event.name);
            if (["openlayer", "closelayer", "screencast"].includes(event.name)) return;
            updateAll()
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

    Process {
        id: getMonitors
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            id: monitorsCollector
            onStreamFinished: {
                root.monitors = JSON.parse(monitorsCollector.text);
            }
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
