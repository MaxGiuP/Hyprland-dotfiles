#!/usr/bin/env sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SERVICE_NAME="${QS_SERVICE_NAME:-quickshell.service}"
QS_CONFIG="${1:-${QS_CONFIG:-ii}}"
EVENT_LOG="$SCRIPT_DIR/quickshell_event_log.sh"

if command -v dbus-update-activation-environment >/dev/null 2>&1; then
  dbus-update-activation-environment --systemd \
    DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE \
    DBUS_SESSION_BUS_ADDRESS HYPRCURSOR_THEME HYPRCURSOR_SIZE >/dev/null 2>&1 || true
fi

sleep "${QS_HYPRLAND_START_DELAY:-0.1}"
"$EVENT_LOG" hyprland-exec-once-start "config=$QS_CONFIG" "service=$SERVICE_NAME" || true

if command -v systemctl >/dev/null 2>&1 \
    && systemctl --user start "$SERVICE_NAME" >/dev/null 2>&1 \
    && systemctl --user is-active --quiet "$SERVICE_NAME"; then
  "$EVENT_LOG" hyprland-systemd-started "config=$QS_CONFIG" "service=$SERVICE_NAME" || true
else
  "$EVENT_LOG" hyprland-systemd-start-failed "config=$QS_CONFIG" "service=$SERVICE_NAME" || true
  exit 1
fi

if command -v systemctl >/dev/null 2>&1; then
  (systemctl --user restart hypridle.service >/dev/null 2>&1 || true) &
fi

(
  sleep "${QS_STARTUP_ENSURE_DELAY:-0.5}"
  WAIT_FOR_IPC_TENTHS="${QS_STARTUP_ENSURE_TENTHS:-60}" \
    QS_SERVICE_NAME="$SERVICE_NAME" \
    "$SCRIPT_DIR/ensure_quickshell.sh" "$QS_CONFIG"
) >/dev/null 2>&1 &
