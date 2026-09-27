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
    property int recoveryAttempts: 0
    property int workerGeneration: 0

    readonly property bool recovering: recoveryTimer.running
    readonly property bool active: workerActive || launchPending || recovering || stopRequested
    readonly property bool desiredRunning: Persistent.ready && Persistent.states.liveCaptions.desiredRunning
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
        if (stopRequested)
            return Translation.tr("Stopping")
        if (recovering)
            return Translation.tr("Reconnecting")
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
        const tentativeColor = Appearance.colors.colOnSurfaceVariant.toString()

        if (stable.length === 0 && unstable.length === 0)
            return active
                ? root.escapeRichText(Translation.tr("Listening…"))
                : root.escapeRichText(Translation.tr("Not running"))

        if (stable.length === 0)
            return `<span style="color:${tentativeColor};">${unstable}</span>`
        if (unstable.length === 0)
            return stable

        return `${stable} <span style="color:${tentativeColor};">${unstable}</span>`
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

    function setDesiredRunning(enabled) {
        if (Persistent.ready)
            Persistent.states.liveCaptions.desiredRunning = enabled
    }

    function probeWorker() {
        if (workerStatusProc.running || workerLaunchProc.running || root.stopRequested)
            return
        workerStatusProc.generation = root.workerGeneration
        workerStatusProc.command = buildWorkerStatusCommand()
        workerStatusProc.running = true
    }

    function scheduleRecovery() {
        if (!root.desiredRunning || root.stopRequested || root.active || recoveryTimer.running)
            return
        root.recoveryAttempts += 1
        recoveryTimer.interval = Math.min(30000, 1000 * Math.pow(2, Math.min(root.recoveryAttempts - 1, 5)))
        recoveryTimer.restart()
    }

    function ensureDesiredWorker() {
        if (root.desiredRunning && root.backendAvailable && !root.active && !root.stopRequested)
            root.scheduleRecovery()
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
        backendAvailable = false
        persistSettings()
        refreshBackendAvailability()
        restartIfActive()
    }

    function setDisplayMode(mode) {
        if (mode === displayMode)
            return
        displayMode = mode
        backendAvailable = false
        persistSettings()
        refreshBackendAvailability()
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

    function stateWriteCommand(payload) {
        const statePath = CF.StringUtils.shellSingleQuoteEscape(Directories.liveCaptionsStatePath)
        const serialized = CF.StringUtils.shellSingleQuoteEscape(JSON.stringify(payload ?? {}))
        return `state_path='${statePath}'; tmp_path="$state_path.tmp.$$"; ` +
            `mkdir -p -- "$(dirname -- "$state_path")" || exit 1; umask 077; ` +
            `trap 'rm -f -- "$tmp_path"' EXIT; ` +
            `printf '%s' '${serialized}' > "$tmp_path" && mv -f -- "$tmp_path" "$state_path" || exit 1; `
    }

    function handleStatePayload(payload) {
        if (!payload || typeof payload !== "object" || Array.isArray(payload))
            throw new Error("Invalid caption state")
        if (payload.target_language && payload.target_language !== root.targetLanguage)
            return
        let nextPayload = Object.assign({}, payload)
        nextPayload.target_language = nextPayload.target_language ?? root.targetLanguage
        nextPayload.backend_ready = nextPayload.backend_ready ?? root.backendAvailable
        nextPayload.history = Array.isArray(nextPayload.history) ? nextPayload.history : []
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
        const launchScript = workerShellPrelude() +
            `pid="$(cat "$pid_path" 2>/dev/null)"; worker_alive && exit 0; ` +
            stateWriteCommand(root.state) +
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
            `>>'${backendLogPath}' 2>&1 </dev/null & echo $! > '${backendPidPath}'`
        return [
            "bash",
            "-c",
            launchScript
        ]
    }

    function workerShellPrelude() {
        const pidPath = CF.StringUtils.shellSingleQuoteEscape(Directories.liveCaptionsPidPath)
        const scriptPath = CF.StringUtils.shellSingleQuoteEscape(Directories.liveCaptionsBackendScriptPath)
        return `pid_path='${pidPath}'; ` +
            `worker_alive() { [[ "$pid" =~ ^[1-9][0-9]*$ ]] && [ "$pid" -gt 1 ] && ` +
            `kill -0 "$pid" 2>/dev/null && ` +
            `tr '\\0' '\\n' < "/proc/$pid/cmdline" 2>/dev/null | grep -Fxq -- '${scriptPath}'; }; `
    }

    function buildWorkerStatusCommand() {
        return ["bash", "-c", workerShellPrelude() +
            `pid="$(cat "$pid_path" 2>/dev/null)"; worker_alive`]
    }

    function buildStopCommand() {
        return ["bash", "-c", workerShellPrelude() +
            `pid="$(cat "$pid_path" 2>/dev/null)"; ` +
            `if worker_alive; then ` +
            `kill -- "$pid" 2>/dev/null || true; ` +
            `for ((attempt=0; attempt<100; attempt++)); do worker_alive || break; sleep 0.1; done; ` +
            `worker_alive && exit 1; fi; ` +
            `rm -f -- "$pid_path"; ` + stateWriteCommand(root.state)]
    }

    function updateWorkerState(isRunning) {
        if (root.stopRequested)
            return
        const wasActive = root.workerActive || root.launchPending
        const wasWorkerActive = root.workerActive
        root.workerActive = isRunning

        if (isRunning) {
            root.launchPending = false
            launchTimeoutTimer.stop()
            recoveryTimer.stop()
            if (!wasWorkerActive)
                stableWorkerTimer.restart()
            stateFileView.reload()
            return
        }

        root.launchPending = false
        stableWorkerTimer.stop()
        if (wasActive && !root.restartPending) {
            root.state = Object.assign({}, root.state, {
                status: "error",
                message: root.status === "error" && root.statusMessage.trim().length > 0
                    ? root.statusMessage
                    : Translation.tr("Live captions backend exited unexpectedly.")
            })
            stateFileView.reload()
        }
        if (!root.restartPending)
            root.ensureDesiredWorker()
    }

    function refreshBackendAvailability() {
        if (backendProbe.running)
            return
        backendProbe.backend = root.backendKind
        backendProbe.needsTranslation = root.translating
        backendProbe.running = true
    }

    function start(recovery = false) {
        if (recovery && !root.desiredRunning)
            return
        if (!recovery) {
            root.setDesiredRunning(true)
            root.recoveryAttempts = 0
        }
        recoveryTimer.stop()
        if (root.stopRequested) {
            root.restartPending = true
            return
        }
        if (root.active)
            return
        if (!backendAvailable) {
            clearState("error", Translation.tr("Live captions backend is not installed yet."))
            refreshBackendAvailability()
            return
        }

        root.restartPending = false
        root.workerGeneration += 1
        root.launchPending = true
        root.workerActive = false
        root.clearState("loading", Translation.tr("Starting live captions…"))
        workerLaunchProc.command = buildBackendLaunchCommand()
        workerLaunchProc.running = true
    }

    function stop(preserveRunIntent = false) {
        restartTimer.stop()
        recoveryTimer.stop()
        stableWorkerTimer.stop()
        launchTimeoutTimer.stop()
        initialWorkerProbeTimer.stop()
        if (!preserveRunIntent) {
            root.setDesiredRunning(false)
            root.restartPending = false
            root.recoveryAttempts = 0
        }
        root.workerGeneration += 1
        root.stopRequested = true
        root.clearState("stopped", Translation.tr("Live captions stopped."))
        // A launch must finish writing its PID before the stop can find it.
        if (!workerLaunchProc.running)
            root.stopWorker()
    }

    function stopWorker() {
        if (workerStopProc.running)
            return
        workerStopProc.command = buildStopCommand()
        workerStopProc.running = true
    }

    function toggleRunning() {
        if (root.active)
            stop()
        else
            start()
    }

    function restartIfActive() {
        if (!root.active) {
            root.clearState()
            root.ensureDesiredWorker()
            return
        }
        root.restartPending = true
        root.clearState("loading", Translation.tr("Applying settings…"))
        if (!root.stopRequested)
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
        onTriggered: root.stop(true)
    }

    Timer {
        id: recoveryTimer
        interval: 1000
        repeat: false
        onTriggered: root.start(true)
    }

    Timer {
        id: stableWorkerTimer
        interval: 30000
        repeat: false
        onTriggered: root.recoveryAttempts = 0
    }

    Timer {
        id: statePollTimer
        // File notifications provide live captions; this is only a fallback
        // for atomic replacements or missed inotify events.
        interval: 1000
        repeat: true
        running: root.active || GlobalStates.liveCaptionsOpen
        onTriggered: stateFileView.reload()
    }

    Timer {
        id: workerStatusTimer
        interval: 2500
        repeat: true
        running: root.active || GlobalStates.liveCaptionsOpen
        onTriggered: root.probeWorker()
    }

    Timer {
        id: initialWorkerProbeTimer
        interval: 400
        repeat: false
        onTriggered: root.probeWorker()
    }

    Timer {
        id: launchTimeoutTimer
        interval: 6000
        repeat: false
        onTriggered: {
            if (root.launchPending && !root.workerActive)
                root.updateWorkerState(false)
        }
    }

    FileView {
        id: stateFileView
        path: Directories.liveCaptionsStatePath
        watchChanges: true
        onFileChanged: stateReloadDebounce.restart()
        onLoaded: {
            // Ignore a previous worker's final write during stop/reconfigure.
            if (root.stopRequested || root.restartPending || root.launchPending
                    || (!root.active && !root.desiredRunning))
                return
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

    Timer {
        id: stateReloadDebounce
        interval: 20
        repeat: false
        onTriggered: stateFileView.reload()
    }

    Process {
        id: backendProbe
        property string backend: "whisper"
        property bool needsTranslation: true
        command: [
            "bash",
            "-c",
            `command -v ffmpeg >/dev/null && command -v pactl >/dev/null || exit 1; ` +
            (needsTranslation ? `command -v trans >/dev/null || exit 1; ` : "") +
            `if [ -x '${CF.StringUtils.shellSingleQuoteEscape(Directories.liveCaptionsPythonPath)}' ]; then ` +
            `backend_python='${CF.StringUtils.shellSingleQuoteEscape(Directories.liveCaptionsPythonPath)}'; ` +
            `else backend_python=python3; fi; ` +
            `exec "$backend_python" -c 'import numpy, ${backend === "asr" ? "vosk" : "faster_whisper"}'`
        ]
        onExited: (exitCode, exitStatus) => {
            if (backend !== root.backendKind || needsTranslation !== root.translating) {
                root.refreshBackendAvailability()
                return
            }
            root.backendChecked = true
            root.backendAvailable = exitCode === 0
            root.backendStatusText = root.backendAvailable
                ? Translation.tr("Backend ready.")
                : Translation.tr("Install the live captions backend to enable transcription.")
            if (!root.backendAvailable && !root.active && root.status !== "error")
                root.clearState("stopped", root.backendStatusText)
            root.ensureDesiredWorker()
        }
    }

    Process {
        id: workerLaunchProc
        onExited: (exitCode, exitStatus) => {
            if (root.stopRequested) {
                root.stopWorker()
                return
            }
            if (exitCode !== 0) {
                root.updateWorkerState(false)
                return
            }
            launchTimeoutTimer.restart()
            initialWorkerProbeTimer.restart()
        }
    }

    Process {
        id: workerStopProc
        onExited: (exitCode, exitStatus) => {
            const shouldRestart = root.restartPending && root.desiredRunning
            root.stopRequested = false
            root.launchPending = false
            root.restartPending = false
            if (exitCode !== 0) {
                // Retain the PID and block replacement if the old worker is
                // still decoding/loading. A later Stop can try again.
                root.workerActive = true
                root.clearState("error", Translation.tr("The backend is still stopping. Try stopping it again shortly."))
                return
            }
            root.workerActive = false
            if (shouldRestart)
                root.start(true)
        }
    }

    Process {
        id: workerStatusProc
        property int generation: -1
        onExited: (exitCode, exitStatus) => {
            if (generation !== root.workerGeneration || root.stopRequested)
                return
            if (exitCode === 0)
                root.updateWorkerState(true)
            else if (!root.launchPending || !launchTimeoutTimer.running)
                root.updateWorkerState(false)
        }
    }

    Connections {
        target: Persistent
        function onReadyChanged() {
            if (!Persistent.ready)
                return
            root.syncSettingsFromPersistent()
            root.refreshBackendAvailability()
            root.probeWorker()
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
        stateFileView.reload()
        root.probeWorker()
    }
}
