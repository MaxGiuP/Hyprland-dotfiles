import qs.modules.common
import qs.modules.common.models
import qs.modules.common.functions
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
pragma Singleton
pragma ComponentBehavior: Bound

/**
 * Provides a list of wallpapers and an "apply" action that calls the existing
 * switchwall.sh script. Pretty much a limited file browsing service.
 */
Singleton {
    id: root

    property string thumbgenScriptPath: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/thumbnails/thumbgen-venv.sh`
    property string generateThumbnailsMagickScriptPath: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/thumbnails/generate-thumbnails-magick.sh`
    property alias directory: folderModel.folder
    readonly property string effectiveDirectory: FileUtils.trimFileProtocol(folderModel.folder.toString())
    property url defaultFolder: Qt.resolvedUrl(`${Directories.pictures}/Wallpapers`)
    property alias folderModel: folderModel // Expose for direct binding when needed
    property string searchQuery: ""
    readonly property list<string> extensions: [ // TODO: add videos
        "jpg", "jpeg", "png", "webp", "avif", "bmp", "svg"
    ]
    property list<string> wallpapers: [] // List of absolute file paths (without file://)
    readonly property bool thumbnailGenerationRunning: thumbgenProc.running
    property real thumbnailGenerationProgress: 0
    property string dynamicStatus: "unknown"
    property bool dynamicRunning: false
    property bool dynamicStartupHandled: false
    readonly property string dynamicScriptPath: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/colors/dynamic_wallpaper.py`
    property string pendingSwitchwallPath: ""
    property bool pendingSwitchwallDarkMode: Appearance.m3colors.darkmode
    readonly property bool settingsApp: Quickshell.env("II_SETTINGS_APP") === "1"
    property string pendingApplyPath: ""
    property bool pendingApplyDarkMode: Appearance.m3colors.darkmode
    property string pendingApplyWallpaperMode: "static"
    property string preloadWallpaperPath: ""
    property var preloadReadyScreens: ({})
    property int preloadReadyCount: 0
    property string lastPreloadRequestPath: ""
    readonly property int preloadRequiredCount: Math.max(1, Quickshell.screens.length)

    function dynamicScheduleArgs() {
        return [
            "--schedule-mode", Config.options.background.dynamic.scheduleMode ?? "sun",
            "--morning-time", Config.options.background.dynamic.morningTime ?? "06:00",
            "--day-time", Config.options.background.dynamic.dayTime ?? "10:30",
            "--evening-time", Config.options.background.dynamic.eveningTime ?? "17:30",
            "--night-time", Config.options.background.dynamic.nightTime ?? "21:30"
        ]
    }

    signal changed()
    signal thumbnailGenerated(directory: string)
    signal thumbnailGeneratedFile(filePath: string)

    function load () {} // For forcing initialization

    function openFallbackPicker(darkMode = Appearance.m3colors.darkmode) {
        Quickshell.execDetached([
            Directories.wallpaperSwitchScriptPath,
            "--mode", (darkMode ? "dark" : "light")
        ])
    }

    function runPendingSwitchwall() {
        if (!pendingSwitchwallPath || pendingSwitchwallPath.length === 0)
            return

        Quickshell.execDetached([
            Directories.wallpaperSwitchScriptPath,
            "--image", pendingSwitchwallPath,
            "--mode", (pendingSwitchwallDarkMode ? "dark" : "light"),
            "--animation-settled"
        ])
        pendingSwitchwallPath = ""
    }

    function apply(path, darkMode = Appearance.m3colors.darkmode) {
        if (!path || path.length === 0) return
        if (root.settingsApp) {
            root.applyThroughShell(path, darkMode)
            return
        }
        root.stageApply(path, darkMode)
    }

    function applyThroughShell(path, darkMode = Appearance.m3colors.darkmode) {
        shellApplyProc.running = false
        shellApplyProc.fallbackPath = path
        shellApplyProc.fallbackDarkMode = darkMode
        shellApplyProc.exec([
            "qs", "-c", "ii", "ipc", "call", "wallpapers", "applyDark",
            path,
            darkMode ? "true" : "false"
        ])
    }

    function preload(path) {
        if (!path || path.length === 0 || path === (Config.options.background.wallpaperPath ?? ""))
            return
        if (path === lastPreloadRequestPath && (root.settingsApp || path === preloadWallpaperPath))
            return

        lastPreloadRequestPath = path
        if (root.settingsApp) {
            shellPreloadProc.running = false
            shellPreloadProc.exec(["qs", "-c", "ii", "ipc", "call", "wallpapers", "preload", path])
            return
        }

        root.startPreload(path)
    }

    function startPreload(path) {
        if (!path || path.length === 0 || path === (Config.options.background.wallpaperPath ?? ""))
            return
        if (pendingApplyPath && pendingApplyPath !== path)
            return
        if (preloadWallpaperPath === path && preloadReadyCount >= preloadRequiredCount)
            return

        preloadReadyScreens = ({})
        preloadReadyCount = 0
        preloadWallpaperPath = ""
        preloadWallpaperPath = path
    }

    function stageApply(path, darkMode = Appearance.m3colors.darkmode, wallpaperMode = "static") {
        if (!path || path.length === 0) return
        if (path === (Config.options.background.wallpaperPath ?? "")) {
            root.commitApply(path, darkMode, wallpaperMode)
            return
        }

        pendingApplyPath = path
        pendingApplyDarkMode = darkMode
        pendingApplyWallpaperMode = wallpaperMode
        if (preloadWallpaperPath !== path)
            root.startPreload(path)
        preloadCommitFallbackTimer.restart()
        if (preloadReadyCount >= preloadRequiredCount)
            root.commitPendingApply()
    }

    function markPreloadReady(path, screenName) {
        if (path !== preloadWallpaperPath)
            return

        const key = (screenName && screenName.length > 0) ? screenName : `screen-${preloadReadyCount}`
        if (preloadReadyScreens[key])
            return

        const readyScreens = Object.assign({}, preloadReadyScreens)
        readyScreens[key] = true
        preloadReadyScreens = readyScreens
        preloadReadyCount = Object.keys(readyScreens).length

        if (pendingApplyPath && path === pendingApplyPath && preloadReadyCount >= preloadRequiredCount)
            root.commitPendingApply()
    }

    function commitPendingApply() {
        if (!pendingApplyPath || pendingApplyPath.length === 0)
            return

        const path = pendingApplyPath
        const darkMode = pendingApplyDarkMode
        const wallpaperMode = pendingApplyWallpaperMode
        pendingApplyPath = ""
        preloadCommitFallbackTimer.stop()
        root.commitApply(path, darkMode, wallpaperMode)
        preloadCleanupTimer.restart()
    }

    function commitApply(path, darkMode = Appearance.m3colors.darkmode, wallpaperMode = "static") {
        Config.options.background.wallpaperMode = wallpaperMode === "dynamic" ? "dynamic" : "static"
        Config.options.background.wallpaperPath = path
        Config.options.background.thumbnailPath = path
        pendingSwitchwallPath = path
        pendingSwitchwallDarkMode = darkMode
        deferredSwitchwallTimer.restart()
        root.changed()
    }

    Timer {
        id: deferredSwitchwallTimer
        interval: 6000
        repeat: false
        onTriggered: root.runPendingSwitchwall()
    }

    Timer {
        id: preloadCommitFallbackTimer
        interval: 1400
        repeat: false
        onTriggered: root.commitPendingApply()
    }

    Timer {
        id: preloadCleanupTimer
        interval: 2400
        repeat: false
        onTriggered: {
            if (!root.pendingApplyPath)
                root.preloadWallpaperPath = ""
        }
    }

    Process {
        id: shellApplyProc
        property string fallbackPath: ""
        property bool fallbackDarkMode: Appearance.m3colors.darkmode
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 && fallbackPath.length > 0)
                root.commitApply(fallbackPath, fallbackDarkMode)
            fallbackPath = ""
        }
    }

    Process {
        id: shellPreloadProc
    }

    Process {
        id: selectProc
        property string filePath: ""
        property bool darkMode: Appearance.m3colors.darkmode
        function select(filePath, darkMode = Appearance.m3colors.darkmode) {
            selectProc.filePath = filePath
            selectProc.darkMode = darkMode
            selectProc.exec(["test", "-d", FileUtils.trimFileProtocol(filePath)])
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                setDirectory(selectProc.filePath);
                return;
            }
            root.apply(selectProc.filePath, selectProc.darkMode);
        }
    }

    function select(filePath, darkMode = Appearance.m3colors.darkmode) {
        selectProc.select(filePath, darkMode);
    }

    function randomFromCurrentFolder(darkMode = Appearance.m3colors.darkmode) {
        if (folderModel.count === 0) return;
        const randomIndex = Math.floor(Math.random() * folderModel.count);
        const filePath = folderModel.get(randomIndex, "filePath");
        print("Randomly selected wallpaper:", filePath);
        root.select(filePath, darkMode);
    }

    function setWallpaperMode(mode) {
        const nextMode = mode === "dynamic" ? "dynamic" : "static"
        Config.options.background.wallpaperMode = nextMode
        if (nextMode === "dynamic")
            root.startDynamic()
        else
            root.stopDynamic()
    }

    function startDynamic() {
        Config.options.background.wallpaperMode = "dynamic"
        dynamicStatus = "starting"
        dynamicRunning = true
        Quickshell.execDetached([
            root.dynamicScriptPath,
            "start",
            "--directory", Config.options.background.dynamic.directory,
            "--interval", String(Config.options.background.dynamic.intervalSeconds),
            "--latitude", String(Config.options.background.dynamic.latitude),
            "--longitude", String(Config.options.background.dynamic.longitude),
            Config.options.background.dynamic.autoMode ? "--auto-mode" : "--no-auto-mode",
            Config.options.background.dynamic.preferTime ? "--prefer-time" : "--no-prefer-time"
        ].concat(root.dynamicScheduleArgs()))
        dynamicRefreshDelay.restart()
    }

    function stopDynamic() {
        Config.options.background.wallpaperMode = "static"
        Quickshell.execDetached([root.dynamicScriptPath, "stop"])
        dynamicRefreshDelay.restart()
    }

    function dynamicNext() {
        Quickshell.execDetached([
            root.dynamicScriptPath,
            "next",
            "--directory", Config.options.background.dynamic.directory,
            "--latitude", String(Config.options.background.dynamic.latitude),
            "--longitude", String(Config.options.background.dynamic.longitude),
            Config.options.background.dynamic.autoMode ? "--auto-mode" : "--no-auto-mode",
            Config.options.background.dynamic.preferTime ? "--prefer-time" : "--no-prefer-time"
        ].concat(root.dynamicScheduleArgs()))
        dynamicRefreshDelay.restart()
    }

    function refreshDynamicStatus(recoverIfStopped = false) {
        dynamicStatusProc.running = false
        dynamicStatusProc.recoverIfStopped = recoverIfStopped
        dynamicStatusProc.command = [
            root.dynamicScriptPath,
            "status",
            "--directory", Config.options.background.dynamic.directory,
            "--latitude", String(Config.options.background.dynamic.latitude),
            "--longitude", String(Config.options.background.dynamic.longitude),
            Config.options.background.dynamic.preferTime ? "--prefer-time" : "--no-prefer-time"
        ].concat(root.dynamicScheduleArgs())
        dynamicStatusProc.running = true
    }

    Timer {
        id: dynamicRefreshDelay
        interval: 900
        repeat: false
        onTriggered: root.refreshDynamicStatus()
    }

    function restoreDynamicMode() {
        if (root.dynamicStartupHandled || !Config.ready)
            return

        root.dynamicStartupHandled = true
        dynamicStartupTimer.stop()
        if (!root.settingsApp && (Config.options.background.wallpaperMode ?? "static") === "dynamic")
            root.refreshDynamicStatus(true)
        else
            root.refreshDynamicStatus()
    }

    Timer {
        id: dynamicStartupTimer
        interval: 250
        repeat: true
        running: true
        onTriggered: root.restoreDynamicMode()
    }

    Timer {
        interval: 60000
        repeat: true
        running: Config.ready
            && !root.settingsApp
            && (Config.options.background.wallpaperMode ?? "static") === "dynamic"
        onTriggered: root.refreshDynamicStatus(true)
    }

    Process {
        id: dynamicStatusProc
        property bool recoverIfStopped: false
        stdout: StdioCollector {
            onStreamFinished: {
                const first = text.split("\n")[0] ?? ""
                root.dynamicStatus = first.trim()
                root.dynamicRunning = root.dynamicStatus.startsWith("running")
                const shouldRecover = dynamicStatusProc.recoverIfStopped
                    && !root.dynamicRunning
                    && Config.ready
                    && !root.settingsApp
                    && (Config.options.background.wallpaperMode ?? "static") === "dynamic"
                dynamicStatusProc.recoverIfStopped = false
                if (shouldRecover)
                    root.startDynamic()
            }
        }
    }

    Component.onCompleted: root.restoreDynamicMode()

    Process {
        id: validateDirProc
        property string nicePath: ""
        function setDirectoryIfValid(path) {
            validateDirProc.nicePath = FileUtils.trimFileProtocol(path).replace(/\/+$/, "")
            if (/^\/*$/.test(validateDirProc.nicePath)) validateDirProc.nicePath = "/";
            validateDirProc.exec([
                "bash", "-c",
                `if [ -d "${validateDirProc.nicePath}" ]; then echo dir; elif [ -f "${validateDirProc.nicePath}" ]; then echo file; else echo invalid; fi`
            ])
        }
        stdout: StdioCollector {
            onStreamFinished: {
                    root.directory = Qt.resolvedUrl(validateDirProc.nicePath)
                const result = text.trim()
                if (result === "dir") {
                } else if (result === "file") {
                    root.directory = Qt.resolvedUrl(FileUtils.parentDirectory(validateDirProc.nicePath))
                } else {
                    // Ignore
                }
            }
        }
    }
    function setDirectory(path) {
        validateDirProc.setDirectoryIfValid(path)
    }
    function navigateUp() {
        folderModel.navigateUp()
    }
    function navigateBack() {
        folderModel.navigateBack()
    }
    function navigateForward() {
        folderModel.navigateForward()
    }

    // Folder model
    FolderListModelWithHistory {
        id: folderModel
        folder: Qt.resolvedUrl(root.defaultFolder)
        caseSensitive: false
        nameFilters: root.extensions.map(ext => `*${searchQuery.split(" ").filter(s => s.length > 0).map(s => `*${s}*`)}*.${ext}`)
        showDirs: true
        showDotAndDotDot: false
        showOnlyReadable: true
        sortField: FolderListModel.Time
        sortReversed: false
        onCountChanged: {
            root.wallpapers = []
            for (let i = 0; i < folderModel.count; i++) {
                const path = folderModel.get(i, "filePath") || FileUtils.trimFileProtocol(folderModel.get(i, "fileURL"))
                if (path && path.length) root.wallpapers.push(path)
            }
        }
    }

    // Thumbnail generation
    function generateThumbnail(size: string) {
        if (!["normal", "large", "x-large", "xx-large"].includes(size)) throw new Error("Invalid thumbnail size");
        thumbgenProc.directory = root.directory
        thumbgenProc.running = false
        thumbgenProc.command = [
            "bash", "-c",
            `${thumbgenScriptPath} --size ${size} --machine_progress -d ${FileUtils.trimFileProtocol(root.directory)} || ${generateThumbnailsMagickScriptPath} --size ${size} -d ${FileUtils.trimFileProtocol(root.directory)}`,
        ]
        // console.log("[Wallpapers] Updating thumbnails with command ", thumbgenProc.command.join(" "))
        root.thumbnailGenerationProgress = 0
        thumbgenProc.running = true
    }
    Process {
        id: thumbgenProc
        property string directory
        stdout: SplitParser {
            onRead: data => {
                // print("thumb gen proc:", data)
                let match = data.match(/PROGRESS (\d+)\/(\d+)/)
                if (match) {
                    const completed = parseInt(match[1])
                    const total = parseInt(match[2])
                    root.thumbnailGenerationProgress = completed / total
                }
                match = data.match(/FILE (.+)/)
                if (match) {
                    const filePath = match[1]
                    root.thumbnailGeneratedFile(filePath)
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            // print("[Wallpapers] Thumbnail generation completed with exit code", exitCode)
            root.thumbnailGenerated(thumbgenProc.directory)
        }
    }

    IpcHandler {
        target: "wallpapers"

        function apply(path: string): void {
            root.apply(path);
        }

        function applyDark(path: string, darkMode: string): void {
            root.stageApply(path, darkMode === "true" || darkMode === "1");
        }

        function applyDynamic(path: string, darkMode: string): void {
            root.stageApply(path, darkMode === "true" || darkMode === "1", "dynamic");
        }

        function preload(path: string): void {
            root.startPreload(path);
        }
    }
}
