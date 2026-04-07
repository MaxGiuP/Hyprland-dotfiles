#!/usr/bin/env sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
QS_BIN="${QS_BIN:-}"
QS_CONFIG="${1:-${QS_CONFIG:-ii}}"
WAIT_FOR_IPC_TENTHS="${WAIT_FOR_IPC_TENTHS:-50}"
LOCK_GUARD_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/quickshell-lock-request"

if ! mkdir "$LOCK_GUARD_DIR" 2>/dev/null; then
  exit 0
fi
trap 'rmdir "$LOCK_GUARD_DIR" 2>/dev/null || true' EXIT INT TERM

"$SCRIPT_DIR/ensure_quickshell.sh" "$QS_CONFIG"

if [ -z "$QS_BIN" ]; then
  for candidate in "$HOME/.local/bin/qs" "$HOME/.local/bin/quickshell" qs quickshell /usr/bin/qs /usr/bin/quickshell; do
    if command -v "$candidate" >/dev/null 2>&1; then
      QS_BIN="$(command -v "$candidate")"
      break
    fi
  done
fi

if [ -z "$QS_BIN" ]; then
  echo "Errore: quickshell/qs non trovato nel PATH." >&2
  exit 1
fi

i=0
while [ "$i" -lt "$WAIT_FOR_IPC_TENTHS" ]; do
  if "$QS_BIN" -c "$QS_CONFIG" ipc call lock activate >/dev/null 2>&1; then
    exit 0
  fi
  sleep 0.1
  i=$((i + 1))
done

echo "Errore: impossibile attivare il lockscreen Quickshell." >&2
exit 1
