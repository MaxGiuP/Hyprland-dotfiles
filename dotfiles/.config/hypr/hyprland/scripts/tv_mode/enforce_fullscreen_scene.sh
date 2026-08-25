#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/home/linmax/.config/hypr/hyprland/scripts/tv_mode/common.sh
source "${SCRIPT_DIR}/common.sh"

interval="${TV_SCENE_ENFORCE_INTERVAL:-0.75}"
steam_match='^(steam|Steam|steamwebhelper)$'

select_scene_target() {
    local clients_json="$1"
    local special="$2"

    jq -r --arg special "$special" --arg steam_match "$steam_match" '
        def is_steam_ui:
            (((.class // "") | test($steam_match)) or
             ((.initialClass // "") | test($steam_match)) or
             ((.title // "") | test("Steam|Big Picture|Modalità Big Picture")) or
             ((.initialTitle // "") | test("Steam|Big Picture|Modalità Big Picture")));

        def special_clients:
            [.[] | select(.mapped == true) | select(.workspace.name == $special)];

        (special_clients | map(select(is_steam_ui | not)) | sort_by(.focusHistoryID // 999999) | .[0].address // empty) as $app |
        if $app != "" then
            $app
        else
            special_clients | map(select(is_steam_ui)) | sort_by(.focusHistoryID // 999999) | .[0].address // empty
        end
    ' <<<"$clients_json"
}

select_app_target() {
    local clients_json="$1"
    local special="$2"

    jq -r --arg special "$special" --arg steam_match "$steam_match" '
        def is_steam_ui:
            (((.class // "") | test($steam_match)) or
             ((.initialClass // "") | test($steam_match)) or
             ((.title // "") | test("Steam|Big Picture|Modalità Big Picture")) or
             ((.initialTitle // "") | test("Steam|Big Picture|Modalità Big Picture")));

        [.[] | select(.mapped == true) | select(.workspace.name == $special) | select(is_steam_ui | not)]
        | sort_by(.focusHistoryID // 999999)
        | .[0].address // empty
    ' <<<"$clients_json"
}

client_fullscreen_state() {
    local clients_json="$1"
    local address="$2"

    jq -r --arg address "$address" '
        map(select(.address == $address)) | first | .fullscreen // 0
    ' <<<"$clients_json"
}

client_focus_history_id() {
    local clients_json="$1"
    local address="$2"

    jq -r --arg address "$address" '
        map(select(.address == $address)) | first | .focusHistoryID // 999999
    ' <<<"$clients_json"
}

enforce_target() {
    local address="$1"
    local fullscreen="$2"
    local focus_history_id="$3"

    [[ -n "$address" ]] || return 0

    if [[ "$fullscreen" != "0" && "$focus_history_id" == "0" ]]; then
        return 0
    fi

    /home/linmax/.config/hypr/hyprland/scripts/hypr_dispatch.sh focuswindow "address:${address}" >/dev/null 2>&1 || true
    if [[ "$fullscreen" == "0" ]]; then
        /home/linmax/.config/hypr/hyprland/scripts/hypr_dispatch.sh fullscreen 0 >/dev/null 2>&1 || true
    fi
    /home/linmax/.config/hypr/hyprland/scripts/hypr_dispatch.sh focuswindow "address:${address}" >/dev/null 2>&1 || true
    /home/linmax/.config/hypr/hyprland/scripts/hypr_dispatch.sh bringactivetotop >/dev/null 2>&1 || true
}

refresh_steam_ui_after_app_close() {
    local steam_address="$1"

    steam steam://open/games >/dev/null 2>&1 &
    sleep 0.35

    if [[ -n "$steam_address" ]]; then
        /home/linmax/.config/hypr/hyprland/scripts/hypr_dispatch.sh focuswindow "address:${steam_address}" >/dev/null 2>&1 || true
        /home/linmax/.config/hypr/hyprland/scripts/hypr_dispatch.sh bringactivetotop >/dev/null 2>&1 || true
    fi
}

last_app_address=""

while true; do
    special="$(tv_special_selector)"
    visible_monitor="$(tv_special_visible_monitor || true)"

    if [[ -z "$visible_monitor" ]]; then
        sleep "$interval"
        continue
    fi

    clients_json="$(tv_clients_json || true)"

    if [[ -n "$clients_json" ]]; then
        app_address="$(select_app_target "$clients_json" "$special" || true)"
        address="$(select_scene_target "$clients_json" "$special" || true)"

        if [[ -n "$last_app_address" && -z "$app_address" ]]; then
            refresh_steam_ui_after_app_close "$address"
        fi
        last_app_address="$app_address"

        if [[ -n "$address" ]]; then
            fullscreen="$(client_fullscreen_state "$clients_json" "$address" || printf '0')"
            focus_history_id="$(client_focus_history_id "$clients_json" "$address" || printf '999999')"
            enforce_target "$address" "$fullscreen" "$focus_history_id"
        fi
    fi

    sleep "$interval"
done
