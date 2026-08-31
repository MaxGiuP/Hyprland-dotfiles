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
    property var services: ({})
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
        interval: 60000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: snapshot
        command: [root.scriptPath, "snapshot"]
        property var nextServices: ({})
        onRunningChanged: if (running) nextServices = ({})
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                const fields = line.split("\t");
                if (fields[0] === "service" && fields.length >= 3) {
                    const next = Object.assign({}, snapshot.nextServices);
                    next[fields[1]] = fields[2];
                    snapshot.nextServices = next;
                } else if (fields[0] === "disk") root.diskPercent = Number(fields[1]) || 0;
                else if (fields[0] === "temperature") root.temperature = Number(fields[1]) || 0;
                else if (fields[0] === "warnings") root.warningCount = Number(fields[1]) || 0;
                else if (fields[0] === "crashes") root.crashCount = Number(fields[1]) || 0;
                else if (fields[0] === "power") root.powerProfile = fields[1] || "unknown";
            }
        }
        onExited: {
            root.services = snapshot.nextServices;
            root.lastRefresh = Date.now();
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
