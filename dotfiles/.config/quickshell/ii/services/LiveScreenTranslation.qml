pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.functions as CF
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string targetLanguage: "en"
    property string region: ""
    property string regionLabel: ""

    property bool backendAvailable: false
    property bool backendChecked: false
    property bool launchPending: false
    property bool workerActive: false
    property bool restartPending: false
    property bool stopRequested: false
    property bool selectingRegion: false
    property string backendStatusText: Translation.tr("Backend not checked yet.")
    property int recoveryAttempts: 0
    property int workerGeneration: 0

    readonly property bool recovering: recoveryTimer.running
    readonly property bool active: workerActive || launchPending || recovering || stopRequested
    readonly property bool desiredRunning: Persistent.ready && Persistent.states.liveScreenTranslation.desiredRunning
    readonly property string ocrLanguage: "eng"
    readonly property var targetLanguageOptions: [
        { id: "en", label: Translation.tr("English") },
        { id: "it", label: Translation.tr("Italian") },
        { id: "de", label: Translation.tr("German") },
        { id: "fr", label: Translation.tr("French") },
        { id: "es", label: Translation.tr("Spanish") }
    ]
    property var state: ({
        "status": active ? "running" : "stopped",
        "message": "",
        "ocr_text": "",
        "translated_text": "",
        "target_language": targetLanguage,
        "ocr_language": ocrLanguage,
        "region": region,
    })

    readonly property string status: String(state?.status ?? "stopped")
    readonly property string statusMessage: String(state?.message ?? "")
    readonly property string ocrText: String(state?.ocr_text ?? "")
    readonly property string translatedText: String(state?.translated_text ?? "")
    readonly property string summaryText: {
        if (stopRequested)
            return Translation.tr("Stopping")
        if (selectingRegion)
            return Translation.tr("Selecting region")
        if (recovering)
            return Translation.tr("Reconnecting")
        if (active && status === "running")
            return region.length > 0
                ? Translation.tr("Watching selected area")
                : Translation.tr("No region selected")
        if (active && status === "error")
            return Translation.tr("OCR error")
        if (!backendAvailable)
            return Translation.tr("OCR tools missing")
        if (region.length === 0)
            return Translation.tr("No region selected")
        return Translation.tr("Stopped")
    }

    function isValidGeometry(r) {
        // Monitors to the left/above the primary have negative coordinates.
        const number = "(?:\\d+(?:\\.\\d+)?|\\.\\d+)"
        const match = new RegExp(`^([+-]?${number}),([+-]?${number})\\s+(${number})x(${number})$`)
            .exec(String(r ?? "").trim())
        return match !== null && match.slice(1).every(value => Number.isFinite(Number(value)))
            && Number(match[3]) > 0 && Number(match[4]) > 0
    }

    function normalizedGeometry(r) {
        if (!isValidGeometry(r))
            return ""
        const values = String(r).trim().split(/[,x\s]+/).map(value => {
            const number = Number(value)
            const lower = Math.floor(number)
            // Match Python round() at exact half pixels.
            return number - lower === 0.5 ? lower + Math.abs(lower % 2) : Math.round(number)
        })
        return `${values[0]},${values[1]} ${Math.max(1, values[2])}x${Math.max(1, values[3])}`
    }

    function syncSettingsFromPersistent() {
        if (!Persistent.ready)
            return

        targetLanguage = Persistent.states.liveScreenTranslation.targetLanguage || "en"
        const savedRegion = Persistent.states.liveScreenTranslation.region || ""
        if (savedRegion.length > 0 && !isValidGeometry(savedRegion)) {
            // Corrupted region — clear it silently
            region = ""
            regionLabel = ""
            Persistent.states.liveScreenTranslation.region = ""
            Persistent.states.liveScreenTranslation.regionLabel = ""
        } else {
            region = savedRegion
            regionLabel = Persistent.states.liveScreenTranslation.regionLabel || savedRegion
        }
    }

    function persistSettings() {
        if (!Persistent.ready)
            return

        Persistent.states.liveScreenTranslation.targetLanguage = targetLanguage
        Persistent.states.liveScreenTranslation.region = region
        Persistent.states.liveScreenTranslation.regionLabel = regionLabel
    }

    function setDesiredRunning(enabled) {
        if (Persistent.ready)
            Persistent.states.liveScreenTranslation.desiredRunning = enabled
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
        if (root.desiredRunning && root.backendAvailable && root.isValidGeometry(root.region)
                && !root.active && !root.stopRequested)
            root.scheduleRecovery()
    }

    function clearState(statusText = "stopped", messageText = "") {
        const payload = {
            "status": statusText,
            "message": messageText,
            "ocr_text": "",
            "translated_text": "",
            "target_language": root.targetLanguage,
            "ocr_language": root.ocrLanguage,
            "region": root.region,
        }
        root.state = payload
        return payload
    }

    function stateWriteCommand(payload) {
        const statePath = CF.StringUtils.shellSingleQuoteEscape(Directories.liveScreenTranslationStatePath)
        const serialized = CF.StringUtils.shellSingleQuoteEscape(JSON.stringify(payload ?? {}))
        return `state_path='${statePath}'; tmp_path="$state_path.tmp.$$"; ` +
            `mkdir -p -- "$(dirname -- "$state_path")" || exit 1; umask 077; ` +
            `trap 'rm -f -- "$tmp_path"' EXIT; ` +
            `printf '%s' '${serialized}' > "$tmp_path" && mv -f -- "$tmp_path" "$state_path" || exit 1; `
    }

    function buildBackendLaunchCommand() {
        const scriptPath = CF.StringUtils.shellSingleQuoteEscape(Directories.liveScreenTranslationBackendScriptPath)
        const statePath = CF.StringUtils.shellSingleQuoteEscape(Directories.liveScreenTranslationStatePath)
        const pidPath = CF.StringUtils.shellSingleQuoteEscape(Directories.liveScreenTranslationPidPath)
        const logPath = CF.StringUtils.shellSingleQuoteEscape(Directories.liveScreenTranslationLogPath)
        const region = CF.StringUtils.shellSingleQuoteEscape(root.region)
        const targetLanguage = CF.StringUtils.shellSingleQuoteEscape(root.targetLanguage)
        const ocrLanguage = CF.StringUtils.shellSingleQuoteEscape(root.ocrLanguage)
        const launchScript = workerShellPrelude() +
            `pid="$(cat "$pid_path" 2>/dev/null)"; worker_alive && exit 0; ` +
            stateWriteCommand(root.state) +
            `rm -f '${pidPath}'; ` +
            `: > '${logPath}'; ` +
            `nohup python3 '${scriptPath}' ` +
            `--state-file '${statePath}' ` +
            `--region='${region}' ` +
            `--target-language '${targetLanguage}' ` +
            `--ocr-language '${ocrLanguage}' ` +
            `>>'${logPath}' 2>&1 </dev/null & echo $! > '${pidPath}'`
        return ["bash", "-c", launchScript]
    }

    function workerShellPrelude() {
        const pidPath = CF.StringUtils.shellSingleQuoteEscape(Directories.liveScreenTranslationPidPath)
        const scriptPath = CF.StringUtils.shellSingleQuoteEscape(Directories.liveScreenTranslationBackendScriptPath)
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

    function refreshBackendAvailability() {
        if (backendProbe.running)
            return
        backendProbe.running = true
    }

    function setTargetLanguage(language) {
        if (language === targetLanguage)
            return
        targetLanguage = language
        persistSettings()
        restartIfActive()
    }

    function selectRegion() {
        if (selectingRegion)
            return
        selectingRegion = true
        GlobalStates.overlayOpen = false
        regionSelectionProc.running = true
    }

    function clearRegion() {
        selectingRegion = false
        regionSelectionProc.running = false
        region = ""
        regionLabel = ""
        persistSettings()
        stop()
        clearState("stopped", Translation.tr("No capture region selected."))
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
            clearState("error", Translation.tr("OCR tools are not available yet."))
            refreshBackendAvailability()
            return
        }
        if (!isValidGeometry(region)) {
            if (region.length > 0) {
                region = ""
                regionLabel = ""
                persistSettings()
            }
            clearState("error", Translation.tr("Select a screen region first."))
            return
        }

        root.restartPending = false
        root.workerGeneration += 1
        root.launchPending = true
        root.workerActive = false
        root.clearState("loading", Translation.tr("Starting live screen translation…"))
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
        root.clearState("stopped", Translation.tr("Live screen translation stopped."))
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
        if (active)
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
                    : Translation.tr("Live screen translation backend exited unexpectedly.")
            })
            stateFileView.reload()
        }
        if (!root.restartPending)
            root.ensureDesiredWorker()
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
        id: launchTimeoutTimer
        interval: 6000
        repeat: false
        onTriggered: {
            if (root.launchPending && !root.workerActive)
                root.updateWorkerState(false)
        }
    }

    Timer {
        id: statePollTimer
        interval: 1000
        repeat: true
        running: root.active
        onTriggered: stateFileView.reload()
    }

    Timer {
        id: workerStatusTimer
        interval: 2500
        repeat: true
        running: root.active
        onTriggered: root.probeWorker()
    }

    Timer {
        id: initialWorkerProbeTimer
        interval: 400
        repeat: false
        onTriggered: root.probeWorker()
    }

    FileView {
        id: stateFileView
        path: Directories.liveScreenTranslationStatePath
        watchChanges: true
        onFileChanged: stateReloadDebounce.restart()
        onLoaded: {
            // Ignore a previous worker's final write during stop/reconfigure.
            if (root.stopRequested || root.restartPending || root.launchPending
                    || (!root.active && !root.desiredRunning))
                return
            try {
                const payload = JSON.parse(stateFileView.text() || "{}")
                if (!payload || typeof payload !== "object" || Array.isArray(payload))
                    throw new Error("Invalid OCR state")
                if ((payload.target_language && payload.target_language !== root.targetLanguage)
                        || (payload.region && root.normalizedGeometry(payload.region) !== root.normalizedGeometry(root.region)))
                    return
                root.state = payload
            } catch (e) {
                root.state = root.clearState("error", Translation.tr("Could not parse OCR state."))
            }
        }
    }

    Timer {
        id: stateReloadDebounce
        interval: 30
        repeat: false
        onTriggered: stateFileView.reload()
    }

    Process {
        id: backendProbe
        command: [
            "bash",
            "-lc",
            "command -v python3 >/dev/null && command -v grim >/dev/null && command -v slurp >/dev/null && command -v tesseract >/dev/null && command -v trans >/dev/null && tesseract --list-langs 2>/dev/null | awk 'NR>1{print $1}' | grep -qx eng"
        ]
        onExited: (exitCode, exitStatus) => {
            root.backendChecked = true
            root.backendAvailable = exitCode === 0
            root.backendStatusText = root.backendAvailable
                ? Translation.tr("OCR backend ready.")
                : Translation.tr("Need grim, slurp, trans, and the English tesseract language pack.")
            root.ensureDesiredWorker()
        }
    }

    Process {
        id: regionSelectionProc
        command: ["bash", "-c", "exec slurp"]
        stdout: StdioCollector {
            onStreamFinished: {
                const selected = String(this.text ?? "").trim()
                if (!root.selectingRegion || !root.isValidGeometry(selected))
                    return
                root.region = selected
                root.regionLabel = selected
                root.persistSettings()
                root.restartIfActive()
            }
        }
        onExited: root.selectingRegion = false
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
            root.probeWorker()
        }
    }

    Component.onCompleted: {
        root.syncSettingsFromPersistent()
        root.refreshBackendAvailability()
        stateFileView.reload()
        root.probeWorker()
    }
}
