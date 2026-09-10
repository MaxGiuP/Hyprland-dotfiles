pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property string runtimeDirectory: Quickshell.env("XDG_RUNTIME_DIR") || ""
    property string sessionSignature: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || ""
    readonly property bool enabled: runtimeDirectory.length > 0 && sessionSignature.length > 0
    property bool ready: false
    property bool restoreRequested: false

    // Keep only the lock state, scoped to this compositor and this boot.
    // A shell crash must not erase it; a new Hyprland session must not inherit it.
    FileView {
        id: stateFile
        path: root.enabled ? `${root.runtimeDirectory}/quickshell-lock-${root.sessionSignature}` : ""
        blockLoading: true
        blockWrites: true
        printErrors: false // A missing file is normal before the first lock.
        onSaveFailed: error => console.warn(`[LockRecovery] Could not save lock state: ${error}`)
    }

    Component.onCompleted: {
        root.restoreRequested = root.enabled && stateFile.text().trim() === "locked";
        root.ready = true;
    }

    function setLocked(locked: bool): void {
        if (!root.enabled)
            return;

        const state = locked ? "locked\n" : "unlocked\n";
        if (stateFile.text() !== state)
            stateFile.setText(state);
    }
}
