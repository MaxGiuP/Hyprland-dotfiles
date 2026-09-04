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
    // ResourceUsage publishes at a three-second cadence; sampling faster only
    // duplicates values and rebuilds the history arrays unnecessarily.
    property int sampleIntervalMs: 3000

    // ----------------------------
    // GPU (shared shell-wide sampler)
    // ----------------------------
    readonly property bool gpuAvailable: SystemMetrics.gpuAvailable
    readonly property int gpuUtil: SystemMetrics.gpuUtil
    readonly property int vramUsedMB: SystemMetrics.vramUsedMB
    readonly property int vramTotalMB: SystemMetrics.vramTotalMB
    readonly property int vramPercent: SystemMetrics.vramPercent

    function gpuMaxString() {
        if (!gpuAvailable || vramTotalMB <= 0) return Translation.tr("N/A")
        return (vramTotalMB / 1024).toFixed(1) + " GB"
    }

    // ----------------------------
    // Network (shared shell-wide sampler)
    // ----------------------------
    readonly property string netIface: SystemMetrics.netIface
    property real linkMaxMbps: 1000
    readonly property real downMbps: SystemMetrics.downMbps
    readonly property real upMbps: SystemMetrics.upMbps

    function netMaxString() {
        if (!Number.isFinite(linkMaxMbps) || linkMaxMbps <= 0) return Translation.tr("N/A")
        return linkMaxMbps >= 1000
            ? (linkMaxMbps / 1000).toFixed(1) + " Gbps"
            : linkMaxMbps.toFixed(0) + " Mbps"
    }

    // Optional: update link speed from sysfs if present
    FileView {
        id: sysSpeed
        path: root.netIface.length > 0 ? "/sys/class/net/" + root.netIface + "/speed" : ""
        onLoaded: {
            const speed = Number(text().trim())
            if (Number.isFinite(speed) && speed > 0)
                root.linkMaxMbps = speed
        }
    }
    function tryUpdateLinkSpeed() {
        if (!netIface || netIface.length === 0) return
        sysSpeed.reload()
    }
    onNetIfaceChanged: tryUpdateLinkSpeed()

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

            // GPU and network samples come from the shared collector.
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
        // Refresh shared data once so the overlay opens with a current sample.
        tryUpdateLinkSpeed()
        SystemMetrics.requestGpuRefresh()
        sampleTimer.triggered()
    }
}
