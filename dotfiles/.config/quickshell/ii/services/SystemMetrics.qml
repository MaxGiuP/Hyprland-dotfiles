pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

// Resource metrics that are not exposed by ResourceUsage live here once for the
// whole shell. Bar instances only bind to these values instead of each monitor
// spawning its own nvidia-smi process and /proc/net/dev reader.
Singleton {
    id: root

    property string gpuId: "0"
    property bool gpuAvailable: true
    property bool gpuDriverMismatch: false
    property bool gpuMismatchNotified: false
    property int gpuUtil: 0
    property int vramUsedMB: 0
    property int vramTotalMB: 0
    readonly property int vramPercent: vramTotalMB > 0
        ? Math.round((vramUsedMB / vramTotalMB) * 100) : 0

    property string netIface: ""
    property real downMbps: 0
    property real upMbps: 0
    property var lastNetMap: ({})
    property double lastNetTimestamp: 0
    readonly property real netDisplayFactor: {
        const maximum = Math.max(Math.abs(downMbps), Math.abs(upMbps));
        if (maximum >= 1000) return 1 / 1000;
        if (maximum >= 1) return 1;
        if (maximum >= 0.001) return 1000;
        return 1000000;
    }
    readonly property string netDisplayUnit: {
        const maximum = Math.max(Math.abs(downMbps), Math.abs(upMbps));
        if (maximum >= 1000) return "Gbps";
        if (maximum >= 1) return "Mbps";
        if (maximum >= 0.001) return "Kbps";
        return "bps";
    }
    readonly property real netDisplayDown: downMbps * netDisplayFactor
    readonly property real netDisplayUp: upMbps * netDisplayFactor

    signal networkSample(real downMbps, real upMbps)

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!gpuQuery.running) {
                gpuQuery.output = "";
                gpuQuery.errors = "";
                gpuQuery.running = true;
            }
        }
    }

    Process {
        id: gpuQuery
        environment: ({ LANG: "C", LC_ALL: "C" })
        command: [
            "nvidia-smi", "-i", root.gpuId,
            "--query-gpu=utilization.gpu,memory.used,memory.total",
            "--format=csv,noheader,nounits"
        ]
        property string output: ""
        property string errors: ""
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => gpuQuery.output += data + "\n"
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: data => gpuQuery.errors += data + "\n"
        }
        onExited: code => {
            const output = gpuQuery.output;
            const error = gpuQuery.errors;
            if (code !== 0) {
                root.gpuAvailable = false;
                root.gpuUtil = 0;
                root.vramUsedMB = 0;
                root.vramTotalMB = 0;
                const mismatch = (output + error).toLowerCase().includes("version mismatch");
                root.gpuDriverMismatch = mismatch;
                if (mismatch && !root.gpuMismatchNotified) {
                    root.gpuMismatchNotified = true;
                    Quickshell.execDetached([
                        "notify-send", "--urgency=critical", "--icon=nvidia",
                        "GPU driver version mismatch",
                        "nvidia-smi failed. Reboot to reload the matching kernel module."
                    ]);
                }
                return;
            }

            root.gpuAvailable = true;
            root.gpuDriverMismatch = false;
            root.gpuMismatchNotified = false;
            const fields = output.trim().split(",").map(value => parseInt(value.trim()) || 0);
            root.gpuUtil = fields[0] ?? 0;
            root.vramUsedMB = fields[1] ?? 0;
            root.vramTotalMB = fields[2] ?? 0;
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: netDeviceView.reload()
    }

    FileView {
        id: netDeviceView
        path: "/proc/net/dev"
        onLoaded: {
            const now = Date.now();
            const lines = (netDeviceView.text() || "").trim().split("\n").slice(2);
            const current = {};
            for (const line of lines) {
                const parts = line.split(":");
                if (parts.length < 2) continue;
                const iface = parts[0].trim();
                const fields = parts[1].trim().split(/\s+/);
                if (fields.length < 10) continue;
                current[iface] = { rx: Number(fields[0]), tx: Number(fields[8]) };
            }

            if (!root.netIface || !(root.netIface in current)) {
                let best = "";
                let bestTraffic = -1;
                for (const iface in current) {
                    if (iface === "lo") continue;
                    const traffic = (current[iface].rx || 0) + (current[iface].tx || 0);
                    if (traffic > bestTraffic) {
                        best = iface;
                        bestTraffic = traffic;
                    }
                }
                root.netIface = best;
            }

            if (root.netIface && current[root.netIface]) {
                const previous = root.lastNetMap[root.netIface];
                if (root.lastNetTimestamp > 0 && previous) {
                    const elapsed = Math.max(0.001, (now - root.lastNetTimestamp) / 1000);
                    root.downMbps = Math.max(0, current[root.netIface].rx - previous.rx) * 8 / 1e6 / elapsed;
                    root.upMbps = Math.max(0, current[root.netIface].tx - previous.tx) * 8 / 1e6 / elapsed;
                    root.networkSample(root.downMbps, root.upMbps);
                }
            }
            root.lastNetMap = current;
            root.lastNetTimestamp = now;
        }
    }
}
