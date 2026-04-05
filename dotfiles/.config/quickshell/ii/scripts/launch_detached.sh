#!/usr/bin/env sh

set -eu

if [ "$#" -eq 0 ]; then
  echo "Usage: $0 <command> [args...]" >&2
  exit 1
fi

if command -v systemd-run >/dev/null 2>&1; then
  exec systemd-run --user --scope --quiet --collect -- "$@"
fi

if command -v setsid >/dev/null 2>&1; then
  exec setsid -f "$@"
fi

"$@" >/dev/null 2>&1 &
