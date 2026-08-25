#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
EVENT_LOG="$SCRIPT_DIR/quickshell_event_log.sh"

"$EVENT_LOG" dpms-resume-invoked "argv=$*" || true
/home/linmax/.config/hypr/hyprland/scripts/hypr_dispatch.sh dpms on || true
"$SCRIPT_DIR/on-resume.sh" dpms
