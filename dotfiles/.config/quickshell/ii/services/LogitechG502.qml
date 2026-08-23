pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

Singleton {
    id: root

    readonly property string bridgePath: `${Directories.scriptPath}/peripherals/logitech_g502.py`
    property var status: ({})
    property var actionResult: ({})
    property var pendingActionCommand: []
    property string lastError: ""

    readonly property bool refreshing: statusProcess.running
    readonly property bool actionRunning: actionProcess.running
    readonly property bool connected: root.status?.connected === true
    readonly property var battery: root.status?.battery ?? ({})
    readonly property var solaar: root.status?.solaar ?? ({})
    readonly property bool solaarAvailable: root.solaar?.available === true
    readonly property bool solaarSupported: root.solaar?.supported === true

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

    function controlSetting(logicalName) {
        return `${root.solaar?.controls?.[logicalName] ?? ""}`;
    }

    function controlAvailable(logicalName) {
        return root.solaarSupported && root.controlSetting(logicalName).length > 0;
    }

    function setting(logicalName) {
        const settingName = root.controlSetting(logicalName);
        return settingName ? root.solaar?.settings?.[settingName] ?? null : null;
    }

    function settingValue(logicalName, fallback = "") {
        return `${root.setting(logicalName)?.value ?? fallback}`;
    }

    function settingOptions(logicalName, fallback = []) {
        const options = root.setting(logicalName)?.options;
        return Array.isArray(options) && options.length > 0 ? options : fallback;
    }

    function refresh() {
        root.lastError = "";
        if (!statusProcess.running)
            statusProcess.running = true;
    }

    function set(logicalName, value) {
        if (!root.controlAvailable(logicalName) || actionProcess.running)
            return false;
        root.lastError = "";
        root.actionResult = ({});
        root.pendingActionCommand = ["python3", root.bridgePath, "set", logicalName, `${value}`];
        actionProcess.running = true;
        return true;
    }

    Process {
        id: statusProcess
        command: ["python3", root.bridgePath, "status"]

        stdout: StdioCollector {
            id: statusOutput
            onStreamFinished: root.status = root.parseJson(statusOutput.text)
        }

        stderr: StdioCollector {
            id: statusError
        }

        onExited: exitCode => {
            if (exitCode !== 0)
                root.lastError = statusError.text.trim();
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
            const success = exitCode === 0 && root.actionResult?.ok === true;
            if (!success)
                root.lastError = `${root.actionResult?.error?.message ?? actionError.text.trim()}`;
            root.actionFinished(success, root.actionResult);
            root.refresh();
        }
    }
}
