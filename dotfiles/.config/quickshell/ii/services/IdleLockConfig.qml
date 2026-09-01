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

    function lockTimeoutMinutes() {
        return Math.max(1, Math.min(240, parseInt(Config.options?.lock?.timeout) || 10));
    }

    function suspendTimeoutMinutes() {
        const configured = parseInt(Config.options?.lock?.suspendTimeout) || 45;
        return Math.max(root.lockTimeoutMinutes() + 5, Math.min(480, configured));
    }

    function setLockTimeout(minutes) {
        const nextLock = Math.max(1, Math.min(240, parseInt(minutes) || 1));
        Config.options.lock.timeout = nextLock;
        if (parseInt(Config.options.lock.suspendTimeout) < nextLock + 5)
            Config.options.lock.suspendTimeout = Math.min(480, nextLock + 5);
    }

    function setSuspendTimeout(minutes) {
        Config.options.lock.suspendTimeout = Math.max(
            root.lockTimeoutMinutes() + 5,
            Math.min(480, parseInt(minutes) || 45)
        );
    }

    function apply() {
        if (!Config.ready)
            return;

        Quickshell.execDetached([
            "bash",
            root.syncScriptPath,
            `${root.lockTimeoutMinutes()}`,
            `${root.suspendTimeoutMinutes()}`
        ]);
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
        function onSuspendTimeoutChanged() {
            syncTimer.restart();
        }
    }
}
