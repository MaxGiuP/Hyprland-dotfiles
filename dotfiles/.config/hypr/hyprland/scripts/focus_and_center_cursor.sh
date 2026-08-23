#!/usr/bin/env bash

set -euo pipefail

direction="${1:-}"
case "$direction" in
    l|r|u|d) ;;
    *)
        echo "Usage: ${0##*/} <l|r|u|d>" >&2
        exit 2
        ;;
esac

dispatch_lua() {
    local expression="$1"
    local output

    for _ in 1 2 3 4 5; do
        if output="$(hyprctl dispatch "$expression" 2>&1)"; then
            return 0
        fi
        if [[ "$output" != *"Couldn't set socket timeout"* ]]; then
            printf '%s\n' "$output" >&2
            return 1
        fi
        sleep 0.02
    done

    printf '%s\n' "$output" >&2
    return 1
}

get_active_window() {
    local output

    for _ in 1 2 3 4 5; do
        if output="$(hyprctl activewindow -j 2>/dev/null)" \
            && jq -e 'type == "object"' >/dev/null 2>&1 <<<"$output"; then
            printf '%s\n' "$output"
            return 0
        fi
        sleep 0.02
    done

    return 1
}

# Move focus first, then read Hyprland's resulting active window. Keeping both
# operations in one process prevents follow_mouse from selecting a window under
# the old cursor position between the focus change and the cursor warp.
dispatch_lua "hl.dsp.focus({ direction = \"$direction\" })"

active_window="$(get_active_window)" || exit 0
read -r center_x center_y < <(
    jq -r '
        if (.at | type) == "array" and (.size | type) == "array"
            and (.at | length) >= 2 and (.size | length) >= 2
        then [
            ((.at[0] + (.size[0] / 2)) | floor),
            ((.at[1] + (.size[1] / 2)) | floor)
        ] | @tsv
        else empty
        end
    ' <<<"$active_window"
)

if [[ -n "${center_x:-}" && -n "${center_y:-}" ]]; then
    dispatch_lua "hl.dsp.cursor.move({ x = $center_x, y = $center_y })"
fi
