#!/usr/bin/env bash
# Toggle TV mode on the special:tv workspace pinned to HDMI-A-2.
#  - special:tv hosts no Steam window  →  start.sh (boots Big Picture into it).
#  - special:tv hosts Steam, visible on TV monitor →  hide it.
#  - special:tv hosts Steam, hidden →  show it on the TV monitor.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/home/linmax/.config/hypr/hyprland/scripts/tv_mode/common.sh
source "${SCRIPT_DIR}/common.sh"

tv_require_command hyprctl jq

monitor="$(tv_resolve_monitor || true)"
if [[ -z "$monitor" ]]; then
    tv_stop_tv_workspaces_without_monitor
    tv_notify "TV mode" "No TV monitor connected"
    exit 0
fi

special_ws="special:${TV_SPECIAL_WORKSPACE_NAME}"
if ! hyprctl -j clients 2>/dev/null | jq -e --arg ws "$special_ws" '
    .[] | select(.workspace.name == $ws) | select(
        ((.class // "") | test("^(steam|Steam|steamwebhelper|steam_app_.*)$")) or
        ((.title // "") | test("Steam"))
    )' >/dev/null; then
    exec "${SCRIPT_DIR}/start.sh"
fi

if tv_monitor_has_special_visible "$monitor"; then
    tv_hide_special_everywhere
    tv_clear_state
else
    tv_set_state "active" "Steam Big Picture is on ${monitor}" "gamepadui" "steam" "$monitor"
    tv_show_special_on_monitor "$monitor"
fi
