pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/*
 * System updates service. Currently only supports Arch.
 */
Singleton {
    id: root
    readonly property bool settingsApp: Quickshell.env("II_SETTINGS_APP") === "1"

    property bool available: true
    property alias checking: checkUpdatesProc.running
    property int count: 0
    property string updateScriptPath: "/home/linmax/.config/hypr/hyprland/scripts/update.sh"
    readonly property int watchIntervalMs: 10 * 1000
    
    readonly property bool updateAdvised: available && count > Config.options.updates.adviseUpdateThreshold
    readonly property bool updateStronglyAdvised: available && count > Config.options.updates.stronglyAdviseUpdateThreshold

    function load() {}
    function refresh() {
        if (root.settingsApp) return;
        if (checkUpdatesProc.running) return;
        print("[Updates] Checking for system updates")
        checkUpdatesProc.running = true;
    }

    Timer {
        interval: root.watchIntervalMs
        repeat: true
        running: !root.settingsApp && Config.ready
        onTriggered: root.refresh()
    }

    Process {
        id: checkAvailabilityProc
        running: !root.settingsApp
        command: ["/bin/bash", "-c", `[ -x "${root.updateScriptPath}" ]`]
        onExited: (exitCode, exitStatus) => {
            root.available = (exitCode === 0);
            root.refresh();
        }
    }

    Process {
        id: checkUpdatesProc
        environment: ({
            HOME: "/home/linmax",
            USER: "linmax",
            LOGNAME: "linmax",
            SHELL: "/bin/bash",
            PATH: "/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/home/linmax/.local/bin",
            XDG_CACHE_HOME: "/home/linmax/.cache",
            XDG_DATA_HOME: "/home/linmax/.local/share",
            XDG_CONFIG_HOME: "/home/linmax/.config"
        })
        command: ["/bin/bash", "-lc", `"${root.updateScriptPath}" --count-only 2>&1 || true`]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = (text || "").trim()
                if (!out.length) return

                const lines = out.split(/\r?\n/).map(s => s.trim()).filter(Boolean)
                for (let i = lines.length - 1; i >= 0; i--) {
                    if (!/^\d+$/.test(lines[i])) continue
                    const n = parseInt(lines[i], 10)
                    if (Number.isFinite(n)) {
                        root.count = n
                        return
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        if (!root.settingsApp)
            root.refresh()
    }
}
