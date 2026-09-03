import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true
    baseWidth: 760
    readonly property bool settingsApp: Quickshell.env("II_SETTINGS_APP") === "1"
    property bool pageActive: true
    property int currentSubTab: 0
    readonly property var tabs: [
        { name: Translation.tr("Output"), icon: "volume_up" },
        { name: Translation.tr("Input"), icon: "mic" },
        { name: Translation.tr("Sound & safety"), icon: "hearing" }
    ]

    function applySubTab(subTab, sectionId = "") {
        root.currentSubTab = Math.max(0, Math.min(subTab, root.tabs.length - 1))
        root.contentY = 0
    }

    property bool _monoGuard: false
    property string monoMasterSink: ""
    property real _capturedVolume: 0
    readonly property string monoStatePath: `${Quickshell.env("XDG_RUNTIME_DIR")}/ii-audio-mono-master`
    property list<real> outputVisualizerPoints: []
    property list<real> inputVisualizerPoints: []
    readonly property string outputVisualizerSource: Audio.sink?.name ? `${Audio.sink.name}.monitor` : ""
    readonly property string inputVisualizerSource: Audio.source?.name ?? ""
    readonly property string safeOutputVisualizerSource: root.safeNodeName(root.outputVisualizerSource)
    readonly property string safeInputVisualizerSource: root.safeNodeName(root.inputVisualizerSource)

    readonly property var trackedOutputDevices: Audio.outputDevices.filter(d => d.name !== "qs_mono_out")
    readonly property var realOutputDevices: Audio.selectableOutputDevices.filter(d => d.name !== "qs_mono_out")

    function shellQuote(value) {
        return `'${String(value ?? "").replace(/'/g, `'\"'\"'`)}'`;
    }

    function safeNodeName(value) {
        const name = String(value ?? "")
        return /^[A-Za-z0-9_.:@+\/-]+$/.test(name) ? name : ""
    }

    function cavaConfigCommand(sourceName, useDefaultSource) {
        const resolvedSource = (sourceName ?? "").trim();
        return (
            "CONFIG=$(mktemp); " +
            "trap 'rm -f \"$CONFIG\"' EXIT; " +
            "cat > \"$CONFIG\" <<EOF\n" +
            "[general]\n" +
            "mode = waves\n" +
            "framerate = 60\n" +
            "autosens = 1\n" +
            "bars = 50\n\n" +
            "[input]\n" +
            "method = pulse\n" +
            (useDefaultSource ? "" : `source = ${resolvedSource}\n`) +
            "\n" +
            "[output]\n" +
            "method = raw\n" +
            "raw_target = /dev/stdout\n" +
            "data_format = ascii\n" +
            "channels = mono\n" +
            "mono_option = average\n\n" +
            "[smoothing]\n" +
            "noise_reduction = 20\n" +
            "EOF\n" +
            "exec cava -p \"$CONFIG\""
        );
    }

    // Track all output devices so their PwNode references are ready for setDefaultSink
    PwObjectTracker {
        objects: root.trackedOutputDevices
    }

    Process {
        id: outputVisualizerProc
        running: root.pageActive && root.currentSubTab === 0 && root.safeOutputVisualizerSource.length > 0
        command: ["bash", "-lc", root.cavaConfigCommand(root.safeOutputVisualizerSource, false)]
        stdout: SplitParser {
            onRead: data => {
                root.outputVisualizerPoints = data.split(";").map(p => parseFloat(p.trim())).filter(p => !isNaN(p));
            }
        }
        onRunningChanged: {
            if (!running)
                root.outputVisualizerPoints = [];
        }
    }

    Process {
        id: inputVisualizerProc
        running: root.pageActive && root.currentSubTab === 1 && root.safeInputVisualizerSource.length > 0
        command: ["bash", "-lc", root.cavaConfigCommand(root.safeInputVisualizerSource, false)]
        stdout: SplitParser {
            onRead: data => {
                root.inputVisualizerPoints = data.split(";").map(p => parseFloat(p.trim())).filter(p => !isNaN(p));
            }
        }
        onRunningChanged: {
            if (!running)
                root.inputVisualizerPoints = [];
        }
    }

    onInputVisualizerSourceChanged: {
        inputVisualizerProc.running = false
        inputVisualizerProc.running = Qt.binding(() => root.pageActive
            && root.currentSubTab === 1 && root.safeInputVisualizerSource.length > 0)
    }

    onOutputVisualizerSourceChanged: {
        outputVisualizerProc.running = false
        outputVisualizerProc.running = Qt.binding(() => root.pageActive
            && root.currentSubTab === 0 && root.safeOutputVisualizerSource.length > 0)
    }

    // Shared awk snippet: find stream nodes connected via output_FL to SINK:playback_FL
    readonly property string _awkFindFL: "'/^[^[:space:]]/{src=$1}/[|]->/ && $2==t && src~/:output_FL$/{sub(/:output_FL$/,\"\",src); print src}'"
    // Shared awk snippet: find nodes with cross-link (output_FR→playback_FL)
    readonly property string _awkFindXlink: "'/^[^[:space:]]/{src=$1}/[|]->/ && $2==t && src~/:output_FR$/{sub(/:output_FR$/,\"\",src); print src}'"

    function addLinksCmd(sink) {
        const target = sink === "${OLD}" || sink === "${SINK}" ? sink : root.safeNodeName(sink)
        if (!target.length)
            return "false"
        return "for node in $(pw-link -lo 2>/dev/null | awk -v t=\"" + target + ":playback_FL\" " + _awkFindFL + "); do " +
               "  pw-link \"${node}:output_FL\" \"" + target + ":playback_FR\" 2>/dev/null || true; " +
               "  pw-link \"${node}:output_FR\" \"" + target + ":playback_FL\" 2>/dev/null || true; " +
               "done"
    }

    function removeLinksCmd(sink) {
        const target = sink === "${OLD}" || sink === "${SINK}" ? sink : root.safeNodeName(sink)
        if (!target.length)
            return "false"
        return "for node in $(pw-link -lo 2>/dev/null | awk -v t=\"" + target + ":playback_FL\" " + _awkFindXlink + "); do " +
               "  pw-link -d \"${node}:output_FR\" \"" + target + ":playback_FL\" 2>/dev/null || true; " +
               "  pw-link -d \"${node}:output_FL\" \"" + target + ":playback_FR\" 2>/dev/null || true; " +
               "done"
    }

    Process {
        id: monoCheckProc
        command: ["bash", "-c",
            "MASTER=$(cat " + root.shellQuote(root.monoStatePath) + " 2>/dev/null); " +
            "if [ -n \"$MASTER\" ] && " +
            "pw-link -lo 2>/dev/null | awk -v t=\"${MASTER}:playback_FL\" " +
            "'/^[^[:space:]]/{src=$1}/[|]->/ && $2==t && src~/:output_FR$/{found=1} END{exit !found}'; then " +
            "  echo \"on:$MASTER\"; " +
            "else echo 'off:'; fi"
        ]
        stdout: SplitParser {
            onRead: data => {
                const [state, master] = data.trim().split(":")
                root._monoGuard = true
                monoSwitch.checked = (state === "on")
                if (state === "on" && master) {
                    root.monoMasterSink = master
                    monoMonitorTimer.running = true
                }
                root._monoGuard = false
            }
        }
    }

    Process {
        id: monoSetupProc
        property string master: ""
        command: ["bash", "-c",
            // Clean up any old virtual sink modules from previous implementation
            "for mod in $(cat /tmp/qs_mono_module 2>/dev/null); do pactl unload-module \"$mod\" 2>/dev/null; done; rm -f /tmp/qs_mono_module; " +
            // Remove cross-links from previous master (if any)
            "OLD=$(cat " + root.shellQuote(root.monoStatePath) + " 2>/dev/null); " +
            "if [ -n \"$OLD\" ]; then " + root.removeLinksCmd("${OLD}") + "; fi; " +
            "printf '%s\\n' " + root.shellQuote(root.safeNodeName(master)) + " > " + root.shellQuote(root.monoStatePath) + "; " +
            root.addLinksCmd(master)
        ]
        onRunningChanged: if (!running) {
            monoActivateTimer.interval = 400
            monoActivateTimer.start()
        }
    }

    Timer {
        id: monoActivateTimer
        interval: 400
        repeat: false
        onTriggered: {
            if (root.settingsApp)
                return
            monoMonitorTimer.running = true
            monoCheckProc.running = true
        }
    }

    Process {
        id: monoRecreateProc
        property string newMaster: ""
        property string oldMaster: ""
        command: ["bash", "-c",
            root.removeLinksCmd(oldMaster) + "; " +
            "printf '%s\\n' " + root.shellQuote(root.safeNodeName(newMaster)) + " > " + root.shellQuote(root.monoStatePath) + "; " +
            "sleep 0.5; " +
            root.addLinksCmd(newMaster)
        ]
        onRunningChanged: if (!running) {
            monoActivateTimer.interval = 400
            monoActivateTimer.start()
        }
    }

    Process {
        id: monoTeardownProc
        command: ["bash", "-c",
            "SINK=$(cat " + root.shellQuote(root.monoStatePath) + " 2>/dev/null); " +
            "[ -z \"$SINK\" ] && exit 0; " +
            root.removeLinksCmd("${SINK}") + "; " +
            "rm -f -- " + root.shellQuote(root.monoStatePath)
        ]
        onRunningChanged: if (!running) monoCheckProc.running = true
    }

    Process {
        id: monoUpdateProc
        property string sink: ""
        command: ["bash", "-c", root.addLinksCmd(sink)]
    }

    Timer {
        id: monoMonitorTimer
        interval: 2000
        repeat: true
        running: false
        onTriggered: {
            if (root.settingsApp)
                return
            if (monoSwitch.checked && root.monoMasterSink && !monoUpdateProc.running) {
                monoUpdateProc.sink = root.monoMasterSink
                monoUpdateProc.running = true
            }
        }
    }

    Timer {
        id: volumeSyncTimer
        interval: 100
        repeat: false
        onTriggered: Audio.setVolume(root._capturedVolume)
    }

    SecondaryTabBar {
        Layout.fillWidth: true
        currentIndex: root.currentSubTab
        onCurrentIndexChanged: {
            root.currentSubTab = currentIndex
            root.contentY = 0
        }

        Repeater {
            model: root.tabs
            delegate: SecondaryTabButton {
                required property var modelData
                buttonIcon: modelData.icon
                buttonText: modelData.name
            }
        }
    }

    // ── Output ──────────────────────────────────────────────────────────────
    ContentSection {
        visible: root.currentSubTab === 0
        icon: "volume_up"
        title: Translation.tr("Output")

        ContentSubsection {
            title: Translation.tr("Default output device")

            StyledComboBox {
                Layout.fillWidth: true
                buttonIcon: "speaker"
                textRole: "displayName"
                model: root.realOutputDevices.map(d => ({
                    displayName: monoSwitch.checked
                        ? Audio.friendlyDeviceName(d) + " - Mono"
                        : Audio.friendlyDeviceName(d)
                }))
                currentIndex: {
                    if (monoSwitch.checked)
                        return Math.max(0, root.realOutputDevices.findIndex(d => d.name === root.monoMasterSink))

                    return Math.max(0, root.realOutputDevices.findIndex(d => Audio.isCurrentDefaultSink(d)))
                }
                onActivated: index => {
                    const newDevice = root.realOutputDevices[index]
                    if (monoSwitch.checked) {
                        root._capturedVolume = Audio.value
                        monoRecreateProc.oldMaster = root.monoMasterSink
                        root.monoMasterSink = newDevice.name
                        Audio.setDefaultSink(newDevice)
                        monoRecreateProc.newMaster = newDevice.name
                        monoRecreateProc.running = false
                        monoRecreateProc.running = true
                    } else {
                        Audio.setDefaultSink(newDevice)
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            RippleButton {
                buttonRadius: Appearance.rounding.full
                implicitWidth: 40
                implicitHeight: 40
                onClicked: Audio.toggleMute()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: Audio.sink?.audio?.muted ? "volume_off" : "volume_up"
                    iconSize: 22
                    color: Appearance.colors.colOnLayer1
                }
            }

            StyledSlider {
                Layout.fillWidth: true
                from: 0
                to: 1.54
                value: Audio.value
                configuration: StyledSlider.Configuration.M
                usePercentTooltip: false
                tooltipContent: `${Math.round(value * 100)}%`
                onMoved: Audio.setVolume(value)
            }

            StyledText {
                text: `${Math.round(Audio.value * 100)}%`
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
            }
        }

        ContentSubsection {
            title: Translation.tr("Output signal monitor")

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Listening to the current default output")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                elide: Text.ElideMiddle
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 72
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer2
                border.width: 1
                border.color: Appearance.colors.colOutlineVariant
                clip: true

                WaveVisualizer {
                    anchors.fill: parent
                    anchors.margins: 8
                    live: true
                    points: root.outputVisualizerPoints
                    maxVisualizerValue: 1000
                    color: Appearance.m3colors.m3primary
                }
            }
        }

        ConfigSwitch {
            id: monoSwitch
            buttonIcon: "merge_type"
            text: Translation.tr("Mono output")
            checked: false
            Component.onCompleted: {
                monoCheckProc.running = true
            }
            onCheckedChanged: {
                if (root._monoGuard)
                    return
                if (checked) {
                    root._capturedVolume = Audio.value
                    root.monoMasterSink = Audio.sink?.name ?? ""
                    monoSetupProc.master = root.monoMasterSink
                    monoSetupProc.running = false
                    monoSetupProc.running = true
                } else {
                    monoMonitorTimer.running = false
                    monoTeardownProc.running = false
                    monoTeardownProc.running = true
                }
            }
            StyledToolTip {
                text: Translation.tr("Create a dedicated mono output device that plays mixed audio on both channels")
            }
        }

        // Per-app output streams
        ContentSubsection {
            title: Translation.tr("App streams")
            visible: Audio.outputAppNodes.length > 0

            Repeater {
                model: Audio.outputAppNodes
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 8
                    PwObjectTracker { objects: [modelData] }

                    MaterialSymbol {
                        text: modelData.audio?.muted ? "volume_off" : "volume_up"
                        iconSize: 18
                        color: Appearance.colors.colOnLayer1
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: modelData.audio.muted = !modelData.audio.muted
                        }
                    }

                    StyledText {
                        Layout.preferredWidth: 140
                        elide: Text.ElideRight
                        text: Audio.appNodeDisplayName(modelData)
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.small
                    }

                    StyledSlider {
                        Layout.fillWidth: true
                        from: 0
                        to: 1.54
                        value: modelData.audio?.volume ?? 0
                        configuration: StyledSlider.Configuration.S
                        usePercentTooltip: false
                        tooltipContent: `${Math.round(value * 100)}%`
                        onMoved: { if (modelData.audio) modelData.audio.volume = value }
                    }

                    StyledText {
                        text: `${Math.round((modelData.audio?.volume ?? 0) * 100)}%`
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }
            }
        }
    }

    // ── Input ────────────────────────────────────────────────────────────────
    ContentSection {
        visible: root.currentSubTab === 1
        icon: "mic"
        title: Translation.tr("Input")

        ContentSubsection {
            title: Translation.tr("Default input device")

            StyledComboBox {
                Layout.fillWidth: true
                buttonIcon: "mic"
                textRole: "displayName"
                model: Audio.selectableInputDevices.map(d => ({ displayName: Audio.friendlyDeviceName(d) }))
                currentIndex: Math.max(0, Audio.selectableInputDevices.findIndex(d => Audio.isCurrentDefaultSource(d)))
                onActivated: index => Audio.setDefaultSource(Audio.selectableInputDevices[index])
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            RippleButton {
                buttonRadius: Appearance.rounding.full
                implicitWidth: 40
                implicitHeight: 40
                onClicked: Audio.toggleMicMute()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: Audio.source?.audio?.muted ? "mic_off" : "mic"
                    iconSize: 22
                    color: Appearance.colors.colOnLayer1
                }
            }

            StyledSlider {
                Layout.fillWidth: true
                from: 0
                to: 1
                value: Audio.micValue
                configuration: StyledSlider.Configuration.M
                usePercentTooltip: false
                tooltipContent: `${Math.round(value * 100)}%`
                onMoved: Audio.setMicVolume(value)
            }

            StyledText {
                text: `${Math.round(Audio.micValue * 100)}%`
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
            }
        }

        ContentSubsection {
            title: Translation.tr("Input signal monitor")

            StyledText {
                Layout.fillWidth: true
                text: root.inputVisualizerSource.length > 0
                    ? Translation.tr("Listening to %1").arg(root.inputVisualizerSource)
                    : Translation.tr("No input source available")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                elide: Text.ElideMiddle
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 72
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer2
                border.width: 1
                border.color: Appearance.colors.colOutlineVariant
                clip: true

                WaveVisualizer {
                    anchors.fill: parent
                    anchors.margins: 8
                    live: true
                    points: root.inputVisualizerPoints
                    maxVisualizerValue: 1000
                    color: Appearance.m3colors.m3secondary
                }
            }
        }

        // Per-app input streams
        ContentSubsection {
            title: Translation.tr("App streams")
            visible: Audio.inputAppNodes.length > 0

            Repeater {
                model: Audio.inputAppNodes
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 8
                    PwObjectTracker { objects: [modelData] }

                    MaterialSymbol {
                        text: modelData.audio?.muted ? "mic_off" : "mic"
                        iconSize: 18
                        color: Appearance.colors.colOnLayer1
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: modelData.audio.muted = !modelData.audio.muted
                        }
                    }

                    StyledText {
                        Layout.preferredWidth: 140
                        elide: Text.ElideRight
                        text: Audio.appNodeDisplayName(modelData)
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.small
                    }

                    StyledSlider {
                        Layout.fillWidth: true
                        from: 0
                        to: 1
                        value: modelData.audio?.volume ?? 0
                        configuration: StyledSlider.Configuration.S
                        usePercentTooltip: false
                        tooltipContent: `${Math.round(value * 100)}%`
                        onMoved: { if (modelData.audio) modelData.audio.volume = value }
                    }

                    StyledText {
                        text: `${Math.round((modelData.audio?.volume ?? 0) * 100)}%`
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }
            }
        }
    }

    // ── Protection ───────────────────────────────────────────────────────────
    ContentSection {
        visible: root.currentSubTab === 2
        icon: "hearing"
        title: Translation.tr("Earbang Protection")

        ConfigSwitch {
            buttonIcon: "hearing"
            text: Translation.tr("Enable protection")
            checked: Config.options.audio.protection.enable
            onCheckedChanged: Config.options.audio.protection.enable = checked
            StyledToolTip {
                text: Translation.tr("Prevents abrupt volume jumps and limits the maximum volume")
            }
        }

        ConfigRow {
            enabled: Config.options.audio.protection.enable

            ConfigSpinBox {
                icon: "arrow_warm_up"
                text: Translation.tr("Max increase per step (%)")
                value: Config.options.audio.protection.maxAllowedIncrease
                from: 0
                to: 250
                stepSize: 2
                onValueChanged: Config.options.audio.protection.maxAllowedIncrease = value
            }

            ConfigSpinBox {
                icon: "vertical_align_top"
                text: Translation.tr("Volume ceiling (%)")
                value: Config.options.audio.protection.maxAllowed
                from: 0
                to: 154
                stepSize: 2
                onValueChanged: Config.options.audio.protection.maxAllowed = value
            }
        }
    }

    // ── Sounds ───────────────────────────────────────────────────────────────
    ContentSection {
        visible: root.currentSubTab === 2
        icon: "notification_sound"
        title: Translation.tr("System sounds")

        ConfigRow {
            uniform: true

            ConfigSwitch {
                buttonIcon: "battery_android_full"
                text: Translation.tr("Battery alerts")
                checked: Config.options.sounds.battery
                onCheckedChanged: Config.options.sounds.battery = checked
            }

            ConfigSwitch {
                buttonIcon: "av_timer"
                text: Translation.tr("Pomodoro")
                checked: Config.options.sounds.pomodoro
                onCheckedChanged: Config.options.sounds.pomodoro = checked
            }
        }
    }

    // ── Open mixer ───────────────────────────────────────────────────────────
    ContentSection {
        visible: root.currentSubTab === 2
        icon: "open_in_new"
        title: Translation.tr("External mixer")

        RippleButtonWithIcon {
            Layout.fillWidth: true
            materialIcon: "tune"
            mainText: Translation.tr("Open full audio mixer")
            onClicked: Quickshell.execDetached([
                "bash", "-lc",
                "command -v pavucontrol-qt >/dev/null 2>&1 && exec pavucontrol-qt; " +
                "command -v pwvucontrol >/dev/null 2>&1 && exec pwvucontrol; " +
                "command -v helvum >/dev/null 2>&1 && exec helvum"
            ])
        }
    }
}
