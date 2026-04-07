#!/usr/bin/env bash
# Usage: cycle_layout.sh [back]

layouts=("dwindle" "master" "scroller")
current=$(hyprctl getoption general:layout -j | jq -r '.str')

for i in "${!layouts[@]}"; do
    if [ "${layouts[$i]}" = "$current" ]; then
        if [ "${1:-}" = "back" ]; then
            next="${layouts[$(( (i - 1 + ${#layouts[@]}) % ${#layouts[@]} ))]}"
        else
            next="${layouts[$(( (i + 1) % ${#layouts[@]} ))]}"
        fi
        hyprctl keyword general:layout "$next"
        notify-send "Layout" "${next^}" -t 1500 -a "Shell"
        exit 0
    fi
done

hyprctl keyword general:layout "${layouts[0]}"
notify-send "Layout" "${layouts[0]^}" -t 1500 -a "Shell"
