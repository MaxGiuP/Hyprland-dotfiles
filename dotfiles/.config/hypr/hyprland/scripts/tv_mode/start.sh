#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/home/linmax/.config/hypr/hyprland/scripts/tv_mode/common.sh
source "${SCRIPT_DIR}/common.sh"

tv_require_command hyprctl jq steam

mode="${1:-gamepadui}"
monitor="$(tv_ensure_monitor)"

"${SCRIPT_DIR}/launch_steam.sh" "$mode"
tv_prepare_special_workspace "$monitor"
