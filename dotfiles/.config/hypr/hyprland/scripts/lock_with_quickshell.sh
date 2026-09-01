#!/usr/bin/env sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
QS_BIN="${QS_BIN:-}"
QS_CONFIG="${1:-${QS_CONFIG:-ii}}"
WAIT_FOR_IPC_TENTHS="${WAIT_FOR_IPC_TENTHS:-50}"
LOCK_GUARD_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/quickshell-lock-request"
EVENT_LOG="$SCRIPT_DIR/quickshell_event_log.sh"

"$EVENT_LOG" lock-invoked "config=$QS_CONFIG" "argv=$*" || true

if ! mkdir "$LOCK_GUARD_DIR" 2>/dev/null; then
  "$EVENT_LOG" lock-guard-busy "config=$QS_CONFIG" || true
  exit 0
fi
trap 'rmdir "$LOCK_GUARD_DIR" 2>/dev/null || true' EXIT INT TERM

"$SCRIPT_DIR/ensure_quickshell.sh" "$QS_CONFIG"
"$EVENT_LOG" lock-after-ensure "config=$QS_CONFIG" || true

if [ -z "$QS_BIN" ]; then
  for candidate in "$HOME/.local/bin/qs" "$HOME/.local/bin/quickshell" qs quickshell /usr/bin/qs /usr/bin/quickshell; do
    if command -v "$candidate" >/dev/null 2>&1; then
      QS_BIN="$(command -v "$candidate")"
      break
    fi
  done
fi

if [ -z "$QS_BIN" ]; then
  "$EVENT_LOG" lock-error-no-bin "config=$QS_CONFIG" || true
  echo "Errore: quickshell/qs non trovato nel PATH." >&2
  exit 1
fi

i=0
while [ "$i" -lt "$WAIT_FOR_IPC_TENTHS" ]; do
  if "$QS_BIN" -c "$QS_CONFIG" ipc call lock activate >/dev/null 2>&1; then
    "$EVENT_LOG" lock-ipc-activate-ok "config=$QS_CONFIG" "attempt=$i" "bin=$QS_BIN" || true
    exit 0
  fi
  sleep 0.1
  i=$((i + 1))
done

"$EVENT_LOG" lock-ipc-activate-failed "config=$QS_CONFIG" "attempts=$WAIT_FOR_IPC_TENTHS" "bin=$QS_BIN" || true
if command -v hyprlock >/dev/null 2>&1; then
  "$EVENT_LOG" lock-fallback-hyprlock "config=$QS_CONFIG" || true
  hyprlock >/dev/null 2>&1 &
  exit 0
fi

echo "Error: unable to activate either the Quickshell lock screen or hyprlock." >&2
exit 1
