#!/usr/bin/env bash

set -euo pipefail

timeout_minutes="${1:-10}"
suspend_minutes="${2:-45}"
case "${timeout_minutes}" in
    ''|*[!0-9]*)
        timeout_minutes=10
        ;;
esac
case "${suspend_minutes}" in
    ''|*[!0-9]*)
        suspend_minutes=45
        ;;
esac

config_path="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hypridle.conf"

python3 - "$config_path" "$timeout_minutes" "$suspend_minutes" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
lock_minutes = max(1, min(240, int(sys.argv[2])))
suspend_minutes = max(lock_minutes + 5, min(480, int(sys.argv[3])))
lock_seconds = lock_minutes * 60
display_seconds = lock_seconds + 60
suspend_seconds = suspend_minutes * 60
start = "# >>> quickshell managed idle lock >>>"
end = "# <<< quickshell managed idle lock <<<"
idle_action_allowed_cmd = "~/.config/hypr/hyprland/scripts/quickshell_locked_idle_action_allowed.sh ii"
block = (
    f"{start}\n"
    "# Lock first. Normal idle inhibitors, including coffee mode and media,\n"
    "# intentionally pause this step.\n"
    "listener {\n"
    f"    timeout = {lock_seconds}\n"
    "    on-timeout = $lock_cmd\n"
    "}\n\n"
    "# Once locked, power down the displays even if an application still owns\n"
    "# a stale idle inhibitor. The condition explicitly honors coffee mode.\n"
    "listener {\n"
    f"    timeout = {display_seconds}\n"
    "    on-timeout = ~/.config/hypr/hyprland/scripts/hypr_dispatch.sh dpms off\n"
    "    on-resume = ~/.config/hypr/hyprland/scripts/on-dpms-resume.sh\n"
    "    ignore_inhibit = true\n"
    f"    condition_cmd = {idle_action_allowed_cmd}\n"
    "    condition_retry = 15\n"
    "}\n\n"
    "# Suspend only after a real Wayland session lock is active and coffee mode\n"
    "# is off. Hypridle also holds external sleep requests until the lock lands.\n"
    "listener {\n"
    f"    timeout = {suspend_seconds}\n"
    "    on-timeout = $suspend_cmd\n"
    "    ignore_inhibit = true\n"
    f"    condition_cmd = {idle_action_allowed_cmd}\n"
    "    condition_retry = 30\n"
    "}\n"
    f"{end}"
)

text = path.read_text() if path.exists() else ""
pattern = re.compile(re.escape(start) + r"[\s\S]*?" + re.escape(end), re.MULTILINE)

if pattern.search(text):
    updated = pattern.sub(block, text)
else:
    trimmed = re.sub(r"\s+$", "", text)
    updated = f"{trimmed}\n\n{block}\n" if trimmed else f"{block}\n"

if updated != text:
    path.write_text(updated)
PY

systemctl --user restart hypridle.service >/dev/null 2>&1 || true
