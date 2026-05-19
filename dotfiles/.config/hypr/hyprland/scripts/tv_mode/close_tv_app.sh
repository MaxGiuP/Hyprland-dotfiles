#!/usr/bin/env bash
# Close the foreground TV app, preferring windows on special:tv-app.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/home/linmax/.config/hypr/hyprland/scripts/tv_mode/common.sh
source "${SCRIPT_DIR}/common.sh"

tv_require_command hyprctl jq

app_workspace="special:tv-app"
clients_json="$(tv_clients_json || true)"
if [[ -z "$clients_json" ]]; then
    exit 0
fi

address="$(
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

if [[ -z "$address" ]]; then
    exit 0
fi

hyprctl dispatch closewindow "address:${address}" >/dev/null 2>&1 || true

for _ in $(seq 1 30); do
    clients_json="$(tv_clients_json || true)"
    if [[ -z "$clients_json" ]]; then
        break
    fi

    if ! jq -e --arg address "$address" '
        .[] |
        select(.mapped != false and .hidden != true) |
        select(.address == $address)
    ' >/dev/null 2>&1 <<<"$clients_json"; then
        break
    fi

    sleep 0.10
done

exec "${SCRIPT_DIR}/focus_tv_target.sh"
