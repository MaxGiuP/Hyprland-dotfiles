pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

/**
 * A nice wrapper for default Pipewire audio sink and source.
 */
Singleton {
    id: root
    readonly property bool settingsApp: Quickshell.env("II_SETTINGS_APP") === "1"

    // Misc props
    property bool ready: Pipewire.defaultAudioSink?.ready ?? false
    property PwNode sink: Pipewire.defaultAudioSink
    property PwNode source: Pipewire.defaultAudioSource
    readonly property real hardMaxValue: 4.00 // People keep joking about setting volume to 5172% so...
    property string audioTheme: Config.options.sounds.theme
    property real value: 0
    property real micValue: 0
    property bool muted: false
    property bool micMuted: false
    property bool sinkRestorePending: true
    property bool sourceRestorePending: true
    property int restoreAttempts: 0
    property list<var> fallbackOutputDevices: []
    property list<var> fallbackInputDevices: []
    property int fallbackDefaultSinkId: -1
    property int fallbackDefaultSourceId: -1
    readonly property int maxRestoreAttempts: 20
    
    function shellQuote(value) {
        return `'${String(value ?? "").replace(/'/g, `'\"'\"'`)}'`;
    }

    function friendlyDeviceName(node) {
        const nickname = `${node?.nickname ?? ""}`.trim();
        const description = `${node?.description ?? ""}`.trim();
        const name = `${node?.name ?? ""}`.trim();
        return nickname || description || name || Translation.tr("Unknown");
    }
    function appNodeDisplayName(node) {
        return (node.properties["application.name"] || node.description || node.name)
    }

    function parseVolumeState(output) {
        const text = `${output ?? ""}`;
        const match = text.match(/Volume:\s+([0-9.]+)/);
        return {
            valid: match !== null,
            volume: match ? Number(match[1]) : 0,
            muted: /\[MUTED\]/.test(text),
        };
    }

    function applySinkStateFromOutput(output) {
        const state = root.parseVolumeState(output);
        if (!state.valid)
            return;

        root.value = state.volume;
        root.muted = state.muted;
    }

    function applySourceStateFromOutput(output) {
        const state = root.parseVolumeState(output);
        if (!state.valid)
            return;

        root.micValue = state.volume;
        root.micMuted = state.muted;
    }

    function refreshSinkState() {
        getSinkVolume.running = false;
        getSinkVolume.running = true;
    }

    function refreshSourceState() {
        getSourceVolume.running = false;
        getSourceVolume.running = true;
    }

    function scheduleSinkRefresh() {
        sinkRefreshTimer.restart();
    }

    function scheduleSourceRefresh() {
        sourceRefreshTimer.restart();
    }

    function rememberNode(kind, node) {
        if (!Persistent.ready || !node)
            return;

        const target = kind === "source" ? Persistent.states.audio.source : Persistent.states.audio.sink;
        target.name = `${node.name ?? ""}`;
        target.description = `${node.description ?? ""}`;
        target.nickname = `${node.nickname ?? ""}`;
    }

    function nodeMatchesSaved(node, saved) {
        if (!node || !saved)
            return false;

        const nodeName = `${node.name ?? ""}`;
        const nodeDescription = `${node.description ?? ""}`;
        const nodeNickname = `${node.nickname ?? ""}`;

        return (saved.name.length > 0 && nodeName === saved.name)
            || (saved.description.length > 0 && nodeDescription === saved.description)
            || (saved.nickname.length > 0 && nodeNickname === saved.nickname);
    }

    function nodeId(node) {
        const id = Number(node?.id);
        return Number.isNaN(id) ? -1 : id;
    }

    function defaultDeviceId(isSink) {
        const liveId = Number(isSink ? Pipewire.defaultAudioSink?.id : Pipewire.defaultAudioSource?.id);
        if (!Number.isNaN(liveId))
            return liveId;

        return isSink ? root.fallbackDefaultSinkId : root.fallbackDefaultSourceId;
    }

    function defaultDevice(isSink) {
        const liveDevice = isSink ? root.sink : root.source;
        if (liveDevice)
            return liveDevice;

        const targetId = root.defaultDeviceId(isSink);
        const devices = isSink ? root.selectableOutputDevices : root.selectableInputDevices;
        return devices.find(node => root.nodeId(node) === targetId) ?? null;
    }

    function isCurrentDefaultSink(node) {
        return root.nodeId(node) === root.defaultDeviceId(true);
    }

    function isCurrentDefaultSource(node) {
        return root.nodeId(node) === root.defaultDeviceId(false);
    }

    function parseFallbackDevices(output) {
        const sinks = [];
        const sources = [];
        let defaultSinkId = -1;
        let defaultSourceId = -1;

        for (const rawLine of `${output ?? ""}`.split(/\r?\n/)) {
            if (!rawLine)
                continue;

            const parts = rawLine.split("\t");
            if (parts.length < 6)
                continue;

            const [kind, idText, name, description, nickname, defaultText] = parts;
            const id = Number(idText);
            if (Number.isNaN(id))
                continue;

            const device = {
                id,
                name,
                description,
                nickname,
                __fallback: true,
                __kind: kind,
            };

            if (kind === "sink") {
                sinks.push(device);
                if (defaultText === "1")
                    defaultSinkId = id;
            } else if (kind === "source") {
                sources.push(device);
                if (defaultText === "1")
                    defaultSourceId = id;
            }
        }

        root.fallbackOutputDevices = sinks;
        root.fallbackInputDevices = sources;
        root.fallbackDefaultSinkId = defaultSinkId;
        root.fallbackDefaultSourceId = defaultSourceId;
    }

    function refreshFallbackDevices() {
        if (root.settingsApp)
            return;

        fallbackDeviceProcess.running = false;
        fallbackDeviceProcess.running = true;
    }

    function attemptRestoreSavedDefaults() {
        if (root.settingsApp)
            return;

        if (!Persistent.ready)
            return;

        let restoredAny = false;

        if (root.sinkRestorePending) {
            const savedSink = Persistent.states.audio.sink;
            const hasSavedSink = savedSink.name.length > 0 || savedSink.description.length > 0 || savedSink.nickname.length > 0;
            const matchingSink = hasSavedSink ? root.outputDevices.find(node => root.nodeMatchesSaved(node, savedSink)) : null;

            if (matchingSink) {
                root.sinkRestorePending = false;
                restoredAny = true;
                if ((root.sink?.name ?? "") !== (matchingSink.name ?? ""))
                    root.setDefaultSink(matchingSink, false);
            } else if (!hasSavedSink) {
                root.sinkRestorePending = false;
            }
        }

        if (root.sourceRestorePending) {
            const savedSource = Persistent.states.audio.source;
            const hasSavedSource = savedSource.name.length > 0 || savedSource.description.length > 0 || savedSource.nickname.length > 0;
            const matchingSource = hasSavedSource ? root.inputDevices.find(node => root.nodeMatchesSaved(node, savedSource)) : null;

            if (matchingSource) {
                root.sourceRestorePending = false;
                restoredAny = true;
                if ((root.source?.name ?? "") !== (matchingSource.name ?? ""))
                    root.setDefaultSource(matchingSource, false);
            } else if (!hasSavedSource) {
                root.sourceRestorePending = false;
            }
        }

        if (!root.sinkRestorePending && !root.sourceRestorePending) {
            restoreTimer.stop();
            return;
        }

        if (!restoredAny) {
            root.restoreAttempts++;
            if (root.restoreAttempts >= root.maxRestoreAttempts)
                restoreTimer.stop();
        }
    }

    // Lists
    function appNodes(isSink) {
        return Pipewire.nodes.values.filter((node) => { // Should be list<PwNode> but it breaks ScriptModel
            return (node.isSink === isSink) && node.isStream
        })
    }
    function devices(isSink) {
        // Note: do NOT filter by node.audio here — audio is null for untracked nodes,
        // causing the list to be empty before PwObjectTracker activates them.
        // node.isSink is available without tracking (set from media.class).
        return Pipewire.nodes.values.filter(node => {
            return (node.isSink === isSink) && !node.isStream
        })
    }
    readonly property list<var> outputAppNodes: root.appNodes(true)
    readonly property list<var> inputAppNodes: root.appNodes(false)
    readonly property list<var> outputDevices: root.devices(true)
    readonly property list<var> inputDevices: root.devices(false)
    readonly property list<var> selectableOutputDevices: root.outputDevices.length > 0 ? root.outputDevices : root.fallbackOutputDevices
    readonly property list<var> selectableInputDevices: root.inputDevices.length > 0 ? root.inputDevices : root.fallbackInputDevices
    readonly property string currentSinkDisplayName: root.friendlyDeviceName(root.defaultDevice(true))
    readonly property string currentSourceDisplayName: root.friendlyDeviceName(root.defaultDevice(false))

    // Signals
    signal sinkProtectionTriggered(string reason);

    // Controls
    function setVolume(volume) {
        const clamped = Math.max(0, Math.min(root.hardMaxValue, Number(volume)));
        if (Number.isNaN(clamped))
            return;

        root.value = clamped;
        Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", `${clamped}`]);
        root.scheduleSinkRefresh();
    }

    function setMicVolume(volume) {
        const clamped = Math.max(0, Math.min(1, Number(volume)));
        if (Number.isNaN(clamped))
            return;

        root.micValue = clamped;
        Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SOURCE@", `${clamped}`]);
        root.scheduleSourceRefresh();
    }

    function toggleMute() {
        root.muted = !root.muted;
        Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]);
        root.scheduleSinkRefresh();
    }

    function toggleMicMute() {
        root.micMuted = !root.micMuted;
        Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"]);
        root.scheduleSourceRefresh();
    }

    function incrementVolume() {
        const currentVolume = Audio.value;
        const stepPercent = currentVolume < 0.09 ? 1 : 2;
        root.value = Math.min(root.hardMaxValue, currentVolume + (stepPercent / 100));
        Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", `${stepPercent}%+`]);
        root.scheduleSinkRefresh();
    }
    
    function decrementVolume() {
        const currentVolume = Audio.value;
        const stepPercent = currentVolume < 0.09 ? 1 : 2;
        root.value = Math.max(0, currentVolume - (stepPercent / 100));
        Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", `${stepPercent}%-`]);
        root.scheduleSinkRefresh();
    }

    function setDefaultSink(node, rememberSelection = true) {
        if (!node)
            return;

        if (rememberSelection)
            root.rememberNode("sink", node);
        const sinkId = `${node.id ?? ""}`;
        const sinkName = `${node.name ?? ""}`;
        const pactTarget = shellQuote(sinkName.length > 0 ? sinkName : sinkId);

        if (!node.__fallback)
            Pipewire.preferredDefaultAudioSink = node;
        root.fallbackDefaultSinkId = root.nodeId(node);

        // Keep PipeWire, PulseAudio compatibility, and existing streams aligned.
        Quickshell.execDetached([
            "bash", "-lc",
            `wpctl set-default ${shellQuote(sinkId)} 2>/dev/null || true; ` +
            `pactl set-default-sink ${pactTarget} 2>/dev/null || true; ` +
            `for input_id in $(pactl list short sink-inputs 2>/dev/null | awk '{print $1}'); do ` +
            `pactl move-sink-input "$input_id" ${pactTarget} 2>/dev/null || true; ` +
            `done`
        ]);
        root.scheduleSinkRefresh();
    }

    function setDefaultSource(node, rememberSelection = true) {
        if (!node)
            return;

        if (rememberSelection)
            root.rememberNode("source", node);
        const sourceId = `${node.id ?? ""}`;
        const sourceName = `${node.name ?? ""}`;
        const pactTarget = shellQuote(sourceName.length > 0 ? sourceName : sourceId);

        if (!node.__fallback)
            Pipewire.preferredDefaultAudioSource = node;
        root.fallbackDefaultSourceId = root.nodeId(node);

        Quickshell.execDetached([
            "bash", "-lc",
            `wpctl set-default ${shellQuote(sourceId)} 2>/dev/null || true; ` +
            `pactl set-default-source ${pactTarget} 2>/dev/null || true`
        ]);
        root.scheduleSourceRefresh();
    }

    // Internals
    // Track all device nodes so node.audio is populated for volume/mute control.
    // Defaults (sink/source) are included so their Connections blocks get live updates.
    PwObjectTracker {
        objects: root.settingsApp ? [] : ([...root.outputDevices, ...root.inputDevices, root.sink, root.source]).filter(n => n != null)
    }

    Timer {
        id: sinkRefreshTimer
        interval: 120
        repeat: false
        onTriggered: root.refreshSinkState()
    }

    Timer {
        id: sourceRefreshTimer
        interval: 120
        repeat: false
        onTriggered: root.refreshSourceState()
    }

    Timer {
        id: volumePollTimer
        interval: 1000
        repeat: true
        running: true
        onTriggered: {
            root.refreshSinkState();
            root.refreshSourceState();
        }
    }

    Process {
        id: getSinkVolume
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        stdout: StdioCollector {
            id: sinkVolumeCollector
            onStreamFinished: root.applySinkStateFromOutput(sinkVolumeCollector.text)
        }
    }

    Process {
        id: getSourceVolume
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SOURCE@"]
        stdout: StdioCollector {
            id: sourceVolumeCollector
            onStreamFinished: root.applySourceStateFromOutput(sourceVolumeCollector.text)
        }
    }

    Process {
        id: fallbackDeviceProcess
        command: ["bash", "-lc",
            "awk_extract='function trim(s){sub(/^[[:space:]]+/,\"\",s); sub(/[[:space:]]+$/,\"\",s); return s} " +
            "function emit(kind, star, id, label){if (id == \"\") return; print kind \"\\t\" id \"\\t\" trim(label) \"\\t\" (star == \"*\" ? 1 : 0)} " +
            "BEGIN{section=\"\"; inAudio=0} " +
            "/^Audio$/{inAudio=1; next} " +
            "inAudio && /├─ Sinks:/{section=\"sink\"; next} " +
            "inAudio && /├─ Sources:/{section=\"source\"; next} " +
            "inAudio && /├─ Filters:/{section=\"filter\"; next} " +
            "inAudio && (/└─ Streams:/ || /^Video$/){section=\"\"; if ($0 ~ /^Video$/) inAudio=0; next} " +
            "inAudio && match($0, /^[[:space:]│]*([* ])?[[:space:]]*([0-9]+)\\.[[:space:]]+([^\\[]+)/, m) { " +
            "  kind = section; " +
            "  if (section == \"filter\") { " +
            "    if ($0 ~ /\\[Audio\\/Sink\\]/) kind = \"sink\"; " +
            "    else if ($0 ~ /\\[Audio\\/Source\\]/) kind = \"source\"; " +
            "    else next; " +
            "  } " +
            "  emit(kind, m[1], m[2], m[3]); " +
            "}' ; " +
            "while IFS=$'\\t' read -r kind id label is_default; do " +
            "  inspect=$(wpctl inspect \"$id\" 2>/dev/null || true); " +
            "  name=$(printf '%s\\n' \"$inspect\" | sed -n 's/^[[:space:]]*\\* node.name = \"\\(.*\\)\"$/\\1/p' | head -n1); " +
            "  desc=$(printf '%s\\n' \"$inspect\" | sed -n 's/^[[:space:]]*\\*\\{0,1\\}[[:space:]]*node.description = \"\\(.*\\)\"$/\\1/p' | head -n1); " +
            "  nick=$(printf '%s\\n' \"$inspect\" | sed -n 's/^[[:space:]]*\\*\\{0,1\\}[[:space:]]*node.nick = \"\\(.*\\)\"$/\\1/p' | head -n1); " +
            "  [ -n \"$name\" ] || name=\"$label\"; " +
            "  [ -n \"$desc\" ] || desc=\"$label\"; " +
            "  printf '%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n' \"$kind\" \"$id\" \"$name\" \"$desc\" \"$nick\" \"$is_default\"; " +
            "done < <(wpctl status -n 2>/dev/null | awk \"$awk_extract\")"
        ]
        stdout: StdioCollector {
            id: fallbackDeviceCollector
            onStreamFinished: root.parseFallbackDevices(fallbackDeviceCollector.text)
        }
    }

    Timer {
        id: restoreTimer
        interval: 750
        repeat: true
        running: false
        onTriggered: root.attemptRestoreSavedDefaults()
    }

    Timer {
        id: fallbackRefreshTimer
        interval: 5000
        repeat: true
        running: !root.settingsApp
        onTriggered: {
            if (root.outputDevices.length === 0 || root.inputDevices.length === 0 || root.fallbackOutputDevices.length > 0 || root.fallbackInputDevices.length > 0)
                root.refreshFallbackDevices();
        }
    }

    onOutputDevicesChanged: {
        root.attemptRestoreSavedDefaults();
        if (root.outputDevices.length === 0)
            root.refreshFallbackDevices();
    }
    onInputDevicesChanged: {
        root.attemptRestoreSavedDefaults();
        if (root.inputDevices.length === 0)
            root.refreshFallbackDevices();
    }
    onSinkChanged: {
        root.scheduleSinkRefresh();
        root.refreshFallbackDevices();
    }
    onSourceChanged: {
        root.scheduleSourceRefresh();
        root.refreshFallbackDevices();
    }

    Component.onCompleted: {
        root.scheduleSinkRefresh();
        root.scheduleSourceRefresh();
        root.refreshFallbackDevices();

        if (root.settingsApp)
            return;

        if (Persistent.ready) {
            root.attemptRestoreSavedDefaults();
            if (root.sinkRestorePending || root.sourceRestorePending)
                restoreTimer.start();
        }
    }

    Connections {
        target: Persistent
        function onReadyChanged() {
            if (root.settingsApp)
                return;
            if (!Persistent.ready)
                return;

            root.attemptRestoreSavedDefaults();
            if ((root.sinkRestorePending || root.sourceRestorePending) && !restoreTimer.running)
                restoreTimer.start();
        }
    }

    Connections {
        target: sink?.audio ?? null

        function onVolumeChanged() {
            const newVolume = Number(sink?.audio?.volume);
            if (!Number.isNaN(newVolume))
                root.value = newVolume;
        }

        function onMutedChanged() {
            root.muted = sink?.audio?.muted ?? false;
        }
    }

    Connections {
        target: source?.audio ?? null

        function onVolumeChanged() {
            const newVolume = Number(source?.audio?.volume);
            if (!Number.isNaN(newVolume))
                root.micValue = newVolume;
        }

        function onMutedChanged() {
            root.micMuted = source?.audio?.muted ?? false;
        }
    }

    Connections { // Protection against sudden volume changes
        target: sink?.audio ?? null
        property bool lastReady: false
        property real lastVolume: 0
        function onVolumeChanged() {
            if (!Config.options.audio.protection.enable) return;
            const newVolume = sink.audio.volume;
            // when resuming from suspend, we should not write volume to avoid pipewire volume reset issues
            if (isNaN(newVolume) || newVolume === undefined || newVolume === null) {
                lastReady = false;
                lastVolume = 0;
                return;
            }
            if (!lastReady) {
                lastVolume = newVolume;
                lastReady = true;
                return;
            }
            const maxAllowedIncrease = Config.options.audio.protection.maxAllowedIncrease / 100; 
            const maxAllowed = Config.options.audio.protection.maxAllowed / 100;

            if (newVolume - lastVolume > maxAllowedIncrease) {
                sink.audio.volume = lastVolume;
                root.sinkProtectionTriggered(Translation.tr("Illegal increment"));
            } else if (newVolume > maxAllowed || newVolume > root.hardMaxValue) {
                root.sinkProtectionTriggered(Translation.tr("Exceeded max allowed"));
                sink.audio.volume = Math.min(lastVolume, maxAllowed);
            }
            lastVolume = sink.audio.volume;
        }
    }

    function playSystemSound(soundName) {
        const ogaPath = `/usr/share/sounds/${root.audioTheme}/stereo/${soundName}.oga`;
        const oggPath = `/usr/share/sounds/${root.audioTheme}/stereo/${soundName}.ogg`;

        // Try playing .oga first
        let command = [
            "ffplay",
            "-nodisp",
            "-autoexit",
            ogaPath
        ];
        Quickshell.execDetached(command);

        // Also try playing .ogg (ffplay will just fail silently if file doesn't exist)
        command = [
            "ffplay",
            "-nodisp",
            "-autoexit",
            oggPath
        ];
        Quickshell.execDetached(command);
    }
}
