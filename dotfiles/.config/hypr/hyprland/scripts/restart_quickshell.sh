#!/usr/bin/env sh
# restart_quickshell.sh
# Chiude tutti i processi quickshell e qs, poi avvia una nuova istanza.

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
QS_CONFIG="${1:-${QS_CONFIG:-ii}}"
SERVICE_NAME="${QS_SERVICE_NAME:-quickshell.service}"
EVENT_LOG="$SCRIPT_DIR/quickshell_event_log.sh"
QS_BIN="${QS_BIN:-}"

# Layer-shell surfaces can temporarily become the keyboard target while
# Quickshell is replaced. Remember the focused client and reassert it once the
# replacement shell has had time to register its panels.
FOCUSED_WINDOW_ADDRESS="$(hyprctl -j activewindow 2>/dev/null | jq -r '.address // empty' 2>/dev/null || true)"

restore_focused_window() {
  [ -n "$FOCUSED_WINDOW_ADDRESS" ] || return 0
  sleep 1
  "$SCRIPT_DIR/hypr_dispatch.sh" focuswindow "address:$FOCUSED_WINDOW_ADDRESS" >/dev/null 2>&1 || true
}

"$EVENT_LOG" restart-invoked "config=$QS_CONFIG" "service=$SERVICE_NAME" "argv=$*" || true

if [ -z "$QS_BIN" ]; then
  for candidate in "$HOME/.local/bin/qs" "$HOME/.local/bin/quickshell" qs quickshell /usr/bin/qs /usr/bin/quickshell; do
    if command -v "$candidate" >/dev/null 2>&1; then
      QS_BIN="$(command -v "$candidate")"
      break
    fi
  done
fi

if [ -n "$QS_BIN" ]; then
  "$SCRIPT_DIR/quickshell_compat_check.sh" "$QS_BIN" "$QS_CONFIG" || exit $?
fi

# Replacing the process that owns ext-session-lock leaves Hyprland securely
# locked with no UI. Never restart Quickshell until its lock has fully released.
LOCK_STATUS=""
if [ -n "$QS_BIN" ]; then
  if command -v timeout >/dev/null 2>&1; then
    LOCK_STATUS="$(timeout 1 "$QS_BIN" -c "$QS_CONFIG" ipc prop get lock locked 2>/dev/null || true)"
  else
    LOCK_STATUS="$("$QS_BIN" -c "$QS_CONFIG" ipc prop get lock locked 2>/dev/null || true)"
  fi
fi

case "$LOCK_STATUS" in
  false) ;;
  true)
    "$EVENT_LOG" restart-blocked-session-lock "config=$QS_CONFIG" "service=$SERVICE_NAME" "status=$LOCK_STATUS" || true
    echo "Errore: impossibile riavviare Quickshell mentre il blocco schermo è attivo." >&2
    exit 1
    ;;
esac

if systemctl --user restart "$SERVICE_NAME" >/dev/null 2>&1 \
    && systemctl --user is-active --quiet "$SERVICE_NAME" \
    && WAIT_FOR_IPC_TENTHS=50 "$SCRIPT_DIR/ensure_quickshell.sh" "$QS_CONFIG"; then
  "$EVENT_LOG" restart-systemd-ok "config=$QS_CONFIG" "service=$SERVICE_NAME" || true
  restore_focused_window &
  echo "Riavviato: $SERVICE_NAME"
  exit 0
fi

"$EVENT_LOG" restart-systemd-failed "config=$QS_CONFIG" "service=$SERVICE_NAME" || true
echo "Errore: impossibile riavviare $SERVICE_NAME." >&2
exit 1
