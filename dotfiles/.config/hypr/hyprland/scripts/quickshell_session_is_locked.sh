#!/usr/bin/env sh

set -eu

QS_CONFIG="${1:-${QS_CONFIG:-ii}}"
QS_BIN="${QS_BIN:-}"

if pidof hyprlock >/dev/null 2>&1; then
    exit 0
fi

if [ -z "$QS_BIN" ]; then
    for candidate in "$HOME/.local/bin/qs" "$HOME/.local/bin/quickshell" qs quickshell /usr/bin/qs /usr/bin/quickshell; do
        if command -v "$candidate" >/dev/null 2>&1; then
            QS_BIN="$(command -v "$candidate")"
            break
        fi
    done
fi

[ -n "$QS_BIN" ] || exit 1
status="$(timeout 1s "$QS_BIN" -c "$QS_CONFIG" ipc prop get lock locked 2>/dev/null || true)"
[ "$status" = "true" ]
