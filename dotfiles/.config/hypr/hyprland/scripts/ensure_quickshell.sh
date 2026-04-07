#!/usr/bin/env sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
QS_CONFIG="${1:-${QS_CONFIG:-ii}}"
SERVICE_NAME="${QS_SERVICE_NAME:-quickshell.service}"

has_quickshell() {
  pgrep -x quickshell >/dev/null 2>&1 || pgrep -x qs >/dev/null 2>&1
}

if systemctl --user is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
  exit 0
fi

if has_quickshell; then
  exit 0
fi

if systemctl --user start "$SERVICE_NAME" >/dev/null 2>&1; then
  exit 0
fi

if has_quickshell; then
  exit 0
fi

setsid -f "$SCRIPT_DIR/start_quickshell.sh" "$QS_CONFIG" >/dev/null 2>&1 &
