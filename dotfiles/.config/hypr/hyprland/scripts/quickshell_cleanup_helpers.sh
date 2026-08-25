#!/usr/bin/env sh

# Clean up Quickshell-owned helper processes that should not outlive the shell.
# GUI apps are intentionally excluded; they are launched into separate scopes.

set -u

is_quickshell_unit_pid() {
  pid="$1"
  [ -r "/proc/$pid/cgroup" ] || return 1
  grep -q 'quickshell.service' "/proc/$pid/cgroup" 2>/dev/null
}

process_cmdline() {
  pid="$1"
  [ -r "/proc/$pid/cmdline" ] || return 1
  tr '\000' ' ' <"/proc/$pid/cmdline" 2>/dev/null
}

for pid in $(pgrep -x nmcli 2>/dev/null || true); do
  is_quickshell_unit_pid "$pid" || continue
  cmdline="$(process_cmdline "$pid" || true)"

  case "$cmdline" in
    *"/nmcli monitor "*|nmcli\ monitor\ *)
      kill -TERM "$pid" 2>/dev/null || true
      ;;
  esac
done

exit 0
