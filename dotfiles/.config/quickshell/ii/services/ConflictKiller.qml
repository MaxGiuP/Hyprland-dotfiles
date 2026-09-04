pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string killDialogQmlPath: FileUtils.trimFileProtocol(Quickshell.shellPath("killDialog.qml"))
    property bool dialogLaunched: false

    function load() {
        // dummy to force init
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (!Config.ready)
                return
            root.dialogLaunched = false
            conflictCheckDelay.restart()
        }
    }

    function showConflictDialog() {
        if (root.dialogLaunched)
            return
        root.dialogLaunched = true
        Quickshell.execDetached(["qs", "-p", root.killDialogQmlPath])
    }

    Timer {
        id: conflictCheckDelay
        interval: 750
        repeat: false
        onTriggered: {
            kdedPresenceProc.running = true
            notificationConflictsProc.running = true
        }
    }

    // kded6 hosts many useful desktop services. Only its StatusNotifierWatcher
    // module can contend with the shell tray, so unload that module rather than
    // terminating the entire daemon (which also used to trigger crash/restart
    // churn in KDE's device-notification module).
    Process {
        id: kdedPresenceProc
        command: ["pidof", "kded6"]
        onExited: exitCode => {
            // Querying org.kde.kded6 directly would D-Bus-activate a daemon that
            // was not otherwise needed. Inspect modules only for an existing one.
            if (exitCode === 0)
                kdedTrayModulesProc.running = true
        }
    }

    Process {
        id: kdedTrayModulesProc
        command: [
            "qdbus6", "org.kde.kded6", "/kded",
            "org.kde.kded6.loadedModules"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const modules = text.trim().split(/\s+/)
                if (modules.includes("statusnotifierwatcher")
                        && Config.options.conflictKiller.autoKillTrays) {
                    Quickshell.execDetached([
                        "qdbus6", "org.kde.kded6", "/kded",
                        "org.kde.kded6.unloadModule", "statusnotifierwatcher"
                    ])
                }
            }
        }
    }

    Process {
        id: notificationConflictsProc
        command: ["pidof", "mako", "dunst", "swaync"]
        onExited: exitCode => {
            if (exitCode !== 0)
                return
            if (Config.options.conflictKiller.autoKillNotificationDaemons)
                Quickshell.execDetached(["killall", "mako", "dunst", "swaync"])
            else
                root.showConflictDialog()
        }
    }
}
