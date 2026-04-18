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

    function openBtop(button) {
        const cmd = (button === Qt.RightButton)
            ? "[float;size 1200 800;center] /usr/bin/kitty -T QSBtop sudo -E btop"
            : "[float;size 1200 800;center] /usr/bin/kitty -T QSBtop btop"
        Quickshell.execDetached(["hyprctl", "dispatch", "exec", cmd])
    }

    // GPU (NVIDIA via nvidia-smi -q)
    property string gpuId: "0"
    property bool gpuAvailable: true
    property bool gpuDriverMismatch: false
    property bool _gpuMismatchNotified: false
    property int gpuUtil: 0
    property int vramUsedMB: 0
    property int vramTotalMB: 0
    property int vramPercent: (vramTotalMB > 0) ? Math.round((vramUsedMB / vramTotalMB) * 100) : 0

    Timer {
        id: gpuTimer
        interval: 2000
        running: true
        repeat: true
        onTriggered: {
            gpuQuery.buf = ""
            gpuQuery.errBuf = ""
            gpuQuery.running = false
            gpuQuery.running = true
        }
    }

    Process {
        id: gpuQuery
        environment: ({ LANG: "C", LC_ALL: "C" })
        command: ["nvidia-smi", "-i", root.gpuId, "-q", "-d", "UTILIZATION,MEMORY"]
        property string buf: ""
        property string errBuf: ""
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => gpuQuery.buf += data + "\n"
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: data => gpuQuery.errBuf += data + "\n"
        }
        onExited: code => {
            const t = gpuQuery.buf
            const e = gpuQuery.errBuf
            gpuQuery.buf = ""
            gpuQuery.errBuf = ""

            if (code !== 0) {
                gpuAvailable = false
                gpuUtil = 0
                vramUsedMB = 0
                vramTotalMB = 0
                const isMismatch = (t + e).toLowerCase().includes("version mismatch")
                if (isMismatch && !root._gpuMismatchNotified) {
                    root.gpuDriverMismatch = true
                    root._gpuMismatchNotified = true
                    Quickshell.execDetached([
                        "notify-send",
                        "--urgency=critical",
                        "--icon=nvidia",
                        "GPU driver version mismatch",
                        "nvidia-smi failed: kernel module and userspace library versions differ. A reboot is required."
                    ])
                }
                return
            }
            root.gpuDriverMismatch = false
            root._gpuMismatchNotified = false
            gpuAvailable = true

            const utilM = t.match(/Gpu\s*:\s*(\d+)\s*%/i)
            if (utilM) gpuUtil = parseInt(utilM[1]) || 0

            const fbM = t.match(/FB Memory Usage[\s\S]*?Total\s*:\s*(\d+)\s*MiB[\s\S]*?Used\s*:\s*(\d+)\s*MiB/i)
            if (fbM) {
                vramTotalMB = parseInt(fbM[1]) || 0
                vramUsedMB  = parseInt(fbM[2]) || 0
            }
        }
    }

    // Network via /proc/net/dev
    property string netIface: ""
    property real downMbps: 0
    property real upMbps: 0
    property var _lastMap: ({})
    property double _lastT: 0

    // Autoscaled display values for popup
    property real netDisplayDown: 0
    property real netDisplayUp: 0
    property string netDisplayUnit: "Mbps"

    function updateNetDisplay() {
        const absMax = Math.max(Math.abs(downMbps), Math.abs(upMbps))
        var factor = 1
        var unit = "Mbps"

        if (absMax >= 1000) {
            factor = 1 / 1000
            unit = "Gbps"
        } else if (absMax >= 1) {
            factor = 1
            unit = "Mbps"
        } else if (absMax >= 0.001) {
            factor = 1000
            unit = "Kbps"
        } else {
            factor = 1000000
            unit = "bps"
        }

        netDisplayUnit = unit
        netDisplayDown = downMbps * factor
        netDisplayUp   = upMbps * factor
    }

    onDownMbpsChanged: updateNetDisplay()
    onUpMbpsChanged: updateNetDisplay()

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

            Qt.callLater(netSpark.pushSample)
        }
    }

    RowLayout {
        id: rowLayout
        spacing: 0
        anchors.fill: parent
        anchors.leftMargin: 60
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
                        var ctx = getContext("2d")
                        var w = width
                        var h = height
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
                                var v = Math.max(0, values[i])
                                var x = Math.round(i * step)
                                var y = Math.round(h - (v / netSpark.graphMax) * h)
                                if (i === 0) ctx.moveTo(x, y)
                                else ctx.lineTo(x, y)
                            }
                            ctx.stroke()
                        }

                        drawLine(netSpark.downHist, "#0091ff")
                        drawLine(netSpark.upHist,   "#ff00d4")
                    }
                }
            }
        }

        // 6) btop button
        Item {
            id: btopBtn
            Layout.leftMargin: 6
            Layout.alignment: Qt.AlignVCenter
            width: 22
            height: 22

            Rectangle {
                anchors.fill: parent
                radius: 6
                color: btopMA.containsMouse ? Appearance.colors.colLayer3 : Appearance.colors.colLayer0Hover
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: "monitor_heart"
                fill: 1
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnLayer0
            }

            MouseArea {
                id: btopMA
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: e => root.openBtop(e.button)
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

    Component.onCompleted: {
        gpuTimer.triggered()
        netTimer.triggered()
    }
}
