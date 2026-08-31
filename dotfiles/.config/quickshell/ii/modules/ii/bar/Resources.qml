import qs.modules.common
import qs.modules.common.widgets
import qs.services 1.0 as Services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

MouseArea {
    id: root
    property bool borderless: Config.options.bar.borderless
    property bool alwaysShowAllResources: false
    implicitWidth: rowLayout.implicitWidth + rowLayout.anchors.leftMargin + rowLayout.anchors.rightMargin
    implicitHeight: Appearance.sizes.barHeight
    hoverEnabled: !Config.options.bar.tooltips.clickToShow
    acceptedButtons: Qt.NoButton

    function openTaskManager() {
        Quickshell.execDetached(["bash", "-lc", Config.options.apps.taskManager])
    }

    readonly property string gpuId: Services.SystemMetrics.gpuId
    readonly property bool gpuAvailable: Services.SystemMetrics.gpuAvailable
    readonly property bool gpuDriverMismatch: Services.SystemMetrics.gpuDriverMismatch
    readonly property int gpuUtil: Services.SystemMetrics.gpuUtil
    readonly property int vramUsedMB: Services.SystemMetrics.vramUsedMB
    readonly property int vramTotalMB: Services.SystemMetrics.vramTotalMB
    readonly property int vramPercent: Services.SystemMetrics.vramPercent
    readonly property string netIface: Services.SystemMetrics.netIface
    readonly property real downMbps: Services.SystemMetrics.downMbps
    readonly property real upMbps: Services.SystemMetrics.upMbps
    readonly property real netDisplayDown: Services.SystemMetrics.netDisplayDown
    readonly property real netDisplayUp: Services.SystemMetrics.netDisplayUp
    readonly property string netDisplayUnit: Services.SystemMetrics.netDisplayUnit

    RowLayout {
        id: rowLayout
        spacing: 0
        anchors.fill: parent
        anchors.leftMargin: 0
        anchors.rightMargin: 0

        // 1) CPU total
        Resource {
            iconName: "developer_board"
            percentage: Services.ResourceUsage.cpuUsage
            shown: Config.options.bar.resources.alwaysShowCpu ||
                   !(Services.MprisController.activePlayer?.trackTitle?.length > 0) ||
                   root.alwaysShowAllResources
            warningThreshold: Config.options.bar.resources.cpuWarningThreshold
        }

        // 2) RAM
        Resource {
            iconName: "memory"
            percentage: Services.ResourceUsage.memoryUsedPercentage
            Layout.leftMargin: 6
            warningThreshold: Config.options.bar.resources.memoryWarningThreshold
        }

        // 3) GPU
        Resource {
            iconName: root.gpuDriverMismatch ? "warning" : "jamboard_kiosk"
            percentage: root.gpuDriverMismatch ? 1.0 : Math.max(0, Math.min(1, root.gpuUtil / 100))
            shown: root.gpuAvailable || root.gpuDriverMismatch
            Layout.leftMargin: shown ? 6 : 0
            warningThreshold: root.gpuDriverMismatch ? 0 : (Config.options?.bar?.resources?.gpuWarningThreshold ?? 90)
        }

        // 4) SWAP
        Resource {
            iconName: "swap_horiz"
            percentage: Services.ResourceUsage.swapUsedPercentage
            shown: (Config.options.bar.resources.alwaysShowSwap && (Services.ResourceUsage.swapTotal || 0) > 0) ||
                   !(Services.MprisController.activePlayer?.trackTitle?.length > 0) ||
                   root.alwaysShowAllResources
            Layout.leftMargin: shown ? 6 : 0
            warningThreshold: Config.options.bar.resources.swapWarningThreshold
        }

        // 5) Network sparkline
        Item {
            id: netSlot
            Layout.leftMargin: 0
            Layout.alignment: Qt.AlignVCenter
            width: 50
            height: parent.height

            Item {
                id: netSpark
                anchors.centerIn: parent
                width: parent.width
                height: 16

                property int maxPoints: 48
                property var downHist: []
                property var upHist: []
                property bool autoscale: true
                property real graphMax: 1

                function recomputeGraphMax() {
                    if (!autoscale) { graphMax = 1; return }
                    var m = Math.max(Math.abs(root.downMbps), Math.abs(root.upMbps))
                    if (m <= 0) { graphMax = 1; return }

                    var exp = Math.floor(Math.log(m) / Math.LN10)
                    var base = Math.pow(10, exp)
                    var norm = m / base
                    var niceNorm
                    if (norm <= 1)      niceNorm = 1
                    else if (norm <= 2) niceNorm = 2
                    else if (norm <= 5) niceNorm = 5
                    else                niceNorm = 10
                    graphMax = niceNorm * base
                }

                function pushSample() {
                    downHist.push(root.downMbps || 0)
                    upHist.push(root.upMbps || 0)
                    if (downHist.length > maxPoints) downHist.shift()
                    if (upHist.length > maxPoints) upHist.shift()
                    recomputeGraphMax()
                    canvas.requestPaint()
                }

                Canvas {
                    id: canvas
                    anchors.fill: parent
                    onPaint: {
                        const paintWidth = Number(width)
                        const paintHeight = Number(height)
                        if (!Number.isFinite(paintWidth) || !Number.isFinite(paintHeight) || paintWidth <= 0 || paintHeight <= 0)
                            return

                        var ctx = getContext("2d")
                        if (!ctx)
                            return

                        var w = paintWidth
                        var h = paintHeight
                        ctx.resetTransform()
                        ctx.clearRect(0, 0, w, h)

                        ctx.globalAlpha = 0.25
                        ctx.strokeStyle = Appearance.colors.colOnLayer2
                        ctx.lineWidth = 1
                        ctx.beginPath()
                        ctx.moveTo(0, h - 0.5)
                        ctx.lineTo(w, h - 0.5)
                        ctx.stroke()

                        function drawLine(values, stroke) {
                            if (!values.length || netSpark.graphMax <= 0) return
                            var step = (w - 1) / Math.max(1, netSpark.maxPoints - 1)
                            ctx.globalAlpha = 1.0
                            ctx.strokeStyle = stroke
                            ctx.lineWidth = 2
                            ctx.beginPath()
                            for (var i = 0; i < values.length; i++) {
                                var v = Math.max(0, Number(values[i]) || 0)
                                var x = Math.round(i * step)
                                var y = Math.round(h - (v / netSpark.graphMax) * h)
                                if (!Number.isFinite(x) || !Number.isFinite(y))
                                    continue
                                if (i === 0) ctx.moveTo(x, y)
                                else ctx.lineTo(x, y)
                            }
                            ctx.stroke()
                        }

                        drawLine(netSpark.downHist, "#0091ff")
                        drawLine(netSpark.upHist,   "#ff00d4")
                    }
                }

                Connections {
                    target: Services.SystemMetrics
                    function onNetworkSample() { netSpark.pushSample(); }
                }
            }
        }

        // 6) Task manager button
        Item {
            id: taskManagerBtn
            Layout.leftMargin: 6
            Layout.alignment: Qt.AlignVCenter
            width: 22
            height: 22

            Rectangle {
                anchors.fill: parent
                radius: 6
                color: taskManagerMA.containsMouse ? Appearance.colors.colLayer3 : Appearance.colors.colLayer0Hover
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: "monitor_heart"
                fill: 1
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnLayer0
            }

            MouseArea {
                id: taskManagerMA
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton
                onClicked: root.openTaskManager()
            }
        }
    }

    ResourcesPopup {
        hoverTarget: root

        gpuAvailable: root.gpuAvailable
        gpuDriverMismatch: root.gpuDriverMismatch
        gpuId: root.gpuId
        gpuUtil: root.gpuUtil
        vramUsedMB: root.vramUsedMB
        vramTotalMB: root.vramTotalMB
        vramPercent: root.vramPercent

        netIface: root.netIface
        downMbps: root.downMbps
        upMbps: root.upMbps
        netDisplayDown: root.netDisplayDown
        netDisplayUp: root.netDisplayUp
        netDisplayUnit: root.netDisplayUnit
    }

}
