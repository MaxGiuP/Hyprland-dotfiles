#!/usr/bin/env sh
set -eu

# Give Hyprland a moment to restore the Wayland session before re-checking
# Quickshell. Starting only if missing avoids the daemonized restart crash.
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
sleep 2
"$SCRIPT_DIR/ensure_quickshell.sh" ii
sleep 0.5
quickshell -c ii ipc call lock resumedFromSleep >/dev/null 2>&1 || true
quickshell -c ii ipc call lock focus >/dev/null 2>&1 || true
