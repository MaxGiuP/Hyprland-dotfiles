#!/usr/bin/env sh

set -eu

QS_CONFIG="${1:-${QS_CONFIG:-ii}}"
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
LOCK_STATUS_CMD="${LOCK_STATUS_CMD:-$SCRIPT_DIR/quickshell_session_is_locked.sh}"
QS_BIN="${QS_BIN:-}"

# Display power-off and suspend are only safe after a real session lock.
"$LOCK_STATUS_CMD" "$QS_CONFIG" || exit 1

if [ -z "$QS_BIN" ]; then
    for candidate in "$HOME/.local/bin/qs" "$HOME/.local/bin/quickshell" qs quickshell /usr/bin/qs /usr/bin/quickshell; do
        if command -v "$candidate" >/dev/null 2>&1; then
            QS_BIN="$(command -v "$candidate")"
            break
        fi
    done
fi

# Once the lock is confirmed, fail open if Quickshell is unavailable so a
# broken shell cannot hold the machine awake forever.
[ -n "$QS_BIN" ] || exit 0
inhibited="$(timeout 1s "$QS_BIN" -c "$QS_CONFIG" ipc prop get lock idleInhibited 2>/dev/null || true)"
[ "$inhibited" != "true" ]
