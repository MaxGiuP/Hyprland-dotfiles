#!/usr/bin/env bash

set -euo pipefail

mode="${1:-focus}"
slot="${2:-}"
dispatch_script="${HOME}/.config/hypr/hyprland/scripts/hypr_dispatch.sh"

if [[ ! "$slot" =~ ^[0-9]+$ ]] || (( slot < 1 || slot > 10 )); then
    echo "usage: $0 focus|move <1-10>" >&2
    exit 2
fi

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

workspace_under_cursor() {
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
            | .activeWorkspace.id
        ][0] // empty
    ' <<<"$monitors_json"
}

active_window_workspace() {
    local window_json

    window_json="$(hyprctl_json activewindow -j || true)"
    jq -r '.workspace.id // empty' 2>/dev/null <<<"$window_json"
}

active_workspace() {
    local workspace_json

    workspace_json="$(hyprctl_json activeworkspace -j || true)"
    jq -r '.id // empty' 2>/dev/null <<<"$workspace_json"
}

case "$mode" in
    focus)
        workspace_id="$(workspace_under_cursor || true)"
        ;;
    move|move-follow)
        workspace_id="$(active_window_workspace || true)"
        ;;
    *)
        echo "usage: $0 focus|move|move-follow <1-10>" >&2
        exit 2
        ;;
esac

if [[ ! "$workspace_id" =~ ^[0-9]+$ ]] || (( workspace_id < 1 )); then
    workspace_id="$(active_workspace || true)"
fi

if [[ ! "$workspace_id" =~ ^[0-9]+$ ]] || (( workspace_id < 1 )); then
    echo "could not determine the current workspace" >&2
    exit 1
fi

workspace_base=$(( ((workspace_id - 1) / 10) * 10 ))
target=$(( workspace_base + slot ))

case "$mode" in
    focus)
        exec "$dispatch_script" workspace "$target"
        ;;
    move)
        exec "$dispatch_script" movetoworkspacesilent "$target"
        ;;
    move-follow)
        exec "$dispatch_script" movetoworkspace "$target"
        ;;
esac
