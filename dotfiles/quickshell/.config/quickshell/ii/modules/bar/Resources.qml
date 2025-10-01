import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io    // for Process / SplitParser

Item {
    id: root
    property bool borderless: Config.options.bar.borderless
    property bool alwaysShowAllResources: false
    implicitWidth: rowLayout.implicitWidth + rowLayout.anchors.leftMargin + rowLayout.anchors.rightMargin
    implicitHeight: 32
    clip: false

    function openBtop(button) {
        const tail = button === Qt.RightButton
            ? ["kitty","--","sudo","-E","btop"]
            : ["kitty","--","btop"];
        Quickshell.execDetached(["hyprctl","dispatch","exec","[float;size 1200 800;center]", ...tail]);
    }

    // ── GPU stats ────────────────────────────────────────────────────────────────
    property string gpuId: "0"
    property int gpuUtil: 0
    property int vramPercent: 0
    property int vramUsedMB: 0
    property int vramTotalMB: 0

    Timer {
        id: gpuTimer
        interval: 2000
        running: true
        repeat: true
        onTriggered: { gpuQuery.running = false; gpuQuery.running = true }
    }
    Process {
        id: gpuQuery
        command: [
            "nvidia-smi", "-i", root.gpuId,
            "--query-gpu=utilization.gpu,memory.used,memory.total",
            "--format=csv,noheader,nounits"
        ]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: {
                const line = data.trim(); if (!line) return;
                const p = line.split(/,\s*/);
                const util  = parseInt(p[0]) || 0;
                const used  = parseInt(p[1]) || 0;
                const total = parseInt(p[2]) || 0;
                root.gpuUtil     = util;
                root.vramUsedMB  = used;
                root.vramTotalMB = total;
                root.vramPercent = total > 0 ? Math.round((used / total) * 100) : 0;
            }
        }
        onExited: (code) => {
            if (code !== 0) { gpuTimer.running = false; console.log("[bar] nvidia-smi failed (code " + code + ")") }
        }
    }

    // ── Network via /proc/net/dev ───────────────────────────────────────────────
    property string netIface: ""
    property real   linkMaxMbps: 1000
    property real   downMbps: 0
    property real   upMbps: 0
    property var    _lastMap: ({})
    property double _lastT: 0

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
            const now = Date.now();
            const lines = (devView.text() || "").trim().split("\n").slice(2);

            let map = {};
            for (let i = 0; i < lines.length; i++) {
                const parts = lines[i].split(":");
                if (parts.length < 2) continue;
                const iface = parts[0].trim();
                const fields = parts[1].trim().split(/\s+/);
                if (fields.length < 10) continue;
                const rx = Number(fields[0]);
                const tx = Number(fields[8]);
                map[iface] = { rx, tx };
            }

            if (!netIface || !(netIface in map)) {
                let best = ""; let bestSum = -1;
                for (const k in map) {
                    if (k === "lo") continue;
                    const sum = (map[k].rx || 0) + (map[k].tx || 0);
                    if (sum > bestSum) { best = k; bestSum = sum; }
                }
                if (best) { netIface = best; console.log("[net] auto-selected iface:", netIface); }
            }

            if (netIface && (netIface in map)) {
                const curr = map[netIface];
                if (_lastT > 0 && _lastMap[netIface]) {
                    const dt  = Math.max(1e-3, (now - _lastT) / 1000.0);
                    const dRx = Math.max(0, curr.rx - _lastMap[netIface].rx);
                    const dTx = Math.max(0, curr.tx - _lastMap[netIface].tx);
                    downMbps = (dRx * 8) / 1e6 / dt;
                    upMbps   = (dTx * 8) / 1e6 / dt;
                }
            }
            _lastMap = map; _lastT = now;
        }
    }

    // ── UI ──────────────────────────────────────────────────────────────────────
    RowLayout {
        id: rowLayout
        spacing: 4
        anchors.fill: parent
        anchors.leftMargin: 4
        anchors.rightMargin: 4
        clip: false

        // CPU
        Item {
            id: cpuSlot
            Layout.alignment: Qt.AlignVCenter
            width: cpuRes.implicitWidth; height: parent.height
            Resource {
                id: cpuRes
                anchors.fill: parent
                iconName: "memory"
                percentage: ResourceUsage.cpuUsage
            }
            HoverHandler { id: hhCPU; acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onHoveredChanged: { if (hovered) lingerCPU.stop(); else lingerCPU.restart(); } }
            Timer { id: lingerCPU; interval: 150; repeat: false }
        }
        StyledToolTip {
            verticalPadding: -20
            parent: root; z: 10000
            x: cpuSlot.mapToItem(root, cpuSlot.width/2, 0).x - width/2
            y: cpuSlot.mapToItem(root, 0, cpuSlot.height).y + 6
            visible: hhCPU.hovered || lingerCPU.running
            content: "CPU - Perf: " + ResourceUsage.perfUsagePercent + "% Eff: " + ResourceUsage.effUsagePercent + "%"
        }

        // RAM
        Item {
            id: ramSlot
            Layout.alignment: Qt.AlignVCenter
            width: ramRes.implicitWidth; height: parent.height
            Resource {
                id: ramRes
                anchors.fill: parent
                iconName: "memory_alt"
                percentage: ResourceUsage.memoryUsedPercentage
            }
            HoverHandler { id: hhRAM; acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onHoveredChanged: { if (hovered) lingerRAM.stop(); else lingerRAM.restart(); } }
            Timer { id: lingerRAM; interval: 150; repeat: false }
        }
        StyledToolTip {
            verticalPadding: 56
            parent: root; z: 10000
            x: ramSlot.mapToItem(root, ramSlot.width/2, 0).x - width/2
            y: ramSlot.mapToItem(root, 0, ramSlot.height).y + 6
            visible: hhRAM.hovered || lingerRAM.running
            content: "RAM: " +
                ((ResourceUsage.memoryTotal - ResourceUsage.memoryFree) / 1000000 || 0).toFixed(1) +
                " / " + (ResourceUsage.memoryTotal / 1000000 || 0).toFixed(1) + " GB"
        }

        // GPU
        Item {
            id: gpuSlot
            Layout.alignment: Qt.AlignVCenter
            width: gpuRes.implicitWidth; height: parent.height
            Resource {
                id: gpuRes
                anchors.fill: parent
                iconName: "jamboard_kiosk"
                percentage: root.gpuUtil / 100
            }
            HoverHandler { id: hhGPU; acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onHoveredChanged: { if (hovered) lingerGPU.stop(); else lingerGPU.restart(); } }
            Timer { id: lingerGPU; interval: 150; repeat: false }
        }
        StyledToolTip {
            verticalPadding: 58
            parent: root; z: 10000
            x: gpuSlot.mapToItem(root, gpuSlot.width/2, 0).x - width/2
            y: gpuSlot.mapToItem(root, 0, gpuSlot.height).y + 6
            visible: hhGPU.hovered || lingerGPU.running
            content: "              GPU\nVRAM: " +
                (root.vramUsedMB / 1000 || 0).toFixed(1) + " / " +
                (root.vramTotalMB / 1000 || 0).toFixed(1) + " GB"
        }

        // Net sparkline (tooltip only; no click-to-open here)
        Item {
            id: netSlot
            Layout.alignment: Qt.AlignVCenter
            width: 50; height: parent.height

            Item {
                id: netSpark
                anchors.centerIn: parent
                width: parent.width; height: 16

                property int  maxPoints: 48
                property var  downHist: []
                property var  upHist:   []
                property bool autoscale: true
                property real graphMax: {
                    if (!autoscale) return Math.max(1, linkMaxMbps);
                    var m = 1;
                    for (var i = 0; i < downHist.length; i++) m = Math.max(m, downHist[i]);
                    for (var j = 0; j < upHist.length;   j++) m = Math.max(m, upHist[j]);
                    return m;
                }

                function pushSample() {
                    downHist.push(downMbps || 0);
                    upHist.push(upMbps   || 0);
                    if (downHist.length > maxPoints) downHist.shift();
                    if (upHist.length   > maxPoints) upHist.shift();
                    canvas.requestPaint();
                }
                Connections { target: devView; function onLoaded() { Qt.callLater(netSpark.pushSample) } }

                Canvas {
                    id: canvas
                    anchors.fill: parent
                    onPaint: {
                        var ctx = getContext("2d");
                        var w = width, h = height;
                        ctx.resetTransform(); ctx.clearRect(0,0,w,h);

                        ctx.globalAlpha = 0.25;
                        ctx.strokeStyle = Appearance.colors.colOnLayer2;
                        ctx.lineWidth = 1;
                        ctx.beginPath(); ctx.moveTo(0, h-0.5); ctx.lineTo(w, h-0.5); ctx.stroke();

                        function drawLine(values, color) {
                            if (!values.length || netSpark.graphMax <= 0) return;
                            var step = (w - 1) / Math.max(1, netSpark.maxPoints - 1);
                            ctx.globalAlpha = 1.0;
                            ctx.strokeStyle = color;
                            ctx.lineWidth = 2;
                            ctx.beginPath();
                            for (var i = 0; i < values.length; i++) {
                                var v = Math.max(0, values[i]);
                                var x = Math.round(i * step);
                                var y = Math.round(h - (v / netSpark.graphMax) * h);
                                if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
                            }
                            ctx.stroke();
                        }

                        drawLine(netSpark.downHist, '#0091ff');
                        drawLine(netSpark.upHist,   '#ff00d4');
                    }
                }

                HoverHandler { id: hhNet; acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onHoveredChanged: { if (hovered) lingerNet.stop(); else lingerNet.restart(); } }
                Timer { id: lingerNet; interval: 150; repeat: false }
            }
        }
        StyledToolTip {
            verticalPadding: 56
            parent: root; z: 10000
            x: netSlot.mapToItem(root, netSlot.width/2, 0).x + 100
            y: netSlot.mapToItem(root, 0, netSlot.height).y + 6
            visible: hhNet.hovered || lingerNet.running
            content: "↓ " + (downMbps||0).toFixed(1) + " / ↑ " + (upMbps||0).toFixed(1) + " Mbps"
        }

        // ── btop launcher button (separate, at the right) ───────────────────────
        Item {
            id: btopBtn
            Layout.alignment: Qt.AlignVCenter
            width: 28; height: 28
            Rectangle {
                anchors.fill: parent
                radius: 6
                color: btopMA.containsMouse ? Appearance.colors.colLayer3 : Appearance.colors.colLayer3Hover
            }
            MaterialSymbol {
                anchors.centerIn: parent
                text: "monitor_heart"     // pick any icon you like
                iconSize: 18
                color: Appearance.colors.colOnLayer0
            }
            MouseArea {
                id: btopMA
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: (e) => root.openBtop(e.button)
            }
            HoverHandler { id: hhBtn; acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onHoveredChanged: { if (hovered) lingerBtn.stop(); else lingerBtn.restart(); } }
            Timer { id: lingerBtn; interval: 150; repeat: false }
        }
    }
}
