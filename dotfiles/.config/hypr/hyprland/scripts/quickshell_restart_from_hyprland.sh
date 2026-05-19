#!/usr/bin/env sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SERVICE_NAME="${QS_SERVICE_NAME:-quickshell.service}"
QS_CONFIG="${1:-${QS_CONFIG:-ii}}"

if command -v dbus-update-activation-environment >/dev/null 2>&1; then
  dbus-update-activation-environment --systemd \
    DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE \
    DBUS_SESSION_BUS_ADDRESS HYPRCURSOR_THEME HYPRCURSOR_SIZE >/dev/null 2>&1 || true
fi

sleep "${QS_HYPRLAND_START_DELAY:-0.1}"
"$SCRIPT_DIR/quickshell_event_log.sh" hyprland-exec-once-ensure "config=$QS_CONFIG" "service=$SERVICE_NAME" || true
QS_SERVICE_NAME="$SERVICE_NAME" "$SCRIPT_DIR/ensure_quickshell.sh" "$QS_CONFIG"
