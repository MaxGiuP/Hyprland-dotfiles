pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property var devices: []
    property string lastError: ""
    readonly property bool loading: fetchProc.running

    // All phone notifications from available (connected) devices
    readonly property var phoneNotifications: {
        const result = [];
        for (const device of root.devices) {
            if (!device.available) continue;
            for (const notif of (device.notifications ?? [])) {
                result.push({
                    "deviceName": device.name,
                    "deviceId": device.id,
                    "appName": notif.appName ?? "",
                    "title": notif.title ?? "",
                    "text": notif.text ?? "",
                    "ticker": notif.ticker ?? "",
                    "iconPath": notif.iconPath ?? "",
                });
            }
        }
        return result;
    }

    // showPopup=false for notifications already present on startup, true for new arrivals
    signal newPhoneNotification(notif: var, showPopup: bool)
    property var _seenNotifKeys: ({})
    property bool _kdeConnectInitialized: false

    onPhoneNotificationsChanged: {
        const currentKeys = {};
        for (const notif of phoneNotifications) {
            const key = `${notif.deviceId}::${notif.appName}::${notif.title}::${notif.text}`;
            currentKeys[key] = true;
            if (!root._seenNotifKeys[key]) {
                root.newPhoneNotification(notif, root._kdeConnectInitialized);
            }
        }
        root._seenNotifKeys = currentKeys;
        root._kdeConnectInitialized = true;
    }

    function refresh() {
        fetchProc.running = false;
        fetchProc.running = true;
    }

    function runAction(args) {
        actionProc.running = false;
        root.lastError = "";
        actionProc.command = ["kdeconnect-cli", ...args];
        actionProc.running = true;
    }

    Timer {
        interval: 15000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: fetchProc
        command: ["python3", `${Directories.scriptPath}/kdeconnect_overview.py`.replace(/file:\/\//, "")]
        stdout: StdioCollector {
            id: collector
            onStreamFinished: {
                if (!collector.text || collector.text.trim().length === 0) return;
                try {
                    const payload = JSON.parse(collector.text.trim());
                    root.devices = payload.devices ?? [];
                    root.lastError = payload.error ?? "";
                } catch (e) {
                    root.lastError = `${e}`;
                }
            }
        }
    }

    Process {
        id: actionProc
        stdout: StdioCollector {
            id: actionOut
            waitForEnd: true
        }

        stderr: StdioCollector {
            id: actionErr
            waitForEnd: true
        }

        onExited: exitCode => {
            if (exitCode !== 0) {
                root.lastError = actionErr.text.trim() || actionOut.text.trim() || `kdeconnect-cli failed with code ${exitCode}`;
            }
            root.refresh();
        }
    }
}
