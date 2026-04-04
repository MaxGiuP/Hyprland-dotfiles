#!/usr/bin/env sh
set -eu

exec "$HOME/.config/hypr/custom/scripts/lock_with_quickshell.sh" "${1:-ii}"
