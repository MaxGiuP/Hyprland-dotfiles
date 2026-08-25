#!/usr/bin/env bash
# Apply a layout selected by the Quickshell layout picker.
set -euo pipefail

layout="${1:-}"

leave_monocle() {
    hyprctl dispatch fullscreenstate 0 0 unset >/dev/null || true
}

set_layout() {
    hyprctl eval "hl.config({ general = { layout = \"$1\" } })"
}

case "$layout" in
    dwindle)
        leave_monocle
        hyprctl eval 'hl.config({ general = { layout = "dwindle" }, dwindle = { force_split = 0 } })'
        ;;
    dwindle-columns)
        leave_monocle
        hyprctl eval 'hl.config({ general = { layout = "dwindle" }, dwindle = { force_split = 1 } })'
        ;;
    dwindle-rows)
        leave_monocle
        hyprctl eval 'hl.config({ general = { layout = "dwindle" }, dwindle = { force_split = 2 } })'
        ;;
    master|master-top|master-center)
        leave_monocle
        orientation="left"
        smart_resizing="true"
        [[ "$layout" == "master-top" ]] && orientation="top"
        if [[ "$layout" == "master-center" ]]; then
            orientation="center"
            # Center Master has stacks on both sides, so the mouse-position-based
            # resize edge can make keyboard resizing appear to go the wrong way.
            smart_resizing="false"
        fi
        hyprctl eval "hl.config({ general = { layout = \"master\" }, master = { orientation = \"$orientation\", smart_resizing = $smart_resizing } })"
        ;;
    scroller)
        leave_monocle
        set_layout scroller
        ;;
    monocle)
        # Hyprland has no native monocle layout; fullscreen is its focus-mode equivalent.
        hyprctl dispatch fullscreenstate 1 1 set
        ;;
    *)
        echo "Unknown layout: $layout" >&2
        exit 2
        ;;
esac
