#!/usr/bin/env bash
set -u

mode="${1:-mail}"
target="${2:-}"
project_dir="${LIGHTBIRD_MAIL_PROJECT:-$HOME/lightbird-mail}"

if command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  running_address=$(hyprctl clients -j 2>/dev/null \
    | jq -r '.[] | select((.title // "") | startswith("Lightbird Mail")) | .address' \
    | head -n 1)
  if [ -n "$running_address" ]; then
    hyprctl dispatch "hl.dsp.focus({ window = \"address:$running_address\" })" >/dev/null 2>&1 || true
    exit 0
  fi
fi

launch_binary() {
  local binary="$1"
  if [ -n "$target" ]; then
    exec "$binary" "$target"
  fi
  exec "$binary"
}

if command -v lightbird-mail >/dev/null 2>&1; then
  launch_binary "$(command -v lightbird-mail)"
fi

for binary in \
  "$project_dir/target/release/lightbird-mail" \
  "$project_dir/target/debug/lightbird-mail"; do
  if [ -x "$binary" ]; then
    launch_binary "$binary"
  fi
done

if [ -x "$project_dir/packaging/lightbird-mail" ]; then
  exec "$project_dir/packaging/lightbird-mail"
fi

for entry in "$project_dir/qml/main.qml" "$project_dir/qml/shell.qml"; do
  if [ -f "$entry" ]; then
    exec qs -p "$entry"
  fi
done

if command -v notify-send >/dev/null 2>&1; then
  notify-send \
    --app-name="Lightbird Mail" \
    --icon=mail-unread \
    "Lightbird Mail is still being built" \
    "The dashboard bridge is ready and will connect automatically when the client and daemon are installed. Requested view: $mode."
fi

exit 1
