#!/usr/bin/env sh
set -eu

# Refocus the quickshell lock after resume. Starting only if missing avoids the
# daemonized restart crash.
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
EVENT_LOG="$SCRIPT_DIR/quickshell_event_log.sh"
QS_BIN="${QS_BIN:-}"

if [ -z "$QS_BIN" ]; then
  for candidate in "$HOME/.local/bin/qs" "$HOME/.local/bin/quickshell" qs quickshell /usr/bin/qs /usr/bin/quickshell; do
    if command -v "$candidate" >/dev/null 2>&1; then
      QS_BIN="$(command -v "$candidate")"
      break
    fi
  done
fi

call_lock_ipc() {
  method="$1"
  attempts="$2"
  label="$3"

  if [ -z "$QS_BIN" ]; then
    "$EVENT_LOG" "resume-ipc-$label-no-bin" || true
    return 1
  fi

  i=0
  while [ "$i" -lt "$attempts" ]; do
    if "$QS_BIN" -c ii ipc call lock "$method" >/dev/null 2>&1; then
      "$EVENT_LOG" "resume-ipc-$label-ok" "attempt=$i" "bin=$QS_BIN" || true
      return 0
    fi
    sleep 0.1
    i=$((i + 1))
  done

  "$EVENT_LOG" "resume-ipc-$label-failed" "attempts=$attempts" "bin=$QS_BIN" || true
  return 1
}

"$EVENT_LOG" resume-invoked "argv=$*" || true
sleep 0.1
"$EVENT_LOG" resume-before-ensure || true
"$SCRIPT_DIR/ensure_quickshell.sh" ii
"$EVENT_LOG" resume-after-ensure || true
sleep 1.5
call_lock_ipc focus 15 focus || true
