#!/usr/bin/env sh

set -eu

QS_BIN="${QS_BIN:-}"
QS_CONFIG="${1:-${QS_CONFIG:-ii}}"
WAIT_FOR_HYPR_TENTHS="${WAIT_FOR_HYPR_TENTHS:-100}"
WAIT_FOR_WIREPLUMBER_TENTHS="${WAIT_FOR_WIREPLUMBER_TENTHS:-10}"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
EVENT_LOG="$SCRIPT_DIR/quickshell_event_log.sh"

"$EVENT_LOG" start-invoked "config=$QS_CONFIG" "argv=$*" || true

if [ -z "$QS_BIN" ]; then
  for candidate in "$HOME/.local/bin/qs" "$HOME/.local/bin/quickshell" qs quickshell /usr/bin/qs /usr/bin/quickshell; do
    if command -v "$candidate" >/dev/null 2>&1; then
      QS_BIN="$(command -v "$candidate")"
      break
    fi
  done
fi

if [ -z "$QS_BIN" ]; then
  "$EVENT_LOG" start-error-no-bin "config=$QS_CONFIG" || true
  echo "Errore: quickshell/qs non trovato nel PATH." >&2
  exit 1
fi

"$EVENT_LOG" start-bin-resolved "config=$QS_CONFIG" "bin=$QS_BIN" || true
"$SCRIPT_DIR/quickshell_compat_check.sh" "$QS_BIN" "$QS_CONFIG" || exit $?

wait_for_hypr() {
  i=0
  while [ "$i" -lt "$WAIT_FOR_HYPR_TENTHS" ]; do
    if [ -n "${WAYLAND_DISPLAY:-}" ] && hyprctl version >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
    i=$((i + 1))
  done
  return 1
}

wait_for_hypr || true

# Wait for WirePlumber to register audio nodes in PipeWire.
# Without this, quickshell may connect before ALSA devices are available,
# resulting in an empty audio device list in the sidebar.
wait_for_wireplumber() {
  i=0
  while [ "$i" -lt "$WAIT_FOR_WIREPLUMBER_TENTHS" ]; do
    status="$(wpctl status -n 2>/dev/null || true)"
    if printf '%s\n' "$status" | grep -qE "^[[:space:]│]*[* ]?[[:space:]]*[0-9]+\.[[:space:]]+.+(\[vol:|\[Audio/Sink\])"; then
      return 0
    fi
    sleep 0.1
    i=$((i + 1))
  done
  return 0  # Don't block startup even if WirePlumber isn't ready
}
wait_for_wireplumber

NOTIFICATION_ACTIVATION_QML_ROOT="$HOME/.local/lib/qt6/qml"
NOTIFICATION_ACTIVATION_BUILD="$HOME/.config/quickshell/ii/native/notification-activation/build.sh"
NOTIFICATION_ACTIVATION_MODULE="$NOTIFICATION_ACTIVATION_QML_ROOT/Linmax/NotificationActivation"
NOTIFICATION_ACTIVATION_PLUGIN="$NOTIFICATION_ACTIVATION_MODULE/libnotificationactivationplugin.so"

case "$QS_CONFIG" in
  ii|*/ii)
    if [ -x "$NOTIFICATION_ACTIVATION_BUILD" ]; then
      "$EVENT_LOG" native-notification-activation-build "config=$QS_CONFIG" || true
      if ! "$NOTIFICATION_ACTIVATION_BUILD"; then
        if [ ! -r "$NOTIFICATION_ACTIVATION_PLUGIN" ] \
            || [ ! -r "$NOTIFICATION_ACTIVATION_MODULE/qmldir" ] \
            || ldd "$NOTIFICATION_ACTIVATION_PLUGIN" 2>&1 | grep -q 'not found'; then
          "$EVENT_LOG" native-notification-activation-error "config=$QS_CONFIG" || true
          exit 1
        fi
        echo "Warning: using the last working notification activation plugin." >&2
        "$EVENT_LOG" native-notification-activation-fallback "config=$QS_CONFIG" || true
      fi
    elif [ ! -r "$NOTIFICATION_ACTIVATION_PLUGIN" ] \
        || [ ! -r "$NOTIFICATION_ACTIVATION_MODULE/qmldir" ]; then
      "$EVENT_LOG" native-notification-activation-error "config=$QS_CONFIG" || true
      exit 1
    fi

    # The local wrappers already add this path. Export it here as well when a
    # caller explicitly selects the system Quickshell binary.
    case "$QS_BIN" in
      "$HOME/.local/bin/qs"|"$HOME/.local/bin/quickshell") ;;
      *)
        QML_IMPORT_PATH="$NOTIFICATION_ACTIVATION_QML_ROOT${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
        QML2_IMPORT_PATH="$NOTIFICATION_ACTIVATION_QML_ROOT${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}"
        export QML_IMPORT_PATH QML2_IMPORT_PATH
        ;;
    esac
    ;;
esac

"$EVENT_LOG" start-exec "config=$QS_CONFIG" "bin=$QS_BIN" || true
exec "$QS_BIN" --no-duplicate -c "$QS_CONFIG"
