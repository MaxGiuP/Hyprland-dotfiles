#!/usr/bin/env bash

set -u

# Prefer the largest active XWayland output as primary so X11/XWayland games
# default to the main screen even if Hyprland monitor IDs enumerate differently.

if ! command -v xrandr >/dev/null 2>&1; then
    exit 0
fi

for _ in $(seq 1 30); do
    output="$(xrandr --query 2>/dev/null)" || output=""
    [ -n "$output" ] && break
    sleep 1
done

[ -n "${output:-}" ] || exit 0

primary_output="$(
    printf '%s\n' "$output" | awk '
        $2 == "connected" {
            name = $1
            width = 0
            height = 0

            if (match($0, /[0-9]+x[0-9]+\+[0-9]+\+[0-9]+/)) {
                geom = substr($0, RSTART, RLENGTH)
                split(geom, parts, /[x+]/)
                width = parts[1] + 0
                height = parts[2] + 0
            }

            area = width * height
            if (area > best_area) {
                best_area = area
                best_name = name
            }
        }
        END {
            if (best_name != "") {
                print best_name
            }
        }
    '
)"

[ -n "$primary_output" ] || exit 0

xrandr --output "$primary_output" --primary >/dev/null 2>&1 || true
