#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/home/linmax/.config/hypr/hyprland/scripts/tv_mode/common.sh
source "${SCRIPT_DIR}/common.sh"

tv_require_command hyprctl jq
tv_action_lock_or_exit "focus"

monitor="$(tv_ensure_monitor)"
app_workspace="special:tv-app"
clients_json="$(tv_clients_json || true)"

app_address=""
if [[ -n "$clients_json" ]]; then
    app_address="$(
        jq -r --arg ws "$app_workspace" '
            [
                .[] |
                select(.mapped != false and .hidden != true) |
                select(.workspace.name == $ws)
            ] |
            sort_by(.focusHistoryID // 999999) |
            .[0].address // empty
        ' <<<"$clients_json"
    )"
fi

if [[ -n "$app_address" ]]; then
    tv_switch_audio_to_tv
    tv_configure_monitor "$monitor"
    tv_show_special_workspace_on_monitor "$app_workspace" "$monitor"
    tv_focus_window_on_monitor "$app_address" "$monitor" true
    tv_set_state "active" "TV app is focused on ${monitor}" "app" "tv-app" "$monitor"
    exit 0
fi

exec "${SCRIPT_DIR}/focus_steam.sh"
