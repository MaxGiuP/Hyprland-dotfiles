#!/usr/bin/env bash
set -euo pipefail

# Rebuild the desktop palette from the currently configured wallpaper without
# opening the wallpaper picker or changing the image.
#
# This updates matugen outputs, Quickshell Material colors, terminal colors,
# Qt/KDE/Kvantum colors, browser/editor accents, Hyprland borders/background,
# hyprlock colors, and GTK user CSS when enabled in config.json.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/switchwall.sh" --noswitch "$@"
