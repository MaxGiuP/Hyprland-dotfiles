#!/usr/bin/env bash
set -euo pipefail

# Playerctl: lista di player da provare (ordine di priorità)
players="spotify,mpv,vlc,chromium,firefox"

# Lunghezza massima (override: MAX_NP_LEN=40 ./script.sh)
max_len="${MAX_NP_LEN:-40}"

# Ellissi semplice (byte-based)
ellipse() {
  local s="${1-}" max="${2:-$max_len}"
  if (( ${#s} > max )); then
    printf '%s…' "${s:0:max-1}"
  else
    printf '%s' "$s"
  fi
}

# Stato player
st="$(playerctl -p "$players" status 2>/dev/null || true)"
if [[ -z "$st" ]]; then
  echo "Nothing playing"
  exit 0
fi

# Solo titolo
title="$(playerctl -p "$players" metadata --format '{{title}}' 2>/dev/null || true)"

# Se non abbiamo titolo, mostra lo stato (Playing/Paused)
if [[ -z "$title" ]]; then
  echo "$st"
  exit 0
fi

ellipse "$title" "$max_len"
