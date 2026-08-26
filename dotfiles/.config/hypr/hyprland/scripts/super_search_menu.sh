#!/usr/bin/env bash

set -euo pipefail

action="${1:-}"
qs_config="${2:-${QS_CONFIG:-ii}}"
qs_path="$HOME/.config/quickshell/$qs_config"
state_dir="${XDG_RUNTIME_DIR:-/tmp}/hyprland-super-search"
state_file="$state_dir/armed"

cursor_position() {
    local pos x y
    pos="$(hyprctl cursorpos 2>/dev/null || true)"
    pos="${pos// /}"
    [[ "$pos" == *,* ]] || return 1
    x="${pos%%,*}"
    y="${pos#*,}"
    [[ "$x" =~ ^-?[0-9]+$ && "$y" =~ ^-?[0-9]+$ ]] || return 1
    printf '%s %s\n' "$x" "$y"
}

cursor_monitor() {
    local position cursor_x cursor_y
    position="$(cursor_position)" || return 1
    read -r cursor_x cursor_y <<< "$position"

    hyprctl monitors -j 2>/dev/null | jq -r \
        --argjson cursor_x "$cursor_x" \
        --argjson cursor_y "$cursor_y" \
        '.[]
         | select($cursor_x >= .x and $cursor_x < (.x + .width)
                  and $cursor_y >= .y and $cursor_y < (.y + .height))
         | .name' \
        | head -n 1
}

cursor_moved_since_press() {
    local start_x start_y current current_x current_y dx dy threshold
    threshold=12
    read -r start_x start_y < "$state_file" || return 1
    current="$(cursor_position)" || return 1
    read -r current_x current_y <<< "$current"
    dx=$((current_x - start_x))
    dy=$((current_y - start_y))
    ((dx < 0)) && dx=$((-dx))
    ((dy < 0)) && dy=$((-dy))
    ((dx > threshold || dy > threshold))
}

case "$action" in
    press)
        mkdir -p "$state_dir"
        cursor_position > "$state_file" || : > "$state_file"
        ;;
    cancel)
        rm -f "$state_file"
        ;;
    release)
        [[ -e "$state_file" ]] || exit 0
        if cursor_moved_since_press; then
            rm -f "$state_file"
            exit 0
        fi
        rm -f "$state_file"

        target_monitor="$(cursor_monitor || true)"
        if [[ -n "$target_monitor" ]] \
            && qs -p "$qs_path" ipc call search toggleOnScreen "$target_monitor" >/dev/null 2>&1; then
            exit 0
        fi

        if qs -p "$qs_path" ipc call search toggle >/dev/null 2>&1; then
            exit 0
        fi

        if pkill fuzzel >/dev/null 2>&1 || pkill rofi >/dev/null 2>&1; then
            exit 0
        fi

        if command -v fuzzel >/dev/null 2>&1; then
            fuzzel >/dev/null 2>&1 &
        elif command -v rofi >/dev/null 2>&1; then
            rofi -show drun -replace -i >/dev/null 2>&1 &
        fi
        ;;
    *)
        echo "usage: $0 press|cancel|release" >&2
        exit 2
        ;;
esac
