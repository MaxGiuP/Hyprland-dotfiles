pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

import Quickshell
import Quickshell.Hyprland
import Quickshell.Io   // Process, SplitParser, FileView

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overlay

StyledOverlayWidget {
    id: root
    minimumWidth: 300
    minimumHeight: 200

    // Sampling controls for overlay histories (does NOT change ResourceUsage)
    property int points: (ResourceUsage.historyLength && ResourceUsage.historyLength > 0) ? ResourceUsage.historyLength : 60
    property int sampleIntervalMs: 1000

    // ----------------------------
    // GPU (same approach as bar)
    // ----------------------------
    property string gpuId: "0"
    property bool gpuAvailable: true
    property int gpuUtil: 0
    property int vramUsedMB: 0
    property int vramTotalMB: 0
    property int vramPercent: (vramTotalMB > 0) ? Math.round((vramUsedMB / vramTotalMB) * 100) : 0

    function gpuMaxString() {
        if (!gpuAvailable || vramTotalMB <= 0) return Translation.tr("N/A")
        return (vramTotalMB / 1024).toFixed(1) + " GB"
    }

    Timer {
        id: gpuTimer
        interval: 2000
        running: true
        repeat: true
        onTriggered: {
            if (!gpuAvailable) return
            gpuQuery.buf = ""
            gpuQuery.running = false
            gpuQuery.running = true
        }
    }

    Process {
        id: gpuQuery
        environment: ({ LANG: "C", LC_ALL: "C" })
        command: ["nvidia-smi", "-i", root.gpuId, "-q", "-d", "UTILIZATION,MEMORY"]
        property string buf: ""
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => gpuQuery.buf += data + "\n"
        }
        onExited: code => {
            const t = gpuQuery.buf
            gpuQuery.buf = ""

            if (code !== 0) {
                root.gpuAvailable = false
                root.gpuUtil = 0
                root.vramUsedMB = 0
                root.vramTotalMB = 0
                return
            }

            root.gpuAvailable = true

            const utilM = t.match(/Gpu\s*:\s*(\d+)\s*%/i)
            if (utilM) root.gpuUtil = parseInt(utilM[1]) || 0

            const fbM = t.match(/FB Memory Usage[\s\S]*?Total\s*:\s*(\d+)\s*MiB[\s\S]*?Used\s*:\s*(\d+)\s*MiB/i)
            if (fbM) {
                root.vramTotalMB = parseInt(fbM[1]) || 0
                root.vramUsedMB  = parseInt(fbM[2]) || 0
            }
        }
    }

    // ----------------------------
    // Network (same approach as bar)
    // ----------------------------
    property string netIface: ""
    property real linkMaxMbps: 1000
    property real downMbps: 0
    property real upMbps: 0
    property var _lastMap: ({})
    property double _lastT: 0

    function netMaxString() {
        if (!Number.isFinite(linkMaxMbps) || linkMaxMbps <= 0) return Translation.tr("N/A")
        return linkMaxMbps >= 1000
            ? (linkMaxMbps / 1000).toFixed(1) + " Gbps"
            : linkMaxMbps.toFixed(0) + " Mbps"
    }

    // Optional: update link speed from sysfs if present
    FileView { id: sysSpeed; path: "" }
    function tryUpdateLinkSpeed() {
        if (!netIface || netIface.length === 0) return
        sysSpeed.path = "/sys/class/net/" + netIface + "/speed"
        sysSpeed.reload()
        const txt = (sysSpeed.text() || "").trim()
        const sp = Number(txt)
        if (Number.isFinite(sp) && sp > 0) linkMaxMbps = sp
    }

    Timer {
        id: netTimer
        interval: 1000
        repeat: true
        running: true
        onTriggered: devView.reload()
    }

    FileView {
        id: devView
        path: "/proc/net/dev"
        onLoaded: {
            const now = Date.now()
            const lines = (devView.text() || "").trim().split("\n").slice(2)

            let map = {}
            for (let i = 0; i < lines.length; i++) {
                const parts = lines[i].split(":")
                if (parts.length < 2) continue
                const iface = parts[0].trim()
                const fields = parts[1].trim().split(/\s+/)
                if (fields.length < 10) continue
                const rx = Number(fields[0])
                const tx = Number(fields[8])
                map[iface] = { rx, tx }
            }

            if (!netIface || !(netIface in map)) {
                let best = ""
                let bestSum = -1
                for (const k in map) {
                    if (k === "lo") continue
                    const sum = (map[k].rx || 0) + (map[k].tx || 0)
                    if (sum > bestSum) { best = k; bestSum = sum }
                }
                if (best) netIface = best
            }

            if (netIface && (netIface in map)) {
                const curr = map[netIface]
                if (_lastT > 0 && _lastMap[netIface]) {
                    const dt = Math.max(1e-3, (now - _lastT) / 1000.0)
                    const dRx = Math.max(0, curr.rx - _lastMap[netIface].rx)
                    const dTx = Math.max(0, curr.tx - _lastMap[netIface].tx)
                    downMbps = (dRx * 8) / 1e6 / dt
                    upMbps   = (dTx * 8) / 1e6 / dt
                }
            }

            _lastMap = map
            _lastT = now

            tryUpdateLinkSpeed()
        }
    }

    // ----------------------------
    // Overlay histories (local)
    // These are what the overlay graphs use.
    // ----------------------------
    property list<real> cpuHist: []
    property list<real> ramHist: []
    property list<real> gpuHist: []
    property list<real> swapHist: []
    property list<real> netDownHist: []
    property list<real> netUpHist: []

    function clamp01(v) {
        const n = Number(v)
        if (!Number.isFinite(n)) return 0
        if (n < 0) return 0
        if (n > 1) return 1
        return n
    }

    function push(arr, v) {
        const next = [...arr, clamp01(v)]
        if (next.length > points) next.shift()
        return next
    }

    Timer {
        id: sampleTimer
        interval: root.sampleIntervalMs
        running: true
        repeat: true
        onTriggered: {
            // Match what the bar uses
            cpuHist = push(cpuHist, ResourceUsage.cpuUsage)
            ramHist = push(ramHist, ResourceUsage.memoryUsedPercentage)
            swapHist = push(swapHist, ResourceUsage.swapUsedPercentage)

            // GPU and net in overlay are polled here too
            gpuHist = push(gpuHist, root.gpuAvailable ? (root.gpuUtil / 100) : 0)

            const lm = (Number.isFinite(root.linkMaxMbps) && root.linkMaxMbps > 0) ? root.linkMaxMbps : 0
            netDownHist = push(netDownHist, lm > 0 ? (root.downMbps / lm) : 0)
            netUpHist   = push(netUpHist,   lm > 0 ? (root.upMbps   / lm) : 0)
        }
    }

    // Tabs wired like the bar, but with overlay-owned histories
    property list<var> resources: [
        {
            "icon": "developer_board",
            "name": Translation.tr("CPU"),
            "history": root.cpuHist,
            "maxAvailableString": (ResourceUsage.maxAvailableCpuString && ResourceUsage.maxAvailableCpuString.length > 0)
                ? ResourceUsage.maxAvailableCpuString
                : Translation.tr("N/A")
        },
        {
            "icon": "memory",
            "name": Translation.tr("RAM"),
            "history": root.ramHist,
            "maxAvailableString": (ResourceUsage.maxAvailableMemoryString && ResourceUsage.maxAvailableMemoryString.length > 0)
                ? ResourceUsage.maxAvailableMemoryString
                : Translation.tr("N/A")
        },
        {
            "icon": "jamboard_kiosk",
            "name": Translation.tr("GPU"),
            "history": root.gpuHist,
            "maxAvailableString": root.gpuMaxString()
        },
        {
            "icon": "south",
            "name": Translation.tr("Net Down"),
            "history": root.netDownHist,
            "maxAvailableString": root.netMaxString()
        },
        {
            "icon": "north",
            "name": Translation.tr("Net Up"),
            "history": root.netUpHist,
            "maxAvailableString": root.netMaxString()
        },
        {
            "icon": "swap_horiz",
            "name": Translation.tr("Swap"),
            "history": root.swapHist,
            "maxAvailableString": (ResourceUsage.maxAvailableSwapString && ResourceUsage.maxAvailableSwapString.length > 0)
                ? ResourceUsage.maxAvailableSwapString
                : Translation.tr("N/A")
        }
    ]

    contentItem: OverlayBackground {
        id: contentItem
        radius: root.contentRadius
        property real padding: 4

        ColumnLayout {
            id: contentColumn
            anchors.fill: parent
            anchors.margins: parent.padding
            spacing: 8

            SecondaryTabBar {
                id: tabBar

                currentIndex: Persistent.states.overlay.resources.tabIndex
                onCurrentIndexChanged: Persistent.states.overlay.resources.tabIndex = tabBar.currentIndex

                Repeater {
                    model: root.resources.length
                    delegate: SecondaryTabButton {
                        required property int index
                        property var modelData: root.resources[index]
                        buttonIcon: modelData.icon
                        buttonText: modelData.name
                    }
                }
            }

            ResourceSummary {
                Layout.margins: 8
                history: root.resources[tabBar.currentIndex]?.history ?? []
                maxAvailableString: root.resources[tabBar.currentIndex]?.maxAvailableString ?? Translation.tr("N/A")
            }
        }
    }

    component ResourceSummary: RowLayout {
        id: resourceSummary
        required property list<real> history
        required property string maxAvailableString
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 12

        readonly property real lastValue: {
            if (!history || history.length <= 0) return 0
            const v = Number(history[history.length - 1])
            return Number.isFinite(v) ? v : 0
        }

        ColumnLayout {
            spacing: 2
            StyledText {
                text: (resourceSummary.lastValue * 100).toFixed(1) + "%"
                font {
                    family: Appearance.font.family.numbers
                    variableAxes: Appearance.font.variableAxes.numbers
                    pixelSize: Appearance.font.pixelSize.huge
                }
            }
            StyledText {
                text: Translation.tr("of %1").arg(resourceSummary.maxAvailableString)
                font.pixelSize: Appearance.font.pixelSize.smallie
                color: Appearance.colors.colSubtext
            }
            Item { Layout.fillHeight: true }
        }

        Rectangle {
            id: graphBg
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Appearance.rounding.small
            color: Appearance.colors.colSecondaryContainer
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: graphBg.width
                    height: graphBg.height
                    radius: graphBg.radius
                }
            }
            Graph {
                anchors.fill: parent
                values: resourceSummary.history ?? []
                points: root.points
                alignment: Graph.Alignment.Right
            }
        }
    }

    Component.onCompleted: {
        // Kick initial polls so overlay has data immediately
        gpuTimer.triggered()
        netTimer.triggered()
        sampleTimer.triggered()
    }
}
