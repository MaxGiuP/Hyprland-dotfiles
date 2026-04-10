pragma Singleton

import QtQuick
import qs.modules.common
import qs.modules.common.functions
import Quickshell

Singleton {
    id: root

    readonly property string syncScriptPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/hyprland/scripts/sync_idle_lock.sh`)

    function load() {
        if (Config.ready)
            syncTimer.restart();
    }

    function timeoutMinutes() {
        return Math.max(0, parseInt(Config.options?.lock?.timeout) || 0);
    }

    function apply() {
        if (!Config.ready)
            return;

        Quickshell.execDetached(["bash", root.syncScriptPath, `${root.timeoutMinutes()}`]);
    }

    Timer {
        id: syncTimer
        interval: 150
        repeat: false
        onTriggered: root.apply()
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready)
                syncTimer.restart();
        }
    }

    Connections {
        target: Config.options.lock
        function onTimeoutChanged() {
            syncTimer.restart();
        }
    }
}
