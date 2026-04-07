#!/usr/bin/env sh
# restart_quickshell.sh
# Chiude tutti i processi quickshell e qs, poi avvia una nuova istanza.

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
QS_CONFIG="${1:-${QS_CONFIG:-ii}}"
SERVICE_NAME="${QS_SERVICE_NAME:-quickshell.service}"

if systemctl --user restart "$SERVICE_NAME" >/dev/null 2>&1; then
  echo "Riavviato: $SERVICE_NAME"
  exit 0
fi

pkill -TERM -x quickshell 2>/dev/null || true
pkill -TERM -x qs 2>/dev/null || true
sleep 0.5
pgrep -x quickshell >/dev/null 2>&1 && pkill -KILL -x quickshell || true
pgrep -x qs >/dev/null 2>&1 && pkill -KILL -x qs || true

setsid -f "$SCRIPT_DIR/start_quickshell.sh" "$QS_CONFIG" >/dev/null 2>&1 &

echo "Riavviato: quickshell manuale ($QS_CONFIG)"
