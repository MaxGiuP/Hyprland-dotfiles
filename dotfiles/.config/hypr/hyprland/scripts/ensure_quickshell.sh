#!/usr/bin/env sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
QS_CONFIG="${1:-${QS_CONFIG:-ii}}"
SERVICE_NAME="${QS_SERVICE_NAME:-quickshell.service}"
QS_BIN="${QS_BIN:-}"
WAIT_FOR_IPC_TENTHS="${WAIT_FOR_IPC_TENTHS:-30}"
QS_IPC_TIMEOUT="${QS_IPC_TIMEOUT:-0.25}"
EVENT_LOG="$SCRIPT_DIR/quickshell_event_log.sh"
QS_CRASH_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/crashes"

"$EVENT_LOG" ensure-invoked "config=$QS_CONFIG" "service=$SERVICE_NAME" "argv=$*" || true

# Quickshell crash reports contain a full executable snapshot and can be
# hundreds of megabytes each. Keep recent diagnostics without allowing years
# of stale reports to consume the home filesystem.
if [ -d "$QS_CRASH_DIR" ]; then
  find "$QS_CRASH_DIR" -mindepth 1 -maxdepth 1 -type d -mtime +7 -exec rm -rf -- {} +
fi

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
    timeout "$QS_IPC_TIMEOUT" "$QS_BIN" -c "$QS_CONFIG" ipc call lock focus >/dev/null 2>&1
  else
    "$QS_BIN" -c "$QS_CONFIG" ipc call lock focus >/dev/null 2>&1
  fi
}

start_quickshell_service() {
  if command -v systemctl >/dev/null 2>&1 && systemctl --user start "$SERVICE_NAME" >/dev/null 2>&1; then
    "$EVENT_LOG" ensure-systemd-started "config=$QS_CONFIG" "service=$SERVICE_NAME" || true
    return 0
  fi

  "$EVENT_LOG" ensure-systemd-start-failed "config=$QS_CONFIG" "service=$SERVICE_NAME" || true
  return 1
}

start_quickshell_manual() {
  "$EVENT_LOG" ensure-manual-start "config=$QS_CONFIG" "service=$SERVICE_NAME" || true
  setsid -f "$SCRIPT_DIR/start_quickshell.sh" "$QS_CONFIG" >/dev/null 2>&1 &
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

"$SCRIPT_DIR/quickshell_compat_check.sh" "$QS_BIN" "$QS_CONFIG" || exit $?

if ! has_quickshell; then
  start_quickshell_service || start_quickshell_manual
fi

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

start_quickshell_manual

if wait_for_quickshell_ready; then
  exit 0
fi

echo "Errore: quickshell non è pronto dopo l'avvio." >&2
exit 1
