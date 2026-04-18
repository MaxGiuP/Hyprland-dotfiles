import qs.modules.common
import qs.modules.common.widgets
import qs.services 1.0 as Services
import QtQuick
import QtQuick.Layouts

StyledPopup {
    id: root

    // GPU values passed in from Resources.qml
    property bool gpuAvailable: false
    property bool gpuDriverMismatch: false
    property string gpuId: ""
    property int gpuUtil: 0
    property int vramUsedMB: 0
    property int vramTotalMB: 0
    property int vramPercent: 0

    // Network values passed in from Resources.qml
    property string netIface: ""
    property real downMbps: 0
    property real upMbps: 0
    property real netDisplayDown: 0
    property real netDisplayUp: 0
    property string netDisplayUnit: "Mbps"

    function formatKB(kb) {
        return (kb / (1024 * 1024)).toFixed(1) + " GB"
    }
    function formatMBToGB(mb) {
        return (mb / 1024).toFixed(1) + " GB"
    }

    Row {
        anchors.centerIn: parent
        spacing: 12

        // CPU
        Column {
            anchors.top: parent.top
            spacing: 8

            StyledPopupHeaderRow { icon: "developer_board"; label: Services.Translation.tr("CPU") }

            Column {
                spacing: 4

                StyledPopupValueRow {
                    icon: "bolt"
                    label: Services.Translation.tr("Load:")
                    value: `${Math.round((Services.ResourceUsage.cpuUsage || 0) * 100)}%`
                }

                StyledPopupValueRow {
                    visible: (Services.ResourceUsage.groupsReady ?? false) && ((Services.ResourceUsage.perfCores?.length ?? 0) > 0)
                    icon: "speed"
                    label: Services.Translation.tr("Perf:")
                    value: `${Math.round((Services.ResourceUsage.perfUsage || 0) * 100)}%`
                }

                StyledPopupValueRow {
                    visible: (Services.ResourceUsage.groupsReady ?? false) && ((Services.ResourceUsage.effCores?.length ?? 0) > 0)
                    icon: "eco"
                    label: Services.Translation.tr("Eff:")
                    value: `${Math.round((Services.ResourceUsage.effUsage || 0) * 100)}%`
                }

                StyledPopupValueRow {
                    icon: "memory"
                    label: Services.Translation.tr("Threads:")
                    value: `${Services.ResourceUsage.logicalCpuCount || 0}`
                }

                StyledPopupValueRow {
                    icon: "speed"
                    label: Services.Translation.tr("Max:")
                    value: Services.ResourceUsage.maxAvailableCpuString
                }
            }
        }

        // RAM
        Column {
            anchors.top: parent.top
            spacing: 8

            StyledPopupHeaderRow { icon: "memory"; label: Services.Translation.tr("RAM") }

            Column {
                spacing: 4
                StyledPopupValueRow { icon: "clock_loader_60"; label: Services.Translation.tr("Used:");  value: root.formatKB(Services.ResourceUsage.memoryUsed || 0) }
                StyledPopupValueRow { icon: "check_circle";     label: Services.Translation.tr("Free:");  value: root.formatKB(Services.ResourceUsage.memoryFree || 0) }
                StyledPopupValueRow { icon: "empty_dashboard";  label: Services.Translation.tr("Total:"); value: root.formatKB(Services.ResourceUsage.memoryTotal || 0) }
                StyledPopupValueRow { icon: "shield";           label: Services.Translation.tr("Max:");   value: Services.ResourceUsage.maxAvailableMemoryString }
            }
        }

        // GPU
        Column {
            anchors.top: parent.top
            spacing: 8

            StyledPopupHeaderRow { icon: "jamboard_kiosk"; label: Services.Translation.tr("GPU") }

            Column {
                spacing: 4

                StyledPopupValueRow {
                    visible: root.gpuDriverMismatch
                    icon: "warning"
                    label: Services.Translation.tr("Driver mismatch")
                    value: Services.Translation.tr("Reboot required")
                }

                StyledPopupValueRow {
                    visible: !root.gpuDriverMismatch
                    icon: "bolt"
                    label: Services.Translation.tr("Util:")
                    value: root.gpuAvailable ? `${root.gpuUtil}%` : Services.Translation.tr("N/A")
                }

                StyledPopupValueRow {
                    visible: !root.gpuDriverMismatch
                    icon: "memory"
                    label: Services.Translation.tr("VRAM:")
                    value: root.gpuAvailable
                        ? `${root.formatMBToGB(root.vramUsedMB)} / ${root.formatMBToGB(root.vramTotalMB)}`
                        : Services.Translation.tr("N/A")
                }

                StyledPopupValueRow {
                    visible: !root.gpuDriverMismatch
                    icon: "pie_chart"
                    label: Services.Translation.tr("VRAM %:")
                    value: root.gpuAvailable ? `${root.vramPercent}%` : Services.Translation.tr("N/A")
                }

                StyledPopupValueRow {
                    visible: !root.gpuDriverMismatch && root.gpuAvailable && (root.gpuId || "") !== ""
                    icon: "tag"
                    label: Services.Translation.tr("GPU ID:")
                    value: `${root.gpuId}`
                }
            }
        }

        // Net
        Column {
            anchors.top: parent.top
            spacing: 8

            StyledPopupHeaderRow { icon: "network_check"; label: "Net" }

            Column {
                spacing: 4

                StyledPopupValueRow {
                    icon: "badge"
                    label: Services.Translation.tr("Iface:")
                    value: (root.netIface || "").length > 0 ? root.netIface : Services.Translation.tr("N/A")
                }

                StyledPopupValueRow {
                    icon: "south"
                    label: Services.Translation.tr("Down:")
                    value: `${(root.netDisplayDown || 0).toFixed(1)} ${root.netDisplayUnit}`
                }

                StyledPopupValueRow {
                    icon: "north"
                    label: Services.Translation.tr("Up:")
                    value: `${(root.netDisplayUp || 0).toFixed(1)} ${root.netDisplayUnit}`
                }
            }
        }

        // Swap
        Column {
            visible: (Services.ResourceUsage.swapTotal || 0) > 0
            anchors.top: parent.top
            spacing: 8

            StyledPopupHeaderRow { icon: "swap_horiz"; label: Services.Translation.tr("Swap") }

            Column {
                spacing: 4
                StyledPopupValueRow { icon: "clock_loader_60"; label: Services.Translation.tr("Used:");  value: root.formatKB(Services.ResourceUsage.swapUsed || 0) }
                StyledPopupValueRow { icon: "check_circle";     label: Services.Translation.tr("Free:");  value: root.formatKB(Services.ResourceUsage.swapFree || 0) }
                StyledPopupValueRow { icon: "empty_dashboard";  label: Services.Translation.tr("Total:"); value: root.formatKB(Services.ResourceUsage.swapTotal || 0) }
                StyledPopupValueRow { icon: "shield";           label: Services.Translation.tr("Max:");   value: Services.ResourceUsage.maxAvailableSwapString }
            }
        }
    }
}
