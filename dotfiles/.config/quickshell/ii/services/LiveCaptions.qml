pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.functions as CF
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Singleton {
    id: root

    property string backendKind: "whisper"
    property string sourceMode: "system"
    property string displayMode: "bilingual"
    property string preferredLanguage: "auto"
    property string targetLanguage: "en"
    property string modelName: "tiny"
    property string tuningPreset: "realtime"

    readonly property var backendOptions: [
        { id: "whisper", label: Translation.tr("Whisper"), description: Translation.tr("GPU rolling decode") },
        { id: "asr", label: Translation.tr("Streaming ASR"), description: Translation.tr("Low-latency Vosk") }
    ]

    readonly property var modelOptions: [
        { id: "tiny", label: Translation.tr("Tiny"), description: Translation.tr("Realtime") },
        { id: "base", label: Translation.tr("Base"), description: Translation.tr("Sharper") },
        { id: "small", label: Translation.tr("Small"), description: Translation.tr("Slowest") }
    ]

    readonly property var tuningPresetOptions: [
        { id: "realtime", label: Translation.tr("Realtime"), description: Translation.tr("Fastest") },
        { id: "snappy", label: Translation.tr("Snappy"), description: Translation.tr("Closest to realtime") },
        { id: "balanced", label: Translation.tr("Balanced"), description: Translation.tr("Smoother text") },
        { id: "accurate", label: Translation.tr("Accurate"), description: Translation.tr("More confirmation") }
    ]

    property bool backendAvailable: false
    property bool backendChecked: false
    property bool restartPending: false
    property bool stopRequested: false
    property bool launchPending: false
    property bool workerActive: false
    property string backendStatusText: Translation.tr("Backend not checked yet.")
    property string lastBackendLog: ""

    readonly property bool active: workerActive || launchPending
    readonly property bool translating: displayMode !== "captions"
    property var state: ({
        "status": active ? "running" : "stopped",
        "message": "",
        "current_text": "",
        "stable_text": "",
        "unstable_text": "",
        "translated_text": "",
        "translated_stable_text": "",
        "translated_unstable_text": "",
        "source_language": "",
        "target_language": targetLanguage,
        "history": [],
        "backend_ready": backendAvailable
    })

    readonly property string status: String(state?.status ?? "stopped")
    readonly property string statusMessage: String(state?.message ?? "")
    readonly property string currentText: String(state?.current_text ?? "")
    readonly property string stableText: String(state?.stable_text ?? "")
    readonly property string unstableText: String(state?.unstable_text ?? "")
    readonly property string translatedText: String(state?.translated_text ?? "")
    readonly property string translatedStableText: String(state?.translated_stable_text ?? "")
    readonly property string translatedUnstableText: String(state?.translated_unstable_text ?? "")
    readonly property string sourceLanguage: String(state?.source_language ?? "")
    readonly property string runtimeDevice: String(state?.runtime_device ?? "")
    readonly property var history: state?.history ?? []
    readonly property bool hasText: currentText.trim().length > 0 || translatedText.trim().length > 0
    readonly property bool showTranslatedLine: translating && translatedText.trim().length > 0
    readonly property string transcriptText: root.buildContinuousTranscript(root.history, root.currentText, "text")
    readonly property string translatedTranscriptText: root.buildContinuousTranscript(root.history, root.translatedText, "translated")
    readonly property string visibleTranscriptText: root.tailLimitTranscript(root.transcriptText)
    readonly property string visibleTranslatedTranscriptText: root.tailLimitTranscript(root.translatedTranscriptText)
    readonly property string visibleStableText: root.tailLimitTranscript(root.stableText, 26, 180)
    readonly property string visibleUnstableText: root.tailLimitTranscript(root.unstableText, 12, 90)
    readonly property string visibleTranslatedStableText: root.tailLimitTranscript(root.translatedStableText, 26, 180)
    readonly property string visibleTranslatedUnstableText: root.tailLimitTranscript(root.translatedUnstableText, 20, 180)
    readonly property string summaryText: {
        if (active && status === "loading")
            return Translation.tr("Loading caption model")
        if (active && status === "downloading")
            return Translation.tr("Downloading caption model")
        if (active && status === "running")
            return sourceLanguage.length > 0
                ? runtimeDevice.length > 0
                    ? Translation.tr("Listening • %1 • %2").arg(sourceLanguage.toUpperCase()).arg(runtimeDevice.toUpperCase())
                    : Translation.tr("Listening • %1").arg(sourceLanguage.toUpperCase())
                : runtimeDevice.length > 0
                    ? Translation.tr("Listening • %1").arg(runtimeDevice.toUpperCase())
                    : Translation.tr("Listening")
        if (active && status === "error")
            return Translation.tr("Backend error")
        if (!backendAvailable)
            return Translation.tr("Backend missing")
        return Translation.tr("Stopped")
    }

    function normalizedWords(text) {
        const normalized = String(text ?? "").trim()
        return normalized.length > 0 ? normalized.split(/\s+/) : []
    }

    function mergeContinuousText(baseText, nextText) {
        const base = String(baseText ?? "").trim()
        const next = String(nextText ?? "").trim()

        if (base.length === 0)
            return next
        if (next.length === 0)
            return base

        const baseLower = base.toLowerCase()
        const nextLower = next.toLowerCase()
        if (baseLower === nextLower || baseLower.endsWith(nextLower))
            return base
        if (nextLower.indexOf(baseLower) !== -1)
            return next

        const baseWords = root.normalizedWords(base)
        const nextWords = root.normalizedWords(next)
        const maxOverlap = Math.min(baseWords.length, nextWords.length, 16)

        for (let overlap = maxOverlap; overlap > 0; overlap--) {
            const baseSlice = baseWords.slice(baseWords.length - overlap).join(" ").toLowerCase()
            const nextSlice = nextWords.slice(0, overlap).join(" ").toLowerCase()
            if (baseSlice === nextSlice)
                return `${baseWords.concat(nextWords.slice(overlap)).join(" ")}`
        }

        return `${base} ${next}`
    }

    function buildContinuousTranscript(historyItems, currentLine, key) {
        let merged = ""
        const orderedHistory = (historyItems ?? []).slice().reverse()

        for (const item of orderedHistory)
            merged = root.mergeContinuousText(merged, String(item?.[key] ?? ""))

        return root.mergeContinuousText(merged, currentLine)
    }

    function tailLimitTranscript(text, maxWords = 34, maxChars = 240) {
        const normalized = String(text ?? "").trim()
        if (normalized.length === 0)
            return ""

        let limited = normalized
        const words = root.normalizedWords(normalized)
        if (words.length > maxWords)
            limited = words.slice(words.length - maxWords).join(" ")

        if (limited.length > maxChars)
            limited = limited.slice(limited.length - maxChars).trim()

        return limited !== normalized ? `... ${limited}` : limited
    }

    function escapeRichText(text) {
        return String(text ?? "")
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
    }

    function sourceCaptionMarkup() {
        const stable = root.escapeRichText(root.visibleStableText)
        const unstable = root.escapeRichText(root.visibleUnstableText)

        if (stable.length === 0 && unstable.length === 0)
            return active
                ? root.escapeRichText(Translation.tr("Listening…"))
                : root.escapeRichText(Translation.tr("Not running"))

        if (stable.length === 0)
            return `<span style="color:#CCFFFFFF;">${unstable}</span>`
        if (unstable.length === 0)
            return stable

        return `${stable} <span style="color:#CCFFFFFF;">${unstable}</span>`
    }

    function syncSettingsFromPersistent() {
        if (!Persistent.ready)
            return

        sourceMode = Persistent.states.liveCaptions.source || "system"
        backendKind = Persistent.states.liveCaptions.backend || "whisper"
        displayMode = Persistent.states.liveCaptions.displayMode || "bilingual"
        preferredLanguage = Persistent.states.liveCaptions.preferredLanguage || "auto"
        targetLanguage = Persistent.states.liveCaptions.targetLanguage || "en"
        modelName = Persistent.states.liveCaptions.model || "tiny"
        tuningPreset = Persistent.states.liveCaptions.tuningPreset || "realtime"
    }

    function persistSettings() {
        if (!Persistent.ready)
            return

        Persistent.states.liveCaptions.source = sourceMode
        Persistent.states.liveCaptions.backend = backendKind
        Persistent.states.liveCaptions.displayMode = displayMode
        Persistent.states.liveCaptions.preferredLanguage = preferredLanguage
        Persistent.states.liveCaptions.targetLanguage = targetLanguage
        Persistent.states.liveCaptions.model = modelName
        Persistent.states.liveCaptions.tuningPreset = tuningPreset
    }

    function setSourceMode(mode) {
        if (mode === sourceMode)
            return
        sourceMode = mode
        persistSettings()
        restartIfActive()
    }

    function setBackendKind(backend) {
        if (backend === backendKind)
            return
        backendKind = backend
        persistSettings()
        refreshBackendAvailability()
        restartIfActive()
    }

    function setDisplayMode(mode) {
        if (mode === displayMode)
            return
        displayMode = mode
        persistSettings()
        restartIfActive()
    }

    function setPreferredLanguage(language) {
        if (language === preferredLanguage)
            return
        preferredLanguage = language
        persistSettings()
        restartIfActive()
    }

    function setTargetLanguage(language) {
        if (language === targetLanguage)
            return
        targetLanguage = language
        persistSettings()
        restartIfActive()
    }

    function setModelName(model) {
        if (model === modelName)
            return
        modelName = model
        persistSettings()
        restartIfActive()
    }

    function setTuningPreset(preset) {
        if (preset === tuningPreset)
            return
        tuningPreset = preset
        persistSettings()
        restartIfActive()
    }

    function clearState(statusText = "stopped", messageText = "") {
        const payload = {
            "status": statusText,
            "message": messageText,
            "current_text": "",
            "stable_text": "",
            "unstable_text": "",
            "translated_text": "",
            "translated_stable_text": "",
            "translated_unstable_text": "",
            "source_language": "",
            "target_language": root.targetLanguage,
            "history": [],
            "runtime_device": "",
            "backend_ready": root.backendAvailable
        }
        root.handleStatePayload(payload)
        return payload
    }

    function persistStatePayload(payload) {
        const statePath = CF.StringUtils.shellSingleQuoteEscape(Directories.liveCaptionsStatePath)
        const serialized = CF.StringUtils.shellSingleQuoteEscape(JSON.stringify(payload ?? {}))
        Quickshell.execDetached([
            "bash",
            "-c",
            `printf '%s' '${serialized}' > '${statePath}'`
        ])
    }

    function handleStatePayload(payload) {
        let nextPayload = payload ?? {}
        nextPayload.target_language = nextPayload.target_language ?? root.targetLanguage
        nextPayload.backend_ready = nextPayload.backend_ready ?? root.backendAvailable
        root.state = nextPayload
    }

    function buildBackendLaunchCommand() {
        const backendPythonPath = CF.StringUtils.shellSingleQuoteEscape(Directories.liveCaptionsPythonPath)
        const backendScriptPath = CF.StringUtils.shellSingleQuoteEscape(Directories.liveCaptionsBackendScriptPath)
        const backendStatePath = CF.StringUtils.shellSingleQuoteEscape(Directories.liveCaptionsStatePath)
        const backendModelCachePath = CF.StringUtils.shellSingleQuoteEscape(Directories.liveCaptionsModelCachePath)
        const backendVenvPath = CF.StringUtils.shellSingleQuoteEscape(Directories.liveCaptionsVenvPath)
        const backendPidPath = CF.StringUtils.shellSingleQuoteEscape(Directories.liveCaptionsPidPath)
        const backendLogPath = CF.StringUtils.shellSingleQuoteEscape(Directories.liveCaptionsLogPath)
        const sourceMode = CF.StringUtils.shellSingleQuoteEscape(root.sourceMode)
        const backendKind = CF.StringUtils.shellSingleQuoteEscape(root.backendKind)
        const displayMode = CF.StringUtils.shellSingleQuoteEscape(root.displayMode)
        const preferredLanguage = CF.StringUtils.shellSingleQuoteEscape(root.preferredLanguage)
        const targetLanguage = CF.StringUtils.shellSingleQuoteEscape(root.targetLanguage)
        const modelName = CF.StringUtils.shellSingleQuoteEscape(root.modelName)
        const tuningPreset = CF.StringUtils.shellSingleQuoteEscape(root.tuningPreset)
        const launchScript =
            `rm -f '${backendPidPath}'; ` +
            `: > '${backendLogPath}'; ` +
            `backend_venv='${backendVenvPath}'; ` +
            `cuda_lib_path=''; ` +
            `for libdir in "$backend_venv"/lib/python*/site-packages/nvidia/*/lib; do ` +
            `  [ -d "$libdir" ] || continue; ` +
            `  if [ -n "$cuda_lib_path" ]; then cuda_lib_path="$cuda_lib_path:$libdir"; else cuda_lib_path="$libdir"; fi; ` +
            `done; ` +
            `if [ -n "$cuda_lib_path" ]; then export LD_LIBRARY_PATH="$cuda_lib_path\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"; fi; ` +
            `if [ -x '${backendPythonPath}' ]; then backend_python='${backendPythonPath}'; else backend_python='python3'; fi; ` +
            `nohup "$backend_python" '${backendScriptPath}' ` +
            `--state-file '${backendStatePath}' ` +
            `--backend '${backendKind}' ` +
            `--source '${sourceMode}' ` +
            `--display-mode '${displayMode}' ` +
            `--language '${preferredLanguage}' ` +
            `--target-language '${targetLanguage}' ` +
            `--model '${modelName}' ` +
            `--preset '${tuningPreset}' ` +
            `--model-cache-dir '${backendModelCachePath}' ` +
            `>>'${backendLogPath}' 2>&1 & echo $! > '${backendPidPath}'`
        return [
            "bash",
            "-c",
            launchScript
        ]
    }

    function buildWorkerStatusCommand() {
        const backendPidPath = CF.StringUtils.shellSingleQuoteEscape(Directories.liveCaptionsPidPath)
        return [
            "bash",
            "-c",
            `if [ -f '${backendPidPath}' ]; then ` +
            `pid="$(cat '${backendPidPath}')"; ` +
            `if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then exit 0; fi; ` +
            `rm -f '${backendPidPath}'; fi; exit 1`
        ]
    }

    function buildStopCommand() {
        const backendPidPath = CF.StringUtils.shellSingleQuoteEscape(Directories.liveCaptionsPidPath)
        return [
            "bash",
            "-c",
            `if [ -f '${backendPidPath}' ]; then ` +
            `pid="$(cat '${backendPidPath}')"; ` +
            `if [ -n "$pid" ]; then kill "$pid" 2>/dev/null || true; fi; ` +
            `rm -f '${backendPidPath}'; fi`
        ]
    }

    function updateWorkerState(isRunning) {
        const wasActive = root.workerActive || root.launchPending
        root.workerActive = isRunning

        if (isRunning) {
            root.launchPending = false
            return
        }

        if (!wasActive)
            return

        const shouldRestart = root.restartPending
        const expectedStop = root.stopRequested || root.restartPending
        root.launchPending = false
        root.workerActive = false

        if (expectedStop) {
            root.persistStatePayload(root.clearState("stopped", Translation.tr("Live captions stopped.")))
        } else {
            stateFileView.reload()
            const payload = {
                "status": "error",
                "message": root.statusMessage.trim().length > 0
                    ? root.statusMessage
                    : Translation.tr("Live captions backend exited before it could stay running."),
                "current_text": root.currentText,
                "stable_text": root.stableText,
                "unstable_text": root.unstableText,
                "translated_text": root.translatedText,
                "translated_stable_text": root.translatedStableText,
                "translated_unstable_text": root.translatedUnstableText,
                "source_language": root.sourceLanguage,
                "target_language": root.targetLanguage,
                "history": root.history,
                "runtime_device": root.runtimeDevice,
                "backend_ready": root.backendAvailable
            }
            root.handleStatePayload(payload)
            root.persistStatePayload(payload)
        }

        root.stopRequested = false
        root.restartPending = false
        root.refreshBackendAvailability()
        if (shouldRestart)
            delayedStartTimer.restart()
    }

    function refreshBackendAvailability() {
        backendProbe.running = false
        backendProbe.running = true
    }

    function start() {
        if (root.active)
            return

        if (!backendAvailable) {
            clearState("error", Translation.tr("Live captions backend is not installed yet."))
            refreshBackendAvailability()
            return
        }

        root.stopRequested = false
        root.restartPending = false
        root.launchPending = true
        root.workerActive = false
        root.persistStatePayload(root.clearState("loading", Translation.tr("Starting live captions…")))
        Quickshell.execDetached(buildBackendLaunchCommand())
        launchTimeoutTimer.restart()
        workerStatusTimer.restart()
    }

    function stop() {
        root.stopRequested = true
        root.launchPending = false
        root.workerActive = false
        Quickshell.execDetached(buildStopCommand())
        root.persistStatePayload(root.clearState("stopped", Translation.tr("Live captions stopped.")))
    }

    function toggleRunning() {
        if (root.active)
            stop()
        else
            start()
    }

    function restartIfActive() {
        if (!root.active)
            return
        root.restartPending = true
        root.stopRequested = false
        restartTimer.restart()
    }

    function openInstaller() {
        Quickshell.execDetached([
            "bash",
            "-lc",
            `${Config.options.apps.terminal} -e '${CF.StringUtils.shellSingleQuoteEscape(Directories.liveCaptionsInstallScriptPath)}'`
        ])
    }

    Timer {
        id: restartTimer
        interval: 150
        repeat: false
        onTriggered: {
            root.stop()
        }
    }

    Timer {
        id: delayedStartTimer
        interval: 150
        repeat: false
        onTriggered: root.start()
    }

    Timer {
        id: statePollTimer
        interval: 60
        repeat: true
        running: root.active || GlobalStates.liveCaptionsOpen
        onTriggered: stateFileView.reload()
    }

    Timer {
        id: workerStatusTimer
        interval: 350
        repeat: true
        running: root.active || GlobalStates.liveCaptionsOpen
        onTriggered: {
            if (!workerStatusProc.running) {
                workerStatusProc.command = buildWorkerStatusCommand()
                workerStatusProc.running = true
            }
        }
    }

    Timer {
        id: launchTimeoutTimer
        interval: 2500
        repeat: false
        onTriggered: {
            if (root.launchPending && !root.workerActive)
                root.updateWorkerState(false)
        }
    }

    FileView {
        id: stateFileView
        path: Directories.liveCaptionsStatePath
        watchChanges: false
        onLoaded: {
            try {
                const parsed = JSON.parse(stateFileView.text() || "{}")
                root.handleStatePayload(parsed)
            } catch (e) {
                root.handleStatePayload({
                    "status": "error",
                    "message": Translation.tr("Could not parse caption state."),
                    "current_text": "",
                    "stable_text": "",
                    "unstable_text": "",
                    "translated_text": "",
                    "translated_stable_text": "",
                    "translated_unstable_text": "",
                    "source_language": "",
                    "target_language": root.targetLanguage,
                    "history": [],
                    "runtime_device": "",
                    "backend_ready": root.backendAvailable
                })
            }
        }
    }

    Process {
        id: backendProbe
        command: [
            "bash",
            "-c",
            `if [ -x '${CF.StringUtils.shellSingleQuoteEscape(Directories.liveCaptionsPythonPath)}' ]; then ` +
            `exec '${CF.StringUtils.shellSingleQuoteEscape(Directories.liveCaptionsPythonPath)}' -c 'import faster_whisper, vosk'; ` +
            `else exec python3 -c 'import faster_whisper, vosk'; fi`
        ]
        onExited: (exitCode, exitStatus) => {
            root.backendChecked = true
            root.backendAvailable = exitCode === 0
            root.backendStatusText = root.backendAvailable
                ? Translation.tr("Backend ready.")
                : Translation.tr("Install the live captions backend to enable transcription.")
            if (!root.backendAvailable && !root.active && root.status !== "error")
                root.clearState("stopped", root.backendStatusText)
        }
    }

    Process {
        id: workerStatusProc
        onExited: (exitCode, exitStatus) => {
            root.updateWorkerState(exitCode === 0)
        }
    }

    Connections {
        target: Persistent
        function onReadyChanged() {
            if (!Persistent.ready)
                return
            root.syncSettingsFromPersistent()
        }
    }

    IpcHandler {
        target: "liveCaptions"

        function start() { root.start(); }
        function stop() { root.stop(); }
        function toggle() { root.toggleRunning(); }
        function state() { return JSON.stringify(root.state); }
    }

    Component.onCompleted: {
        root.syncSettingsFromPersistent()
        root.refreshBackendAvailability()
        root.clearState("stopped", Translation.tr("Live captions stopped."))
    }
}
