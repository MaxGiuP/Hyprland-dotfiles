#!/usr/bin/env bash

set -euo pipefail

mode="${1:-focus}"
slot="${2:-}"
dispatch_script="${HOME}/.config/hypr/hyprland/scripts/hypr_dispatch.sh"

if [[ ! "$slot" =~ ^[0-9]+$ ]] || (( slot < 1 || slot > 10 )); then
    echo "usage: $0 focus|move <1-10>" >&2
    exit 2
fi

target="r~${slot}"

hyprctl_json() {
    local output

    for _ in 1 2 3 4 5; do
        output="$(hyprctl "$@" 2>/dev/null || true)"
        if jq -e . >/dev/null 2>&1 <<<"$output"; then
            printf '%s\n' "$output"
            return 0
        fi
        sleep 0.02
    done

    return 1
}

monitor_under_cursor() {
    local cursor_json monitors_json cursor_x cursor_y

    cursor_json="$(hyprctl_json cursorpos -j || true)"
    monitors_json="$(hyprctl_json monitors -j || true)"
    cursor_x="$(jq -r '.x // empty' 2>/dev/null <<<"$cursor_json")"
    cursor_y="$(jq -r '.y // empty' 2>/dev/null <<<"$cursor_json")"

    [[ -n "$cursor_x" && -n "$cursor_y" && -n "$monitors_json" ]] || return 1

    jq -r --argjson cursor_x "$cursor_x" --argjson cursor_y "$cursor_y" '
        def rotated: . == 1 or . == 3 or . == 5 or . == 7;

        [
            .[]
            | select((.disabled // false) == false)
            | ((.transform // 0) | rotated) as $rotated
            | (if (.scale // 1) > 0 then .scale else 1 end) as $scale
            | ((if $rotated then .height else .width end) / $scale) as $width
            | ((if $rotated then .width else .height end) / $scale) as $height
            | select(
                $cursor_x >= .x and $cursor_x < (.x + $width)
                and $cursor_y >= .y and $cursor_y < (.y + $height)
            )
            | .name
        ][0] // empty
    ' <<<"$monitors_json"
}

focus_monitor_under_cursor() {
    local monitor

    monitor="$(monitor_under_cursor || true)"
    [[ -n "$monitor" ]] || return 0
    "$dispatch_script" focusmonitor "$monitor" >/dev/null
}

case "$mode" in
    focus)
        focus_monitor_under_cursor
        exec "$dispatch_script" workspace "$target"
        ;;
    move)
        exec "$dispatch_script" movetoworkspacesilent "$target"
        ;;
    move-follow)
        exec "$dispatch_script" movetoworkspace "$target"
        ;;
    *)
        echo "usage: $0 focus|move|move-follow <1-10>" >&2
        exit 2
        ;;
esac
