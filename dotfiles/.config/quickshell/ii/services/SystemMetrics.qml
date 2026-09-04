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
    property bool gpuAvailable: false
    property bool gpuDataReady: false
    property bool gpuDriverMismatch: false
    property bool gpuMismatchNotified: false
    property int gpuFailureCount: 0
    property int gpuIdleSampleCount: 0
    property bool gpuRefreshPending: false
    property double gpuLastSampleAt: 0
    property string gpuLastError: ""
    property int gpuUtil: 0
    property int vramUsedMB: 0
    property int vramTotalMB: 0
    readonly property int vramPercent: vramTotalMB > 0
        ? Math.round((vramUsedMB / vramTotalMB) * 100) : 0
    readonly property int gpuPollIntervalMs: {
        if (gpuFailureCount > 0)
            return Math.min(300000, 5000 * Math.pow(2, Math.min(gpuFailureCount, 6)));
        if (gpuIdleSampleCount >= 20)
            return 30000;
        if (gpuIdleSampleCount >= 6)
            return 15000;
        return 5000;
    }

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
    signal gpuSample(int utilization, int memoryUsedMB, int memoryTotalMB, bool available)

    function requestGpuRefresh() {
        if (gpuQuery.running) {
            root.gpuRefreshPending = true;
            return;
        }
        root.gpuRefreshPending = false;
        gpuPollTimer.stop();
        gpuQuery.output = "";
        gpuQuery.errors = "";
        gpuQuery.startConfirmed = false;
        gpuQuery.running = true;
    }

    function scheduleNextGpuRefresh() {
        if (gpuQuery.running)
            return;
        if (root.gpuRefreshPending)
            Qt.callLater(root.requestGpuRefresh);
        else
            gpuPollTimer.restart();
    }

    function recordGpuFailure(message, mismatch) {
        root.gpuDataReady = true;
        root.gpuLastSampleAt = Date.now();
        root.gpuAvailable = false;
        root.gpuFailureCount = Math.min(root.gpuFailureCount + 1, 10);
        root.gpuIdleSampleCount = 0;
        root.gpuLastError = String(message ?? "nvidia-smi failed").trim();
        root.gpuUtil = 0;
        root.vramUsedMB = 0;
        root.vramTotalMB = 0;
        root.gpuDriverMismatch = mismatch;
        if (mismatch && !root.gpuMismatchNotified) {
            root.gpuMismatchNotified = true;
            Quickshell.execDetached([
                "notify-send", "--urgency=critical", "--icon=nvidia",
                "GPU driver version mismatch",
                "nvidia-smi failed. Reboot to reload the matching kernel module."
            ]);
        }
        root.gpuSample(0, 0, 0, false);
        root.scheduleNextGpuRefresh();
    }

    Component.onCompleted: root.requestGpuRefresh()

    onGpuIdChanged: {
        root.gpuFailureCount = 0;
        root.gpuIdleSampleCount = 0;
        Qt.callLater(root.requestGpuRefresh);
    }

    Timer {
        id: gpuPollTimer
        interval: root.gpuPollIntervalMs
        repeat: false
        onTriggered: root.requestGpuRefresh()
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
        property bool startConfirmed: false
        onStarted: gpuQuery.startConfirmed = true
        onRunningChanged: {
            if (!running && !gpuQuery.startConfirmed)
                root.recordGpuFailure("Failed to start nvidia-smi", false);
            if (!running)
                gpuQuery.startConfirmed = false;
        }
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
            const rawFields = output.trim().split(",").map(value => value.trim());
            const fields = rawFields.map(value => Number(value));
            const validSample = rawFields.length >= 3
                && fields.slice(0, 3).every(value => Number.isFinite(value));

            if (code !== 0 || !validSample) {
                const mismatch = (output + error).toLowerCase().includes("version mismatch");
                const fallback = code !== 0
                    ? `nvidia-smi exited with code ${code}`
                    : "nvidia-smi returned an invalid sample";
                root.recordGpuFailure(error || output || fallback, mismatch);
                return;
            }

            root.gpuDataReady = true;
            root.gpuLastSampleAt = Date.now();
            root.gpuAvailable = true;
            root.gpuFailureCount = 0;
            root.gpuDriverMismatch = false;
            root.gpuMismatchNotified = false;
            root.gpuLastError = "";
            root.gpuUtil = Math.max(0, Math.round(fields[0]));
            root.vramUsedMB = Math.max(0, Math.round(fields[1]));
            root.vramTotalMB = Math.max(0, Math.round(fields[2]));
            root.gpuIdleSampleCount = root.gpuUtil === 0
                ? Math.min(root.gpuIdleSampleCount + 1, 100)
                : 0;
            root.gpuSample(root.gpuUtil, root.vramUsedMB, root.vramTotalMB, true);
            root.scheduleNextGpuRefresh();
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
