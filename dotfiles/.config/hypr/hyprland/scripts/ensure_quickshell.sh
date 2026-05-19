#!/usr/bin/env sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
QS_CONFIG="${1:-${QS_CONFIG:-ii}}"
SERVICE_NAME="${QS_SERVICE_NAME:-quickshell.service}"
QS_BIN="${QS_BIN:-}"
WAIT_FOR_IPC_TENTHS="${WAIT_FOR_IPC_TENTHS:-100}"
EVENT_LOG="$SCRIPT_DIR/quickshell_event_log.sh"

"$EVENT_LOG" ensure-invoked "config=$QS_CONFIG" "service=$SERVICE_NAME" "argv=$*" || true

resolve_qs_bin() {
  if [ -n "$QS_BIN" ]; then
    return 0
  fi

  for candidate in "$HOME/.local/bin/qs" "$HOME/.local/bin/quickshell" qs quickshell /usr/bin/qs /usr/bin/quickshell; do
    if command -v "$candidate" >/dev/null 2>&1; then
      QS_BIN="$(command -v "$candidate")"
      return 0
    fi
  done

  return 1
}

has_quickshell() {
  pgrep -x quickshell >/dev/null 2>&1 || pgrep -x qs >/dev/null 2>&1
}

quickshell_ready() {
  resolve_qs_bin || return 1

  if command -v timeout >/dev/null 2>&1; then
    timeout 1 "$QS_BIN" -c "$QS_CONFIG" ipc call lock focus >/dev/null 2>&1
  else
    "$QS_BIN" -c "$QS_CONFIG" ipc call lock focus >/dev/null 2>&1
  fi
}

wait_for_quickshell_ready() {
  i=0
  while [ "$i" -lt "$WAIT_FOR_IPC_TENTHS" ]; do
    if quickshell_ready; then
      "$EVENT_LOG" ensure-ipc-ready "config=$QS_CONFIG" "service=$SERVICE_NAME" "attempt=$i" "bin=$QS_BIN" || true
      return 0
    fi
    sleep 0.1
    i=$((i + 1))
  done

  "$EVENT_LOG" ensure-ipc-not-ready "config=$QS_CONFIG" "service=$SERVICE_NAME" "attempts=$WAIT_FOR_IPC_TENTHS" "bin=$QS_BIN" || true
  return 1
}

resolve_qs_bin || {
  "$EVENT_LOG" ensure-error-no-bin "config=$QS_CONFIG" "service=$SERVICE_NAME" || true
  echo "Errore: quickshell/qs non trovato nel PATH." >&2
  exit 1
}

if wait_for_quickshell_ready; then
  exit 0
fi

if systemctl --user restart "$SERVICE_NAME" >/dev/null 2>&1; then
  "$EVENT_LOG" ensure-systemd-restarted "config=$QS_CONFIG" "service=$SERVICE_NAME" || true
  if wait_for_quickshell_ready; then
    exit 0
  fi
fi

if has_quickshell; then
  "$EVENT_LOG" ensure-process-present-but-ipc-unready "config=$QS_CONFIG" "service=$SERVICE_NAME" || true
fi

"$EVENT_LOG" ensure-manual-start "config=$QS_CONFIG" "service=$SERVICE_NAME" || true
setsid -f "$SCRIPT_DIR/start_quickshell.sh" "$QS_CONFIG" >/dev/null 2>&1 &

if wait_for_quickshell_ready; then
  exit 0
fi

echo "Errore: quickshell non è pronto dopo l'avvio." >&2
exit 1
