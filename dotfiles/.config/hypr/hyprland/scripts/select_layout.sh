#!/usr/bin/env bash
# Apply a layout selected by the Quickshell layout picker.
set -euo pipefail

layout="${1:-}"

case "$layout" in
    dwindle|master|scroller)
        # Leaving Monocle restores the tiled workspace before switching layout.
        hyprctl dispatch fullscreenstate 0 0 unset >/dev/null || true
        # This configuration uses Hyprland's Lua parser, where `keyword` is
        # intentionally unavailable for dynamic config changes.
        hyprctl eval "hl.config({ general = { layout = \"$layout\" } })"
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
