#!/usr/bin/env bash

set -u

target_monitor="DP-1"

if ! command -v hyprctl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    exit 0
fi

for _ in $(seq 1 20); do
    monitors="$(hyprctl -j monitors 2>/dev/null)" || monitors=""
    [ -n "$monitors" ] && break
    sleep 1
done

[ -n "${monitors:-}" ] || exit 0

geometry="$(
    printf '%s\n' "$monitors" | jq -r --arg name "$target_monitor" '
        map(select(.name == $name)) | first |
        if . then "\(.x) \(.y) \(.width) \(.height)" else empty end
    '
)"

[ -n "$geometry" ] || exit 0

read -r mon_x mon_y mon_w mon_h <<<"$geometry"
cursor_x=$((mon_x + (mon_w / 2)))
cursor_y=$((mon_y + (mon_h / 2)))

hyprctl dispatch focusmonitor "$target_monitor" >/dev/null 2>&1 || true
hyprctl dispatch movecursor "$cursor_x" "$cursor_y" >/dev/null 2>&1 || true
