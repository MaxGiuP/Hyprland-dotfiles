#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/home/linmax/.config/hypr/hyprland/scripts/tv_mode/common.sh
source "${SCRIPT_DIR}/common.sh"

selector="${1:?window selector required}"
workspace="${2:-special:tv-app}"
monitor="$(tv_ensure_monitor)"

for _ in $(seq 1 30); do
    if hyprctl dispatch movetoworkspacesilent "${workspace},${selector}" >/dev/null 2>&1; then
        tv_show_special_workspace_on_monitor "$workspace" "$monitor"
        tv_focus_window_on_monitor "${selector#address:}" "$monitor" true
        hyprctl dispatch bringactivetotop >/dev/null 2>&1 || true
        exit 0
    fi
    sleep 0.25
done

exit 0
