#!/usr/bin/env bash

# Focus a numbered workspace and, when it is empty and belongs to another
# monitor, move the pointer to that monitor. This keeps follow_mouse from
# immediately pulling focus back to the previous display.
set -euo pipefail

workspace_id="${1:-}"
[[ "$workspace_id" =~ ^[1-9][0-9]*$ ]] || {
    echo "usage: ${0##*/} <workspace-id>" >&2
    exit 2
}

runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export XDG_RUNTIME_DIR="$runtime_dir"

if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    for instance_dir in "$runtime_dir"/hypr/*; do
        [[ -S "$instance_dir/.socket.sock" ]] || continue
        export HYPRLAND_INSTANCE_SIGNATURE="${instance_dir##*/}"
        break
    done
fi

workspaces="$(hyprctl workspaces -j)"
monitors="$(hyprctl monitors -j)"

target_monitor="$(jq -r --argjson id "$workspace_id" '.[] | select(.id == $id) | .monitor' <<<"$workspaces")"
target_empty="$(jq -r --argjson id "$workspace_id" '.[] | select(.id == $id) | (.windows == 0)' <<<"$workspaces")"
focused_monitor="$(jq -r '.[] | select(.focused) | .name' <<<"$monitors")"

hyprctl dispatch "hl.dsp.focus({ workspace = $workspace_id })" >/dev/null

[[ "$target_empty" == "true" && -n "$target_monitor" && "$target_monitor" != "$focused_monitor" ]] || exit 0

read -r cursor_x cursor_y < <(
    jq -r --arg monitor "$target_monitor" '
        def rotated: . == 1 or . == 3 or . == 5 or . == 7;
        .[]
        | select(.name == $monitor)
        | ((.transform // 0) | rotated) as $rotated
        | (if (.scale // 1) > 0 then .scale else 1 end) as $scale
        | ((if $rotated then .height else .width end) / $scale) as $width
        | ((if $rotated then .width else .height end) / $scale) as $height
        | [(.x + ($width / 2) | floor), (.y + ($height / 2) | floor)]
        | @tsv
    ' <<<"$monitors"
)

[[ -n "${cursor_x:-}" && -n "${cursor_y:-}" ]] || exit 0
hyprctl dispatch "hl.dsp.cursor.move({ x = $cursor_x, y = $cursor_y })" >/dev/null
