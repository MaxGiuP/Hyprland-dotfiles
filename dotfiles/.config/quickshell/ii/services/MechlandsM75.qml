pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root

    readonly property string executable: `${FileUtils.trimFileProtocol(Directories.home)}/mechlands-m75-linux/bin/mechlandsctl`
    property var status: ({})
    property var capabilities: ({})
    property var actionResult: ({})
    property string lastError: ""
    property var pendingActionCommand: []
    property bool statusReady: false
    property bool capabilitiesReady: false

    readonly property bool refreshing: statusProcess.running || capabilitiesProcess.running
    readonly property bool actionRunning: actionProcess.running
    readonly property bool backendAvailable: root.statusReady || root.capabilitiesReady
    readonly property bool connected: root.status?.connected === true
    readonly property bool readOnly: root.capabilities?.read_only !== false
    readonly property bool configurationAvailable: root.status?.driver?.configuration_available === true && !root.readOnly
    readonly property string driverError: `${root.status?.driver?.error ?? ""}`
    readonly property var device: root.status?.device ?? ({})
    readonly property var interfaces: Array.isArray(root.status?.interfaces) ? root.status.interfaces : []
    readonly property var features: Array.isArray(root.capabilities?.features) ? root.capabilities.features : []

    signal actionFinished(bool success, var result)

    function parseJson(text, fallback = ({})) {
        try {
            const parsed = JSON.parse(text || "{}");
            return parsed && typeof parsed === "object" ? parsed : fallback;
        } catch (error) {
            root.lastError = `${error}`;
            return fallback;
        }
    }

    function errorMessage(result, fallback) {
        return `${result?.error?.message ?? result?.message ?? fallback ?? ""}`;
    }

    function refresh() {
        root.lastError = "";
        if (!statusProcess.running)
            statusProcess.running = true;
        if (!capabilitiesProcess.running)
            capabilitiesProcess.running = true;
    }

    function apply(settings) {
        if (!root.configurationAvailable || actionProcess.running)
            return false;

        root.actionResult = ({});
        root.lastError = "";
        root.pendingActionCommand = [root.executable, "apply", "--json", JSON.stringify(settings ?? {})];
        actionProcess.running = true;
        return true;
    }

    Process {
        id: statusProcess
        command: [root.executable, "status", "--json"]

        stdout: StdioCollector {
            id: statusOutput
            onStreamFinished: root.status = root.parseJson(statusOutput.text)
        }

        stderr: StdioCollector {
            id: statusError
        }

        onExited: exitCode => {
            root.statusReady = exitCode === 0;
            if (exitCode !== 0)
                root.lastError = statusError.text.trim();
        }
    }

    Process {
        id: capabilitiesProcess
        command: [root.executable, "capabilities", "--json"]

        stdout: StdioCollector {
            id: capabilitiesOutput
            onStreamFinished: root.capabilities = root.parseJson(capabilitiesOutput.text)
        }

        stderr: StdioCollector {
            id: capabilitiesError
        }

        onExited: exitCode => {
            root.capabilitiesReady = exitCode === 0;
            if (exitCode !== 0 && !root.lastError)
                root.lastError = capabilitiesError.text.trim();
        }
    }

    Process {
        id: actionProcess
        command: root.pendingActionCommand

        stdout: StdioCollector {
            id: actionOutput
            onStreamFinished: root.actionResult = root.parseJson(actionOutput.text)
        }

        stderr: StdioCollector {
            id: actionError
        }

        onExited: exitCode => {
            const success = exitCode === 0 && root.actionResult?.ok !== false;
            if (!success)
                root.lastError = root.errorMessage(root.actionResult, actionError.text.trim());
            root.actionFinished(success, root.actionResult);
            if (success)
                root.refresh();
        }
    }
}
