#!/usr/bin/env sh

set -eu

QS_BIN="${QS_BIN:-}"
QS_CONFIG="${1:-${QS_CONFIG:-ii}}"
WAIT_FOR_HYPR_TENTHS="${WAIT_FOR_HYPR_TENTHS:-100}"

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

exec "$QS_BIN" -c "$QS_CONFIG"
