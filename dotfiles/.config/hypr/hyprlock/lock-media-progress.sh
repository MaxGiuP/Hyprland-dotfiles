#!/usr/bin/env bash
set -euo pipefail

PLAYERS="spotify,mpv,vlc,chromium,firefox"

# mm:ss
fmt() {
  local s="$1"; s="${s%.*}"
  (( s < 0 )) && s=0
  printf "%02d:%02d" "$(( s/60 ))" "$(( s%60 ))"
}

# Build bar with full block chars (UTF-8)
# Env overrides: FILL, EMPTY, WIDTH
make_bar() {
  local pct="$1" width="${2:-${WIDTH:-16}}"
  local fillch="${FILL:-█}" emptych="${EMPTY:-·}"

  (( pct < 0 ))  && pct=0
  (( pct > 100 )) && pct=100

  local fill=$(( pct * width / 100 ))
  (( fill > width )) && fill="$width"
  local empty=$(( width - fill ))

  local left="" right=""; local i
  for (( i = 0; i < fill;  i++ )); do left+="$fillch";  done
  for (( i = 0; i < empty; i++ )); do right+="$emptych"; done
  printf '|%s%s| %d%%' "$left" "$right" "$pct"
}

# If playerctl missing or idle
if ! command -v playerctl >/dev/null 2>&1; then
  echo "--:-- / --:-- |$(printf '·%.0s' {1..16})| 0%"
  exit 0
fi

status="$(playerctl -p "$PLAYERS" status 2>/dev/null || true)"
if [[ -z "$status" ]]; then
  echo "--:-- / --:-- |$(printf '·%.0s' {1..16})| 0%"
  exit 0
fi

len_us="$(playerctl -p "$PLAYERS" metadata mpris:length 2>/dev/null || echo 0)"
pos_s="$(playerctl -p "$PLAYERS" position 2>/dev/null || echo 0)"

len=$(( len_us / 1000000 ))
pos="${pos_s%.*}"

if (( len <= 0 )); then
  echo "--:-- / --:-- |$(printf '·%.0s' {1..16})| 0%"
  exit 0
fi

pct=$(( pos * 100 / len ))
printf "%s / %s %s\n" "$(fmt "$pos")" "$(fmt "$len")" "$(make_bar "$pct")"
