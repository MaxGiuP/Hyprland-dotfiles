#!/usr/bin/env bash
# Print the layout-switcher command for the focused workspace.
set -euo pipefail

workspace="$(hyprctl activeworkspace -j)"
workspace_id="$(jq -r '.id' <<<"$workspace")"
active_window="$(hyprctl activewindow -j)"

# Monocle is implemented by the selector as an internal fullscreen state.
if [[ "$(jq -r '.workspace.id == '"$workspace_id"' and .fullscreen == 1 and .fullscreenClient == 1' <<<"$active_window")" == "true" ]]; then
    printf '%s\n' monocle
    exit 0
fi

case "$(jq -r '.tiledLayout // empty' <<<"$workspace")" in
    dwindle)
        case "$(hyprctl getoption dwindle:force_split -j | jq -r '.int')" in
            1) printf '%s\n' dwindle-columns ;;
            2) printf '%s\n' dwindle-rows ;;
            *) printf '%s\n' dwindle ;;
        esac
        ;;
    master)
        case "$(hyprctl getoption master:orientation -j | jq -r '.str')" in
            top) printf '%s\n' master-top ;;
            center) printf '%s\n' master-center ;;
            *) printf '%s\n' master ;;
        esac
        ;;
    scroller|scrolling) printf '%s\n' scroller ;;
esac
