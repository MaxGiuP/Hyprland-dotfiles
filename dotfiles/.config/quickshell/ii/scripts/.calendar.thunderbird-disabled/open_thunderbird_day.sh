#!/usr/bin/env bash
set -euo pipefail

target_date="${1:-}"
if [[ -z "$target_date" ]]; then
  exit 1
fi

if ! target_epoch="$(date -d "$target_date" +%s 2>/dev/null)"; then
  exit 1
fi

today_epoch="$(date -d "$(date +%F)" +%s)"
day_diff="$(( (target_epoch - today_epoch) / 86400 ))"

thunderbird -calendar >/dev/null 2>&1 &

# Let Thunderbird window appear and receive focus.
sleep 0.55
hyprctl dispatch focuswindow "class:^(thunderbird)$" >/dev/null 2>&1 || true
sleep 0.12

# Start from today, then step to the target day.
wtype -M alt -k End -m alt

if (( day_diff == 0 )); then
  exit 0
fi

if (( day_diff > 0 )); then
  direction_key="Right"
  steps="$day_diff"
else
  direction_key="Left"
  steps="$((-day_diff))"
fi

# Keep this bounded in case of bad input.
if (( steps > 730 )); then
  steps=730
fi

for ((i = 0; i < steps; i++)); do
  wtype -k "$direction_key"
done
