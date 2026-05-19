#!/usr/bin/env sh

# Lightweight trace logger for Quickshell start/restart/resume paths.
# Keep this POSIX-sh compatible because it is called from systemd and Hyprland.

set -u

LOG_DIR="${QS_DEBUG_LOG_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/quickshell-debug}"
LOG_FILE="${QS_DEBUG_LOG_FILE:-$LOG_DIR/restart-trace.log}"
MAX_BYTES="${QS_DEBUG_LOG_MAX_BYTES:-1048576}"

mkdir -p "$LOG_DIR" 2>/dev/null || exit 0

if [ -f "$LOG_FILE" ]; then
  size="$(wc -c <"$LOG_FILE" 2>/dev/null || printf '0')"
  case "$size" in
    *[!0-9]*|"") size=0 ;;
  esac
  if [ "$size" -gt "$MAX_BYTES" ]; then
    mv "$LOG_FILE" "$LOG_FILE.1" 2>/dev/null || true
  fi
fi

event="${1:-unknown}"
if [ "$#" -gt 0 ]; then
  shift
fi

trim_lines() {
  while IFS= read -r line; do
    if [ "${#line}" -gt 260 ]; then
      printf '%s...\n' "$(printf '%s' "$line" | cut -c 1-260)"
    else
      printf '%s\n' "$line"
    fi
  done
}

{
  printf '%s\n' "===== $(date '+%Y-%m-%dT%H:%M:%S%z') event=$event ====="
  printf 'args=%s\n' "$*"
  printf 'pid=%s ppid=%s uid=%s user=%s pwd=%s\n' "$$" "${PPID:-}" "$(id -u 2>/dev/null || printf '?')" "$(id -un 2>/dev/null || printf '?')" "$(pwd 2>/dev/null || printf '?')"
  printf 'env QS_CONFIG=%s QS_BIN=%s QS_SERVICE_NAME=%s WAYLAND_DISPLAY=%s HYPRLAND_INSTANCE_SIGNATURE=%s XDG_CURRENT_DESKTOP=%s\n' \
    "${QS_CONFIG:-}" "${QS_BIN:-}" "${QS_SERVICE_NAME:-}" "${WAYLAND_DISPLAY:-}" "${HYPRLAND_INSTANCE_SIGNATURE:-}" "${XDG_CURRENT_DESKTOP:-}"
  printf 'systemd SERVICE_RESULT=%s EXIT_CODE=%s EXIT_STATUS=%s INVOCATION_ID=%s MAINPID=%s\n' \
    "${SERVICE_RESULT:-}" "${EXIT_CODE:-}" "${EXIT_STATUS:-}" "${INVOCATION_ID:-}" "${MAINPID:-}"

  if command -v ps >/dev/null 2>&1; then
    printf '%s\n' '-- caller process --'
    ps -o pid,ppid,etimes,stat,comm,args -p "$$" -p "${PPID:-0}" 2>/dev/null | trim_lines || true
  fi

  if command -v pgrep >/dev/null 2>&1 && command -v ps >/dev/null 2>&1; then
    printf '%s\n' '-- quickshell processes --'
    qs_pids="$(pgrep -x quickshell 2>/dev/null || true)"
    qs_alias_pids="$(pgrep -x qs 2>/dev/null || true)"
    if [ -n "$qs_pids$qs_alias_pids" ]; then
      for proc_pid in $qs_pids $qs_alias_pids; do
        ps -o pid,ppid,etimes,stat,comm,args -p "$proc_pid" 2>/dev/null | trim_lines || true
      done
    else
      printf '%s\n' '(none)'
    fi
  fi

  if command -v systemctl >/dev/null 2>&1; then
    printf '%s\n' '-- quickshell.service --'
    systemctl --user show quickshell.service \
      -p ActiveState -p SubState -p Result -p NRestarts -p ExecMainPID \
      -p ExecMainStatus -p ExecMainCode -p ExecMainStartTimestamp \
      -p ExecMainExitTimestamp -p InvocationID 2>/dev/null || true
  fi

  printf '\n'
} >>"$LOG_FILE" 2>/dev/null || true

exit 0
