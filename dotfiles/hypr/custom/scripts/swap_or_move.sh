#!/usr/bin/env bash
# Usage: swap_or_move.sh <l|r|u|d>
set -euo pipefail

dir="${1:-}"
case "$dir" in l|r|u|d) ;; *) echo "Usage: $0 <l|r|u|d>" >&2; exit 1;; esac
command -v jq >/dev/null || { echo "Please install jq"; exit 1; }

# Active window address
aw="$(hyprctl -j activewindow 2>/dev/null || true)"
[ -n "$aw" ] || exit 0
waddr="$(jq -r '.address' <<<"$aw")"
[ "$waddr" != "null" ] || exit 0

# Monitors and current monitor center
mons="$(hyprctl -j monitors)"
cur="$(jq -r '.[] | select(.focused==true)' <<<"$mons")" || true
[ -n "$cur" ] || exit 0

cx=$(jq -r '.x' <<<"$cur"); cy=$(jq -r '.y' <<<"$cur")
cw=$(jq -r '.width' <<<"$cur"); ch=$(jq -r '.height' <<<"$cur")
ccx=$((cx + cw/2)); ccy=$((cy + ch/2))

# Pick nearest monitor whose center is beyond current center in the requested direction
target="$(jq -r --arg d "$dir" --argjson ccx "$ccx" --argjson ccy "$ccy" '
  [ .[]
    | {name, x, y, width, height, ws:(.activeWorkspace.id)}
    | .cx = (.x + (.width/2|floor))
    | .cy = (.y + (.height/2|floor))
    | select(
        ($d=="l" and .cx <  $ccx) or
        ($d=="r" and .cx >  $ccx) or
        ($d=="u" and .cy <  $ccy) or
        ($d=="d" and .cy >  $ccy)
      )
    | .dist = ((.cx - $ccx)|abs + (.cy - $ccy)|abs)
  ] | sort_by(.dist) | .[0]
' <<<"$mons")"

# If no monitor in that direction, just swap locally
if [ -z "$target" ] || [ "$target" = "null" ]; then
  hyprctl dispatch swapwindow "$dir"
  exit 0
fi

tws="$(jq -r '.ws' <<<"$target")"

# Is target workspace empty?
clients="$(hyprctl -j clients)"
count="$(jq --argjson ws "$tws" '[.[] | select(.workspace.id == $ws)] | length' <<<"$clients")"

if [ "$count" -eq 0 ]; then
  # Empty → prefer movewindow mon:<dir>, with a fallback if unsupported
  if hyprctl dispatch movewindow "mon:$dir" 2>/dev/null; then
    exit 0
  else
    # Fallback: move to that monitor's active workspace
    hyprctl dispatch movetoworkspace "$tws,address:$waddr"
    hyprctl dispatch focusworkspace "$tws"
    hyprctl dispatch focuswindow "address:$waddr"
  fi
else
  # Non empty → swap
  hyprctl dispatch swapwindow "$dir"
fi
