#!/usr/bin/env sh

set -eu

if [ "$#" -eq 0 ]; then
  echo "Usage: $0 <command> [args...]" >&2
  exit 1
fi

if command -v systemd-run >/dev/null 2>&1; then
  if systemd-run --user --scope --quiet --collect --slice=app.slice --same-dir -- "$@" >/dev/null 2>&1; then
    exit 0
  fi

  if systemd-run --user --scope --quiet --collect -- "$@" >/dev/null 2>&1; then
    exit 0
  fi
fi

if command -v setsid >/dev/null 2>&1; then
  setsid -f "$@" >/dev/null 2>&1
  exit 0
fi

"$@" >/dev/null 2>&1 &
