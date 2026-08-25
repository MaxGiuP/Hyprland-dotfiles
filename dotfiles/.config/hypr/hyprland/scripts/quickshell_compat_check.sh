#!/usr/bin/env sh

set -eu

QS_BIN="${1:-quickshell}"
QS_CONFIG="${2:-${QS_CONFIG:-ii}}"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
EVENT_LOG="$SCRIPT_DIR/quickshell_event_log.sh"

if ! command -v "$QS_BIN" >/dev/null 2>&1; then
  exit 0
fi

if "$QS_BIN" --private-check-compat >/dev/null 2>&1; then
  exit 0
fi

compat_output=$("$QS_BIN" --private-check-compat 2>&1 || true)
"$EVENT_LOG" compat-failed "config=$QS_CONFIG" "bin=$QS_BIN" "output=$compat_output" || true

printf '%s\n' "$compat_output" >&2

if command -v notify-send >/dev/null 2>&1 && { [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${DISPLAY:-}" ]; }; then
  notify-send -u critical -a Quickshell \
    "Quickshell needs rebuild" \
    "Qt was updated after Quickshell was built. Rebuild the package before starting the shell again." >/dev/null 2>&1 || true
fi

exit 42
