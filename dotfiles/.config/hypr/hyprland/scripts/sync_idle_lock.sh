#!/usr/bin/env bash

set -euo pipefail

timeout_minutes="${1:-10}"
case "${timeout_minutes}" in
    ''|*[!0-9]*)
        timeout_minutes=10
        ;;
esac

config_path="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hypridle.conf"

python3 - "$config_path" "$timeout_minutes" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
minutes = max(0, int(sys.argv[2]))
start = "# >>> quickshell managed idle lock >>>"
end = "# <<< quickshell managed idle lock <<<"

if minutes <= 0:
    block = f"{start}\n# Automatic idle lock disabled by Quickshell.\n{end}"
else:
    block = (
        f"{start}\n"
        "listener {\n"
        f"    timeout = {minutes * 60}\n"
        "    on-timeout = $lock_cmd\n"
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
