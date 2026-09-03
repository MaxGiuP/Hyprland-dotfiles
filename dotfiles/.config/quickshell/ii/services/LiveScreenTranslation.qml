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

    readonly property bool recovering: recoveryTimer.running
    readonly property bool active: workerActive || launchPending || recovering
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
        // Must match slurp output: 'X,Y WxH' with numbers (possibly decimal)
        return /^[\d.]+,[\d.]+\s+[\d.]+x[\d.]+$/.test(String(r ?? "").trim())
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
        if (workerStatusProc.running)
            return
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

    function persistStatePayload(payload) {
        const statePath = CF.StringUtils.shellSingleQuoteEscape(Directories.liveScreenTranslationStatePath)
        const serialized = CF.StringUtils.shellSingleQuoteEscape(JSON.stringify(payload ?? {}))
        Quickshell.execDetached([
            "bash",
            "-c",
            `state_path='${statePath}'; tmp_path="$state_path.tmp.$$"; ` +
            `trap 'rm -f -- "$tmp_path"' EXIT; umask 077; ` +
            `printf '%s' '${serialized}' > "$tmp_path" && mv -f -- "$tmp_path" "$state_path"`
        ])
    }

    function buildBackendLaunchCommand() {
        const scriptPath = CF.StringUtils.shellSingleQuoteEscape(Directories.liveScreenTranslationBackendScriptPath)
        const statePath = CF.StringUtils.shellSingleQuoteEscape(Directories.liveScreenTranslationStatePath)
        const pidPath = CF.StringUtils.shellSingleQuoteEscape(Directories.liveScreenTranslationPidPath)
        const logPath = CF.StringUtils.shellSingleQuoteEscape(Directories.liveScreenTranslationLogPath)
        const region = CF.StringUtils.shellSingleQuoteEscape(root.region)
        const targetLanguage = CF.StringUtils.shellSingleQuoteEscape(root.targetLanguage)
        const ocrLanguage = CF.StringUtils.shellSingleQuoteEscape(root.ocrLanguage)
        const launchScript =
            `rm -f '${pidPath}'; ` +
            `: > '${logPath}'; ` +
            `nohup python3 '${scriptPath}' ` +
            `--state-file '${statePath}' ` +
            `--region '${region}' ` +
            `--target-language '${targetLanguage}' ` +
            `--ocr-language '${ocrLanguage}' ` +
            `>>'${logPath}' 2>&1 & echo $! > '${pidPath}'`
        return ["bash", "-c", launchScript]
    }

    function buildWorkerStatusCommand() {
        const pidPath = CF.StringUtils.shellSingleQuoteEscape(Directories.liveScreenTranslationPidPath)
        const scriptPath = CF.StringUtils.shellSingleQuoteEscape(Directories.liveScreenTranslationBackendScriptPath)
        return [
            "bash",
            "-c",
            `if [ -f '${pidPath}' ]; then pid="$(cat '${pidPath}')"; ` +
            `if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null ` +
            `&& tr '\\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -Fq -- '${scriptPath}'; then exit 0; fi; ` +
            `rm -f '${pidPath}'; fi; exit 1`
        ]
    }

    function buildStopCommand() {
        const pidPath = CF.StringUtils.shellSingleQuoteEscape(Directories.liveScreenTranslationPidPath)
        const scriptPath = CF.StringUtils.shellSingleQuoteEscape(Directories.liveScreenTranslationBackendScriptPath)
        return [
            "bash",
            "-c",
            `if [ -f '${pidPath}' ]; then pid="$(cat '${pidPath}')"; ` +
            `if [ -n "$pid" ] && tr '\\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -Fq -- '${scriptPath}'; ` +
            `then kill "$pid" 2>/dev/null || true; fi; ` +
            `rm -f '${pidPath}'; fi`
        ]
    }

    function refreshBackendAvailability() {
        backendProbe.running = false
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
        const selectionPath = CF.StringUtils.shellSingleQuoteEscape(Directories.liveScreenTranslationSelectionPath)
        Quickshell.execDetached(["bash", "-lc",
            `rm -f '${selectionPath}'; slurp > '${selectionPath}' 2>/dev/null; [ -s '${selectionPath}' ] || printf '__CANCELLED__' > '${selectionPath}'`
        ])
        selectionPollTimer.restart()
    }

    function clearRegion() {
        region = ""
        regionLabel = ""
        persistSettings()
        if (active)
            stop()
        persistStatePayload(clearState("stopped", Translation.tr("No capture region selected.")))
    }

    function start(recovery = false) {
        if (!recovery) {
            root.setDesiredRunning(true)
            root.recoveryAttempts = 0
        }
        recoveryTimer.stop()
        if (active)
            return
        if (!backendAvailable) {
            persistStatePayload(clearState("error", Translation.tr("OCR tools are not available yet.")))
            refreshBackendAvailability()
            return
        }
        if (region.length === 0 || !isValidGeometry(region)) {
            if (region.length > 0) {
                region = ""
                regionLabel = ""
                persistSettings()
            }
            persistStatePayload(clearState("error", Translation.tr("Select a screen region first.")))
            return
        }

        stopRequested = false
        restartPending = false
        launchPending = true
        workerActive = false
        persistStatePayload(clearState("loading", Translation.tr("Starting live screen translation…")))
        Quickshell.execDetached(buildBackendLaunchCommand())
        launchTimeoutTimer.restart()
        initialWorkerProbeTimer.restart()
    }

    function stop(preserveRunIntent = false) {
        if (!preserveRunIntent) {
            root.setDesiredRunning(false)
            recoveryTimer.stop()
            stableWorkerTimer.stop()
            root.recoveryAttempts = 0
        }
        stopRequested = true
        launchPending = false
        workerActive = false
        initialWorkerProbeTimer.stop()
        Quickshell.execDetached(buildStopCommand())
        persistStatePayload(clearState("stopped", Translation.tr("Live screen translation stopped.")))
        if (preserveRunIntent && root.restartPending)
            delayedStartTimer.restart()
    }

    function toggleRunning() {
        if (active)
            stop()
        else
            start()
    }

    function restartIfActive() {
        if (!active)
            return
        restartPending = true
        stopRequested = false
        restartTimer.restart()
    }

    function updateWorkerState(isRunning) {
        const wasActive = root.workerActive || root.launchPending
        const wasWorkerActive = root.workerActive
        root.workerActive = isRunning

        if (isRunning) {
            root.launchPending = false
            recoveryTimer.stop()
            if (!wasWorkerActive)
                stableWorkerTimer.restart()
            stateFileView.reload()
            return
        }

        if (!wasActive) {
            root.ensureDesiredWorker()
            return
        }

        const shouldRestart = root.restartPending
        const expectedStop = root.stopRequested || root.restartPending
        root.launchPending = false
        root.workerActive = false

        if (!expectedStop) {
            stateFileView.reload()
        }

        root.stopRequested = false
        root.restartPending = false
        if (shouldRestart)
            delayedStartTimer.restart()
        else if (!expectedStop)
            root.scheduleRecovery()
    }

    Timer {
        id: restartTimer
        interval: 150
        repeat: false
        onTriggered: root.stop(true)
    }

    Timer {
        id: delayedStartTimer
        interval: 150
        repeat: false
        onTriggered: root.start(true)
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
        onTriggered: {
            if (!workerStatusProc.running) {
                workerStatusProc.command = buildWorkerStatusCommand()
                workerStatusProc.running = true
            }
        }
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
            try {
                root.state = JSON.parse(stateFileView.text() || "{}")
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

    Timer {
        id: selectionPollTimer
        interval: 300
        repeat: true
        running: false
        onTriggered: {
            if (!selectionResultProc.running) {
                selectionResultProc.command = ["cat", Directories.liveScreenTranslationSelectionPath]
                selectionResultProc.running = true
            }
        }
    }

    Process {
        id: selectionResultProc
        stdout: StdioCollector {
            onStreamFinished: {
                const selected = String(this.text ?? "").trim()
                if (selected.length === 0)
                    return
                selectionPollTimer.running = false
                root.selectingRegion = false
                if (selected === "__CANCELLED__" || !root.isValidGeometry(selected))
                    return
                root.region = selected
                root.regionLabel = selected
                root.persistSettings()
                if (root.active)
                    root.restartIfActive()
            }
        }
        onExited: (exitCode) => {
            // exitCode != 0 means the file doesn't exist yet — keep polling
        }
    }

    Process {
        id: workerStatusProc
        onExited: (exitCode, exitStatus) => {
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
