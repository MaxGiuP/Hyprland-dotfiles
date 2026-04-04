#!/usr/bin/env sh
set -eu

# Give Hyprland a moment to restore the Wayland session before re-checking
# Quickshell. Starting only if missing avoids the daemonized restart crash.
sleep 2
"$HOME/.config/hypr/custom/scripts/ensure_quickshell.sh" ii
sleep 0.5
quickshell -c ii ipc call lock focus >/dev/null 2>&1 || true
