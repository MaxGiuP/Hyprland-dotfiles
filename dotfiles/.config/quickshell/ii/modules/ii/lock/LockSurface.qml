import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.panels.lock
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris

MouseArea {
    id: root
    required property LockContext context
    property int lockpadRiseDurationMs: 650
    property int introStartDelayMs: 0
    property var captureScreen: null
    property bool introStarted: false

    // ─── Focus management ────────────────────────────────────────────────────
    function forceFieldFocus() {
        passwordInput.forceActiveFocus();
    }
    Connections {
        target: context
        function onShouldReFocus() { forceFieldFocus(); }
    }
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    onPressed: mouse => { forceFieldFocus(); }
    onPositionChanged: mouse => { forceFieldFocus(); }
    Keys.onPressed: event => {
        root.context.resetClearTimer();
        if (event.key === Qt.Key_Escape) root.context.currentText = "";
        forceFieldFocus();
    }

    // ─── Intro state ─────────────────────────────────────────────────────────
    property bool introComplete: false
    readonly property real lockBlurProgress: Config.options.lock.blur.enable
        ? Math.max(0, Math.min(1, GlobalStates.screenLockBlurProgress))
        : 0
    property bool blurCapturePending: false
    property bool blurWasActive: false

    function refreshBlurCapture() {
        if (!root.captureScreen) {
            root.blurCapturePending = true;
            return;
        }

        root.blurCapturePending = false;
        screenshotView.captureFrame();
    }

    // ─── GPU (nvidia-smi) ────────────────────────────────────────────────────
    property bool gpuAvailable: true
    property int  gpuUtil: 0
    property int  vramUsedMB: 0
    property int  vramTotalMB: 0

    Timer {
        interval: 2000; running: true; repeat: true
        onTriggered: { gpuQuery.buf = ""; gpuQuery.running = false; gpuQuery.running = true; }
    }
    Process {
        id: gpuQuery
        environment: ({ LANG: "C", LC_ALL: "C" })
        command: ["nvidia-smi", "-i", "0", "-q", "-d", "UTILIZATION,MEMORY"]
        property string buf: ""
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => gpuQuery.buf += data + "\n"
        }
        onExited: code => {
            const t = gpuQuery.buf; gpuQuery.buf = ""
            if (code !== 0) { root.gpuAvailable = false; return }
            const um = t.match(/Gpu\s*:\s*(\d+)\s*%/i)
            if (um) root.gpuUtil = parseInt(um[1]) || 0
            const mm = t.match(/FB Memory Usage[\s\S]*?Total\s*:\s*(\d+)\s*MiB[\s\S]*?Used\s*:\s*(\d+)\s*MiB/i)
            if (mm) { root.vramTotalMB = parseInt(mm[1]) || 0; root.vramUsedMB = parseInt(mm[2]) || 0 }
        }
    }

    // ─── Network (/proc/net/dev) ──────────────────────────────────────────────
    property string netIface: ""
    property real   downMbps: 0
    property real   upMbps: 0
    property var    _netLastMap: ({})
    property double _netLastT: 0

    function formatNetSpeed(mbps) {
        if (mbps >= 1000) return (mbps / 1000).toFixed(1) + " Gbps"
        if (mbps >= 1)    return mbps.toFixed(1) + " Mbps"
        if (mbps >= 0.001) return (mbps * 1000).toFixed(0) + " Kbps"
        return "0"
    }

    Timer { interval: 1000; running: true; repeat: true; onTriggered: netView.reload() }
    FileView {
        id: netView
        path: "/proc/net/dev"
        onLoaded: {
            const now = Date.now()
            const lines = (netView.text() || "").trim().split("\n").slice(2)
            let map = {}
            for (let i = 0; i < lines.length; i++) {
                const p = lines[i].split(":")
                if (p.length < 2) continue
                const iface = p[0].trim()
                const f = p[1].trim().split(/\s+/)
                if (f.length < 10) continue
                map[iface] = { rx: Number(f[0]), tx: Number(f[8]) }
            }
            if (!root.netIface || !(root.netIface in map)) {
                let best = "", bestSum = -1
                for (const k in map) {
                    if (k === "lo") continue
                    const s = (map[k].rx || 0) + (map[k].tx || 0)
                    if (s > bestSum) { best = k; bestSum = s }
                }
                if (best) root.netIface = best
            }
            if (root.netIface && (root.netIface in map) && root._netLastT > 0 && root._netLastMap[root.netIface]) {
                const dt = Math.max(1e-3, (now - root._netLastT) / 1000)
                root.downMbps = Math.max(0, (map[root.netIface].rx - root._netLastMap[root.netIface].rx) * 8) / 1e6 / dt
                root.upMbps   = Math.max(0, (map[root.netIface].tx - root._netLastMap[root.netIface].tx) * 8) / 1e6 / dt
            }
            root._netLastMap = map; root._netLastT = now
        }
    }

    Component.onCompleted: {
        forceFieldFocus();
        startIntroAnimation();
    }

    onWidthChanged: startIntroAnimation()
    onHeightChanged: startIntroAnimation()
    onCaptureScreenChanged: {
        if (root.blurCapturePending && root.captureScreen)
            Qt.callLater(root.refreshBlurCapture);
    }
    onLockBlurProgressChanged: {
        const blurIsActive = root.lockBlurProgress > 0.001;
        if (blurIsActive && !root.blurWasActive) {
            Qt.callLater(root.refreshBlurCapture);
        }

        root.blurWasActive = blurIsActive;
    }

    function startIntroAnimation() {
        if (root.introStarted || root.width <= 0 || root.height <= 0)
            return;

        root.introStarted = true;
        root.introComplete = false;

        lockpadIcon.x = root.lockpadCenterX;
        lockpadIcon.y = root.height;
        lockpadIcon.scale = 1.0;
        lockpadIcon.opacity = 1.0;
        lockpadSymbol.text = "lock_open";

        mainCard.opacity = 0;
        mainCard.scale = 0.94;
        cardGlow.opacity = 0;
        powerButtons.opacity = 0;
        powerButtons.anchors.bottomMargin = -12;

        lockRiseAnim.restart();
    }

    Item {
        id: screenshotLayer
        z: -20
        anchors.fill: parent
        clip: true
        visible: opacity > 0
        opacity: screenshotView.hasContent ? 1 : 0
        readonly property real blurScale: 1 + ((Config.options.lock.blur.extraZoom - 1) * root.lockBlurProgress)
        readonly property real blurRadius: Config.options.lock.blur.radius * root.lockBlurProgress
        // Overscan the screencopy so the blur still covers the full screen
        // when the lock transition zoom changes and the blur samples past edges.
        readonly property real blurOverscan: Math.ceil(
            blurRadius + (Math.max(root.width, root.height) * Math.max(0, blurScale - 1) / 2)
        )

        Behavior on opacity {
            NumberAnimation {
                duration: 120
                easing.type: Easing.OutCubic
            }
        }

        ScreencopyView {
            id: screenshotView
            x: -screenshotLayer.blurOverscan
            y: -screenshotLayer.blurOverscan
            width: root.width + screenshotLayer.blurOverscan * 2
            height: root.height + screenshotLayer.blurOverscan * 2
            scale: screenshotLayer.blurScale
            transformOrigin: Item.Center
            captureSource: root.captureScreen
            live: false
            paintCursor: false
        }

        ShaderEffectSource {
            id: screenshotTexture
            x: screenshotView.x
            y: screenshotView.y
            width: screenshotView.width
            height: screenshotView.height
            sourceItem: screenshotView
            live: true
            hideSource: true
            visible: false
        }

        GaussianBlur {
            x: screenshotView.x
            y: screenshotView.y
            width: screenshotView.width
            height: screenshotView.height
            visible: screenshotView.hasContent
            source: screenshotTexture
            radius: screenshotLayer.blurRadius
            samples: Math.max(1, Math.ceil(radius) * 2 + 1)
            transparentBorder: false
        }

        Rectangle {
            anchors.fill: parent
            color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.7)
            opacity: root.lockBlurProgress
        }
    }

    // ─── Lockpad position helpers ─────────────────────────────────────────────
    // The lockpad is 120px at full size. Settled scale matches the 48px card badge.
    readonly property real lockpadSize: 120
    readonly property real lockpadSettledScale: 48.0 / lockpadSize   // 0.4 — matches badge
    readonly property real lockpadCenterY: (root.height - lockpadSize) / 2
    readonly property real lockpadCenterX: (root.width  - lockpadSize) / 2
    // Badge centre in root coordinates, computed by tracing the layout chain:
    //   mainCard.x + cardLayout.leftMargin(28) + topRow.x(0) + timeCol.x(0) + lockBadge.x + lockBadge.width/2
    // lockBadge.x is set by the ColumnLayout engine due to Layout.alignment: AlignHCenter.
    readonly property real lockpadSettledX: mainCard.x + 28 + lockBadge.x + lockBadge.width  / 2 - lockpadSize / 2
    readonly property real lockpadSettledY: mainCard.y + 28 + lockBadge.y + lockBadge.height / 2 - lockpadSize / 2

    // ─── Lockpad icon ─────────────────────────────────────────────────────────
    Item {
        id: lockpadIcon
        z: 2
        width: root.lockpadSize
        height: root.lockpadSize
        x: (root.width - width) / 2
        y: root.height      // starts off-screen at the bottom
        scale: 1.0
        opacity: 1.0

        Rectangle {
            anchors.centerIn: parent
            width: parent.width
            height: parent.height
            radius: width / 2
            color: Appearance.colors.colPrimary
        }

        MaterialSymbol {
            id: lockpadSymbol
            anchors.centerIn: parent
            text: "lock_open"   // unlocked state on entry
            fill: 1
            iconSize: 60
            color: Appearance.colors.colOnPrimary
        }
    }

    // ─── Intro animation ─────────────────────────────────────────────────────
    SequentialAnimation {
        id: lockRiseAnim

        // Let the blur settle before the lockpad enters the screen.
        PauseAnimation { duration: root.introStartDelayMs }

        // Phase 1: lockpad rises from bottom to centre in unlocked state
        NumberAnimation {
            target: lockpadIcon
            property: "y"
            from: root.height
            to: root.lockpadCenterY
            duration: root.lockpadRiseDurationMs
            easing.type: Easing.OutCubic
        }

        PauseAnimation { duration: 400 }

        // Phase 2: snap to locked icon
        ScriptAction { script: { lockpadSymbol.text = "lock"; } }

        PauseAnimation { duration: 200 }

        // Phase 3: lockpad shrinks + moves into badge position; card fades in
        ParallelAnimation {
            NumberAnimation {
                target: lockpadIcon; property: "x"
                to: root.lockpadSettledX
                duration: 380; easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: lockpadIcon; property: "y"
                to: root.lockpadSettledY
                duration: 380; easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: lockpadIcon; property: "scale"
                to: root.lockpadSettledScale
                duration: 380; easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: mainCard; property: "opacity"
                to: 1.0; duration: 380; easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: mainCard; property: "scale"
                to: 1.0; duration: 380; easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: cardGlow; property: "opacity"
                to: 1.0; duration: 380; easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: powerButtons; property: "opacity"
                to: 1.0; duration: 380; easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: powerButtons; property: "anchors.bottomMargin"
                to: 24; duration: 380; easing.type: Easing.OutCubic
            }
        }

        ScriptAction {
            script: { root.introComplete = true; root.forceFieldFocus(); }
        }
    }

    // ─── Unlock animation (reverse) ───────────────────────────────────────────
    SequentialAnimation {
        id: unlockAnim

        // Phase 1: lockpad expands + moves back to centre; card fades out
        ParallelAnimation {
            NumberAnimation {
                target: lockpadIcon; property: "x"
                to: root.lockpadCenterX
                duration: 350; easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: lockpadIcon; property: "y"
                to: root.lockpadCenterY
                duration: 350; easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: lockpadIcon; property: "scale"
                to: 1.0
                duration: 350; easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: mainCard; property: "opacity"
                to: 0; duration: 250; easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: cardGlow; property: "opacity"
                to: 0; duration: 250; easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: powerButtons; property: "opacity"
                to: 0; duration: 250; easing.type: Easing.OutCubic
            }
        }

        PauseAnimation { duration: 200 }

        // Phase 2: snap to unlocked icon
        ScriptAction { script: { lockpadSymbol.text = "lock_open"; } }

        PauseAnimation { duration: 150 }

        // Phase 3: lockpad drops off screen
        ParallelAnimation {
            NumberAnimation {
                target: lockpadIcon; property: "y"
                to: root.height
                duration: 500; easing.type: Easing.InCubic
            }
            NumberAnimation {
                target: lockpadIcon; property: "opacity"
                to: 0; duration: 400; easing.type: Easing.InQuad
            }
        }

        PauseAnimation { duration: 50 }
    }

    Connections {
        target: root.context
        function onUnlocked(targetAction) { unlockAnim.start(); }
    }

    // ─── Card halo glow ───────────────────────────────────────────────────────
    RectangularGlow {
        id: cardGlow
        z: -1
        anchors.centerIn: mainCard
        width: mainCard.width
        height: mainCard.height
        glowRadius: 48
        spread: 0.04
        color: Qt.rgba(
            Appearance.colors.colPrimary.r,
            Appearance.colors.colPrimary.g,
            Appearance.colors.colPrimary.b,
            0.32
        )
        cornerRadius: mainCard.radius + glowRadius
        opacity: 0
    }

    // ─── Main info card ──────────────────────────────────────────────────────
    Rectangle {
        id: mainCard
        anchors.centerIn: parent
        width: Math.min(840, root.width - 80)
        implicitHeight: cardLayout.implicitHeight + 32
        radius: 22
        color: Qt.rgba(Appearance.m3colors.m3surfaceContainerLowest.r, Appearance.m3colors.m3surfaceContainerLowest.g, Appearance.m3colors.m3surfaceContainerLowest.b, 1.0)
        border.width: 1
        border.color: Qt.rgba(Appearance.m3colors.m3surfaceTint.r, Appearance.m3colors.m3surfaceTint.g, Appearance.m3colors.m3surfaceTint.b, 0.2)
        opacity: 0
        scale: 0.94

        ColumnLayout {
            id: cardLayout
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                topMargin: 28
                leftMargin: 28
                rightMargin: 28
            }
            spacing: 20

            // ── Top: time + weather ───────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 24

                // Lock icon + time + date
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 2
                    spacing: 10

                    // Lock badge — hidden; lockpadIcon animates to this position
                    Rectangle {
                        id: lockBadge
                        Layout.alignment: Qt.AlignHCenter
                        width: 48; height: 48; radius: 24
                        color: "transparent"
                    }

                    StyledText {
                        text: DateTime.time
                        font.pixelSize: 68
                        font.family: Appearance.font.family.expressive
                        font.weight: Font.Light
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        text: DateTime.formatDate("dddd, MMMM d")
                        font.pixelSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colSubtext
                    }
                }

                // Vertical separator
                Rectangle {
                    width: 1; Layout.fillHeight: true
                    color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.86)
                }

                // Weather: current + forecast
                ColumnLayout {
                    id: weatherColumn
                    Layout.fillWidth: true
                    Layout.preferredWidth: 3
                    spacing: 18

                    // Current conditions
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 16
                        MaterialSymbol {
                            text: Icons.getWeatherIcon(Weather.data?.wCode) ?? "cloud"
                            iconSize: 64; fill: 1
                            color: Appearance.colors.colOnLayer1
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            StyledText {
                                Layout.fillWidth: true
                                text: Weather.data?.temp ?? "--"
                                font.pixelSize: 48
                                font.weight: Font.Light
                                color: Appearance.colors.colOnLayer1
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: (Weather.data?.city ?? "")
                                    + ((Weather.data?.tempFeelsLike ?? "") !== ""
                                        ? " • Feels like " + Weather.data.tempFeelsLike : "")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colSubtext
                                visible: (Weather.data?.city ?? "") !== ""
                                elide: Text.ElideRight
                            }
                        }
                    }

                    // 10-period hourly forecast
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 15
                        visible: (Weather.data?.hourly?.length ?? 0) > 0
                        Repeater {
                            model: (Weather.data?.hourly ?? []).slice(0, 10)
                            delegate: ColumnLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 8
                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: modelData.time
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colSubtext
                                }
                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: Icons.getWeatherIcon(modelData.wCode) ?? "cloud"
                                    iconSize: 36; fill: 1
                                    color: Appearance.colors.colOnLayer1
                                }
                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: modelData.temp
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnLayer1
                                }
                            }
                        }
                    }
                }
            }

            // ── Divider ───────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true; height: 1
                color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.86)
            }

            // ── Bottom: media (left) + resources (right) ──────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 24

                // Media player + volume
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.fillHeight: true
                    spacing: 14

                    // No-player placeholder
                    RowLayout {
                        spacing: 10
                        visible: MprisController.activePlayer == null
                        MaterialSymbol { text: "music_note"; iconSize: 20; color: Appearance.colors.colSubtext }
                        StyledText {
                            text: "No media playing"
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colSubtext
                        }
                    }

                    // Active player
                    Loader {
                        Layout.fillWidth: true
                        active: MprisController.activePlayer != null
                        visible: active
                        sourceComponent: ColumnLayout {
                            spacing: 12

                            RowLayout {
                                spacing: 14
                                Rectangle {
                                    width: 110; height: 110
                                    radius: Appearance.rounding.small
                                    color: Appearance.colors.colLayer2; clip: true
                                    Image {
                                        id: albumArt
                                        anchors.fill: parent
                                        source: MprisController.activeTrack?.artUrl ?? ""
                                        fillMode: Image.PreserveAspectCrop
                                        visible: status === Image.Ready
                                    }
                                    MaterialSymbol {
                                        anchors.centerIn: parent; text: "music_note"; iconSize: 24
                                        color: Appearance.colors.colSubtext
                                        visible: albumArt.status !== Image.Ready
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 4
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: MprisController.activeTrack?.title ?? ""
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        font.weight: Font.Medium
                                        color: Appearance.colors.colOnLayer1; elide: Text.ElideRight
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: MprisController.activeTrack?.artist ?? ""
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colSubtext
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 3
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            RowLayout {
                                Layout.alignment: Qt.AlignHCenter; spacing: 12
                                RippleButton {
                                    implicitWidth: 56; implicitHeight: 56
                                    enabled: MprisController.canGoPrevious
                                    onClicked: MprisController.previous()
                                    contentItem: MaterialSymbol { anchors.centerIn: parent; text: "skip_previous"; iconSize: 32
                                        color: parent.enabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext }
                                }
                                RippleButton {
                                    implicitWidth: 68; implicitHeight: 68
                                    onClicked: MprisController.togglePlaying()
                                    contentItem: MaterialSymbol { anchors.centerIn: parent
                                        text: MprisController.isPlaying ? "pause" : "play_arrow"; iconSize: 40
                                        color: Appearance.colors.colOnLayer1 }
                                }
                                RippleButton {
                                    implicitWidth: 56; implicitHeight: 56
                                    enabled: MprisController.canGoNext
                                    onClicked: MprisController.next()
                                    contentItem: MaterialSymbol { anchors.centerIn: parent; text: "skip_next"; iconSize: 32
                                        color: parent.enabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext }
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }

                    // Volume
                    RowLayout {
                        Layout.fillWidth: true; spacing: 12
                        RippleButton {
                            implicitWidth: 36; implicitHeight: 36
                            onClicked: Audio.toggleMute()
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: Audio.muted ? "volume_off"
                                    : Audio.value > 0.5 ? "volume_up" : "volume_down"
                                iconSize: 20; color: Appearance.colors.colOnLayer1
                            }
                        }
                        StyledSlider {
                            Layout.fillWidth: true; from: 0; to: 1
                            value: Audio.value
                            onMoved: Audio.setVolume(value)
                            configuration: StyledSlider.Configuration.S
                        }
                    }
                }

                // Vertical separator
                Rectangle {
                    width: 1; Layout.fillHeight: true
                    color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.86)
                }

                // Resource usage
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: 8

                    component ResRow: RowLayout {
                        Layout.fillWidth: true; spacing: 6
                        property alias icon: _icon.text
                        property alias label: _label.text
                        property alias pct: _pct.text
                        MaterialSymbol { id: _icon; iconSize: 14; fill: 1; color: Appearance.colors.colSubtext }
                        StyledText { id: _label; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext }
                        Item { Layout.fillWidth: true }
                        StyledText { id: _pct; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer1 }
                    }
                    component ResBar: Rectangle {
                        Layout.fillWidth: true; height: 5; radius: 3
                        color: Appearance.colors.colLayer2
                        property real usage: 0
                        Rectangle {
                            width: Math.max(0, Math.min(1, parent.usage)) * parent.width
                            height: parent.height; radius: parent.radius
                            color: Appearance.colors.colPrimary
                            Behavior on width { SmoothedAnimation { velocity: 120 } }
                        }
                    }

                    ResRow { icon: "developer_board"; label: Translation.tr("CPU"); pct: ResourceUsage.cpuUsagePercent + "%" }
                    ResBar { usage: ResourceUsage.cpuUsage }

                    ResRow { icon: "memory"; label: Translation.tr("RAM"); pct: Math.round(ResourceUsage.memoryUsedPercentage * 100) + "%" }
                    ResBar { usage: ResourceUsage.memoryUsedPercentage }

                    ResRow { icon: "jamboard_kiosk"; label: Translation.tr("GPU"); pct: root.gpuUtil + "%"; visible: root.gpuAvailable }
                    ResBar { usage: root.gpuUtil / 100; visible: root.gpuAvailable }

                    ResRow {
                        icon: "swap_horiz"; label: "SWAP"
                        pct: Math.round(ResourceUsage.swapUsedPercentage * 100) + "%"
                        visible: ResourceUsage.swapTotal > 0
                    }
                    ResBar { usage: ResourceUsage.swapUsedPercentage; visible: ResourceUsage.swapTotal > 0 }

                    RowLayout {
                        Layout.fillWidth: true; spacing: 6
                        MaterialSymbol { text: "network_check"; iconSize: 14; fill: 1; color: Appearance.colors.colSubtext }
                        StyledText { text: "Net"; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext }
                        Item {
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: 192
                            implicitHeight: 16

                            property int maxPoints: 48
                            property var downHist: []
                            property var upHist: []
                            property real graphMax: 1

                            function recomputeGraphMax() {
                                var m = Math.max(Math.abs(root.downMbps), Math.abs(root.upMbps))
                                if (m <= 0) {
                                    graphMax = 1
                                    return
                                }
                                var exp = Math.floor(Math.log(m) / Math.LN10)
                                var base = Math.pow(10, exp)
                                var norm = m / base
                                var niceNorm
                                if (norm <= 1) niceNorm = 1
                                else if (norm <= 2) niceNorm = 2
                                else if (norm <= 5) niceNorm = 5
                                else niceNorm = 10
                                graphMax = niceNorm * base
                            }

                            function pushSample() {
                                downHist.push(root.downMbps || 0)
                                upHist.push(root.upMbps || 0)
                                if (downHist.length > maxPoints) downHist.shift()
                                if (upHist.length > maxPoints) upHist.shift()
                                recomputeGraphMax()
                                netCanvas.requestPaint()
                            }

                            Timer {
                                interval: 1000
                                running: true
                                repeat: true
                                onTriggered: parent.pushSample()
                            }

                            Canvas {
                                id: netCanvas
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
                                        if (!values.length || parent.graphMax <= 0) return
                                        var step = (w - 1) / Math.max(1, parent.maxPoints - 1)
                                        ctx.globalAlpha = 1.0
                                        ctx.strokeStyle = stroke
                                        ctx.lineWidth = 2
                                        ctx.beginPath()
                                        for (var i = 0; i < values.length; i++) {
                                            var v = Math.max(0, values[i])
                                            var x = Math.round(i * step)
                                            var y = Math.round(h - (v / parent.graphMax) * h)
                                            if (i === 0) ctx.moveTo(x, y)
                                            else ctx.lineTo(x, y)
                                        }
                                        ctx.stroke()
                                    }

                                    drawLine(parent.downHist, "#0091ff")
                                    drawLine(parent.upHist, "#ff00d4")
                                }
                            }
                        }
                        Item { Layout.fillWidth: true }
                        ColumnLayout {
                            spacing: 1
                            StyledText {
                                text: "↓ " + root.formatNetSpeed(root.downMbps)
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                text: "↑ " + root.formatNetSpeed(root.upMbps)
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }
            }

            // ── Divider ───────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true; height: 1
                color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.86)
            }

            // ── Password input ────────────────────────────────────────────
            RowLayout {
                id: passwordRow
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    id: passwordPill
                    Layout.fillWidth: true; height: 50
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colLayer2; clip: true

                    StyledText {
                        anchors.centerIn: parent
                        visible: passwordInput.text.length === 0
                        text: root.context.showFailure ? Translation.tr("Incorrect password") : Translation.tr("Enter password")
                        color: root.context.showFailure ? Appearance.m3colors.m3error : Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.normal
                    }

                    StyledTextInput {
                        id: passwordInput
                        anchors { fill: parent; leftMargin: 20; rightMargin: 20 }
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: TextInput.Password; inputMethodHints: Qt.ImhSensitiveData
                        enabled: !root.context.unlockInProgress
                        cursorVisible: text.length > 0
                        color: Config.options.lock.materialShapeChars ? "transparent" : Appearance.colors.colOnLayer2
                        font.pixelSize: Appearance.font.pixelSize.normal

                        onTextChanged: root.context.currentText = this.text
                        onAccepted: root.context.tryUnlock()
                        Keys.onPressed: event => { root.context.resetClearTimer(); }

                        Connections {
                            target: root.context
                            function onCurrentTextChanged() { passwordInput.text = root.context.currentText; }
                        }

                        SequentialAnimation {
                            id: shakeAnim
                            NumberAnimation { target: passwordPill; property: "x"; to: -12; duration: 50 }
                            NumberAnimation { target: passwordPill; property: "x"; to: 12;  duration: 50 }
                            NumberAnimation { target: passwordPill; property: "x"; to: -6;  duration: 40 }
                            NumberAnimation { target: passwordPill; property: "x"; to: 6;   duration: 40 }
                            NumberAnimation { target: passwordPill; property: "x"; to: 0;   duration: 30 }
                        }
                        Connections {
                            target: GlobalStates
                            function onScreenUnlockFailedChanged() {
                                if (GlobalStates.screenUnlockFailed) shakeAnim.restart();
                            }
                        }
                    }

                    Loader {
                        active: Config.options.lock.materialShapeChars
                        anchors { fill: parent; leftMargin: 20; rightMargin: 20 }
                        sourceComponent: PasswordChars {
                            length: root.context.currentText.length
                            selectionStart: passwordInput.selectionStart
                            selectionEnd: passwordInput.selectionEnd
                            cursorPosition: passwordInput.cursorPosition
                        }
                    }
                }

                RippleButton {
                    implicitWidth: 50; implicitHeight: 50; toggled: true
                    colBackgroundToggled: Appearance.colors.colPrimary
                    enabled: !root.context.unlockInProgress
                    onClicked: root.context.tryUnlock()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent; text: "arrow_forward"; iconSize: 24
                        color: Appearance.colors.colOnPrimary
                    }
                }
            }

            // Bottom padding
            Item { implicitHeight: 6 }
        }
    }

    // ─── Power / session buttons — bottom-left ───────────────────────────────
    Row {
        id: powerButtons
        anchors {
            left: parent.left
            bottom: parent.bottom
            leftMargin: 24
            bottomMargin: 0      // animates to 24 on intro completion
        }
        spacing: 8
        opacity: 0

        // Sleep
        RippleButton {
            implicitWidth: 48; implicitHeight: 48
            onClicked: Session.suspend()
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "dark_mode"; iconSize: 24
                color: Appearance.colors.colOnSurfaceVariant
                style: Text.Outline
                styleColor: "#000000"
            }
        }
        // Power off
        RippleButton {
            implicitWidth: 48; implicitHeight: 48
            onClicked: Session.poweroff()
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "power_settings_new"; iconSize: 24
                color: Appearance.colors.colOnSurfaceVariant
                style: Text.Outline
                styleColor: "#000000"
            }
        }
        // Restart
        RippleButton {
            implicitWidth: 48; implicitHeight: 48
            onClicked: Session.reboot()
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "restart_alt"; iconSize: 24
                color: Appearance.colors.colOnSurfaceVariant
                style: Text.Outline
                styleColor: "#000000"
            }
        }
        // Logout
        RippleButton {
            implicitWidth: 48; implicitHeight: 48
            onClicked: Session.logout()
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "logout"; iconSize: 24
                color: Appearance.colors.colOnSurfaceVariant
                style: Text.Outline
                styleColor: "#000000"
            }
        }
    }
}
