#!/usr/bin/env bash
set -euo pipefail

# Usage: lock-weather-emoji.sh [City name]
LOC="${1:-}"  # empty = auto by IP; or pass "London", "Abingdon, Oxfordshire", etc.
LOC_URL="${LOC// /+}"

fetch_weather() {
  curl -fsSL --retry 2 --retry-delay 1 --retry-all-errors --connect-timeout 5 --max-time 10 \
    "https://wttr.in/${1}?format=%t|%C" 2>/dev/null || true
}

# Fetch "temp|Condition" (eg: "+12°C|Partly cloudy")
raw="$(fetch_weather "$LOC_URL")"
if [[ -z "$raw" && "$LOC_URL" == *,* ]]; then
  raw="$(fetch_weather "${LOC_URL//,/}")"
fi
IFS='|' read -r temp cond <<<"${raw:-|}"

# Clean up temp
temp="${temp#+}"  # drop leading plus sign like +12°C

# Choose emoji based on condition (lowercased match)
lc="$(tr '[:upper:]' '[:lower:]' <<< "${cond:-}")"
emoji="🌡️"
case "$lc" in
  *thunder*|*storm*)        emoji="⛈️" ;;
  *snow*|*blizzard*|*sleet*)emoji="❄️" ;;
  *hail*)                   emoji="🌨️" ;;
  *heavy*rain*|*pour*)      emoji="🌧️" ;;
  *rain*|*drizzle*|*shower*)emoji="🌦️" ;;
  *clear*|*sunny*)          emoji="☀️" ;;
  *partly*|*broken*cloud*)  emoji="⛅" ;;
  *overcast*|*cloud*)       emoji="☁️" ;;
  *fog*|*mist*|*haze*)      emoji="🌫️" ;;
  *wind*|*breeze*|*gale*)   emoji="🌬️" ;;
esac

# Fallbacks if fetch failed
[[ -z "$temp" ]] && temp="--"
[[ -z "$cond" ]] && cond="N/A"

# Output with your styling (Pango markup ok in hyprlock)
printf '<b> <big> %s %s</big></b>' "$emoji" "$temp"
