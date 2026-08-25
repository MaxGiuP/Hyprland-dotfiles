#!/usr/bin/env bash
set -euo pipefail

settings_path="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/${qsConfig:-ii}/settings.qml"

if command -v hyprctl >/dev/null 2>&1 && command -v qs >/dev/null 2>&1; then
    settings_pid="$(
        qs list --all 2>/dev/null \
            | awk '
                /^Instance / { pid = "" }
                /Process ID:/ { pid = $3 }
                /Config path: .*\/settings\.qml/ {
                    print pid
                    exit
                }
            ' || true
    )"

    if [[ -n "${settings_pid:-}" ]] && hyprctl --batch "dispatch hl.dsp.focus({ window = \"pid:${settings_pid}\" })" >/dev/null 2>&1; then
        exit 0
    fi
fi

if command -v qs >/dev/null 2>&1; then
    XDG_CURRENT_DESKTOP=gnome qs -p "$settings_path"
elif command -v systemsettings >/dev/null 2>&1; then
    XDG_CURRENT_DESKTOP=gnome systemsettings
elif command -v gnome-control-center >/dev/null 2>&1; then
    XDG_CURRENT_DESKTOP=gnome gnome-control-center
elif command -v better-control >/dev/null 2>&1; then
    XDG_CURRENT_DESKTOP=gnome better-control
fi
