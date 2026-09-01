#!/usr/bin/env bash
set -euo pipefail

mode="${1:-mail}"
target="${2:-}"
project_dir="${QUICKMAIL_PROJECT:-$HOME/QuickMail}"

if (( $# > 2 )); then
  printf 'usage: %s [mail [mailto:URI] | accounts | calendar]\n' "${0##*/}" >&2
  exit 2
fi

find_launcher() {
  local candidate
  candidate="$(command -v quickmail 2>/dev/null || true)"
  if [[ -n "$candidate" && -x "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  candidate="$project_dir/packaging/quickmail"
  if [[ -x "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  return 1
}

launch_quickmail() {
  local launcher
  if ! launcher="$(find_launcher)"; then
    if command -v notify-send >/dev/null 2>&1; then
      notify-send --app-name=QuickMail --icon=mail-unread \
        'QuickMail is not installed' \
        'Install QuickMail or set QUICKMAIL_PROJECT to its source checkout.'
    fi
    return 127
  fi
  exec "$launcher" "$@"
}

case "$mode" in
  mail)
    if [[ -n "$target" ]]; then
      if [[ ! "$target" =~ ^[mM][aA][iI][lL][tT][oO]: ]]; then
        printf 'open-quickmail.sh: mail target must be a mailto URI\n' >&2
        exit 2
      fi
      launch_quickmail -- "$target"
    fi
    launch_quickmail
    ;;
  accounts)
    if [[ -n "$target" ]]; then
      printf 'open-quickmail.sh: accounts does not accept a target\n' >&2
      exit 2
    fi
    launch_quickmail --accounts
    ;;
  calendar)
    if [[ -n "$target" ]]; then
      printf 'open-quickmail.sh: calendar does not accept a target\n' >&2
      exit 2
    fi
    exec qs -c ii ipc call quickMail calendar
    ;;
  *)
    printf 'usage: %s [mail [mailto:URI] | accounts | calendar]\n' "${0##*/}" >&2
    exit 2
    ;;
esac
