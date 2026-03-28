#!/usr/bin/env bash
set -euo pipefail

# Quali player controllare con playerctl
players="spotify,mpv,vlc,chromium,firefox"

st="$(playerctl -p "$players" status 2>/dev/null || true)"
if [[ "$st" == "Playing" ]]; then
  printf '⏸'
else
  printf '▶'
fi
