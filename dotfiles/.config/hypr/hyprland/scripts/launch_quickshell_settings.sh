#!/usr/bin/env bash
set -euo pipefail

settings_path="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/${qsConfig:-ii}/settings.qml"
settings_path="$(realpath -m -- "$settings_path")"
requested_page="${1:-}"
requested_subtab="${2:--1}"
requested_section="${3:-}"

if [[ ! "$requested_subtab" =~ ^-?[0-9]+$ ]]; then
    requested_subtab=-1
fi

if command -v qs >/dev/null 2>&1; then
    settings_pid="$(
        qs list --all 2>/dev/null \
            | awk -v wanted="$settings_path" '
                /^Instance / { pid = "" }
                /Process ID:/ { pid = $3 }
                /Config path:/ {
                    path = $0
                    sub(/^[[:space:]]*Config path:[[:space:]]*/, "", path)
                    if (path == wanted) {
                        print pid
                        exit
                    }
                }
            ' || true
    )"

    if [[ -n "${settings_pid:-}" ]]; then
        route_sent=0
        if [[ -n "$requested_page" ]] \
            && qs ipc --pid "$settings_pid" call settingsApp navigate \
                "$requested_page" "$requested_subtab" "$requested_section" >/dev/null 2>&1; then
            route_sent=1
        fi

        focused=0
        if command -v hyprctl >/dev/null 2>&1 \
            && hyprctl --batch "dispatch hl.dsp.focus({ window = \"pid:${settings_pid}\" })" >/dev/null 2>&1; then
            focused=1
        fi

        if (( route_sent || focused )); then
            exit 0
        fi
    fi
fi

if command -v qs >/dev/null 2>&1; then
    II_SETTINGS_PAGE="$requested_page" \
    II_SETTINGS_SUBTAB="$requested_subtab" \
    II_SETTINGS_SECTION="$requested_section" \
    XDG_CURRENT_DESKTOP=gnome \
        qs -n -d -p "$settings_path"
fi
