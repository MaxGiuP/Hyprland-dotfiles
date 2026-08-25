pragma Singleton

import Quickshell

Singleton {
    id: root

    readonly property string dispatchScriptPath: `${Quickshell.env("HOME") || "/home/linmax"}/.config/hypr/hyprland/scripts/hypr_dispatch.sh`
    readonly property string workspaceFocusScriptPath: `${Quickshell.env("HOME") || "/home/linmax"}/.config/hypr/hyprland/scripts/focus_workspace_with_cursor.sh`

    function dispatch(command) {
        const payload = `${command ?? ""}`.trim();
        if (payload.length === 0)
            return false;

        const workspaceMatch = /^workspace\s+(\d+)$/.exec(payload);
        if (workspaceMatch) {
            Quickshell.execDetached([root.workspaceFocusScriptPath, workspaceMatch[1]]);
            return true;
        }

        Quickshell.execDetached([root.dispatchScriptPath, payload]);
        return true;
    }
}
