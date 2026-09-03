pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string scriptPath: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/system/system-health.sh`
    property var services: ({
        "quickshell.service": "unknown",
        "kdeconnect-bridge.service": "unknown",
        "tv-mode-daemon.service": "unknown",
        "kdeconnect-cursor-sync.service": "unknown"
    })
    property int diskPercent: 0
    property int temperature: 0
    property int warningCount: 0
    property int crashCount: 0
    property string powerProfile: "unknown"
    property double lastRefresh: 0
    readonly property int unhealthyServices: Object.values(services).filter(state => state !== "active").length
    readonly property bool healthy: unhealthyServices === 0 && crashCount === 0 && diskPercent < 90 && temperature < 90

    function refresh() {
        if (!snapshot.running)
            snapshot.running = true;
    }

    function restartBridges() {
        bridgeRestart.running = false;
        bridgeRestart.running = true;
    }

    function openLogs() {
        Quickshell.execDetached([root.scriptPath, "open-logs"]);
    }

    Timer {
        // The snapshot scans services and the boot journal; minute-level
        // polling produced no useful UI precision and repeatedly did heavy IO.
        interval: 5 * 60 * 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: snapshot
        command: [root.scriptPath, "snapshot"]
        property var nextServices: ({})
        property int nextDiskPercent: 0
        property int nextTemperature: 0
        property int nextWarningCount: 0
        property int nextCrashCount: 0
        property string nextPowerProfile: "unknown"
        property bool snapshotComplete: false
        onRunningChanged: if (running) {
            nextServices = ({});
            nextDiskPercent = 0;
            nextTemperature = 0;
            nextWarningCount = 0;
            nextCrashCount = 0;
            nextPowerProfile = "unknown";
            snapshotComplete = false;
        }
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                const fields = line.split("\t");
                if (fields[0] === "service" && fields.length >= 3) {
                    const next = Object.assign({}, snapshot.nextServices);
                    next[fields[1]] = fields[2];
                    snapshot.nextServices = next;
                } else if (fields[0] === "disk") snapshot.nextDiskPercent = Number(fields[1]) || 0;
                else if (fields[0] === "temperature") snapshot.nextTemperature = Number(fields[1]) || 0;
                else if (fields[0] === "warnings") snapshot.nextWarningCount = Number(fields[1]) || 0;
                else if (fields[0] === "crashes") snapshot.nextCrashCount = Number(fields[1]) || 0;
                else if (fields[0] === "power") snapshot.nextPowerProfile = fields[1] || "unknown";
                else if (fields[0] === "complete") snapshot.snapshotComplete = fields[1] === "1";
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0 && snapshot.snapshotComplete) {
                root.services = snapshot.nextServices;
                root.diskPercent = snapshot.nextDiskPercent;
                root.temperature = snapshot.nextTemperature;
                root.warningCount = snapshot.nextWarningCount;
                root.crashCount = snapshot.nextCrashCount;
                root.powerProfile = snapshot.nextPowerProfile;
                root.lastRefresh = Date.now();
            }
        }
    }

    Process {
        id: bridgeRestart
        command: [root.scriptPath, "restart-bridges"]
        onExited: refreshDelay.restart()
    }

    Timer {
        id: refreshDelay
        interval: 700
        repeat: false
        onTriggered: root.refresh()
    }
}
