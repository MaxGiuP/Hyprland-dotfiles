pragma Singleton

import Quickshell

Singleton {
    id: root

    readonly property string dispatchScriptPath: `${Quickshell.env("HOME") || "/home/linmax"}/.config/hypr/hyprland/scripts/hypr_dispatch.sh`

    function dispatch(command) {
        const payload = `${command ?? ""}`.trim();
        if (payload.length === 0)
            return false;

        Quickshell.execDetached([root.dispatchScriptPath, payload]);
        return true;
    }
}
