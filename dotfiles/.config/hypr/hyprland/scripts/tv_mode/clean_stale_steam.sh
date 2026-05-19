#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/home/linmax/.config/hypr/hyprland/scripts/tv_mode/common.sh
source "${SCRIPT_DIR}/common.sh"

tv_require_command pkill pgrep steam
tv_action_lock_or_exit "Steam cleanup"

steam_process_regex='(/Steam/steam\.sh|/Steam/ubuntu12_32/steam|steamwebhelper|steam-runtime-launcher-service|steam-runtime-l)'

tv_any_steam_process_running() {
    pgrep -af "$steam_process_regex" >/dev/null 2>&1
}

tv_wait_for_steam_process_exit() {
    for _ in $(seq 1 150); do
        if ! tv_any_steam_process_running; then
            return 0
        fi

        sleep 0.10
    done

    return 1
}

tv_steam_env() {
    env \
        -u QT_QPA_PLATFORM \
        -u QT_QPA_PLATFORMTHEME \
        LANG=C.UTF-8 \
        LC_ALL=C.UTF-8 \
        LC_CTYPE=C.UTF-8 \
        steam "$@"
}

tv_notify "TV mode" "Cleaning stale Steam TV state, then relaunching Big Picture on the TV workspace."
tv_set_state "cleaning" "Cleaning stale Steam TV state" "gamepadui" "steam" ""

if tv_any_steam_process_running; then
    tv_steam_env -shutdown >/dev/null 2>&1 || true
    tv_wait_for_steam_process_exit || true
fi

if tv_any_steam_process_running; then
    pkill -TERM -f "$steam_process_regex" >/dev/null 2>&1 || true
    tv_wait_for_steam_process_exit || true
fi

if tv_any_steam_process_running; then
    pkill -KILL -f "$steam_process_regex" >/dev/null 2>&1 || true
    tv_wait_for_steam_process_exit || true
fi

python3 "${SCRIPT_DIR}/configure_steam_tv_input.py" >/dev/null 2>&1 || true
tv_clear_state
tv_notify "TV mode" "Stale Steam TV state cleaned. Relaunching Big Picture on the TV."
exec "${SCRIPT_DIR}/launch_steam.sh" gamepadui
