#!/usr/bin/env sh
# restart_quickshell.sh
# Chiude tutti i processi quickshell e qs, poi avvia "qs -c ii".

set -eu

QS_BIN="${QS_BIN:-}"

if [ -z "$QS_BIN" ]; then
  for candidate in "$HOME/.local/bin/qs" "$HOME/.local/bin/quickshell" qs quickshell /usr/bin/qs /usr/bin/quickshell; do
    if command -v "$candidate" >/dev/null 2>&1; then
      QS_BIN="$(command -v "$candidate")"
      break
    fi
  done
fi

if [ -z "$QS_BIN" ]; then
  echo "Errore: quickshell/qs non trovato nel PATH." >&2
  exit 1
fi

# 1) Prova chiusura pulita
pkill -TERM -x quickshell 2>/dev/null || true
pkill -TERM -x qs 2>/dev/null || true

# 2) Attendi che scendano, con piccolo timeout
i=0
while [ $i -lt 20 ]; do
  if ! pgrep -x quickshell >/dev/null 2>&1 && ! pgrep -x qs >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
  i=$((i+1))
done

# 3) Se qualcosa resta, forza la chiusura
pgrep -x quickshell >/dev/null 2>&1 && pkill -KILL -x quickshell || true
pgrep -x qs >/dev/null 2>&1 && pkill -KILL -x qs || true

# 4) Avvia nuova istanza, staccata
setsid -f "$QS_BIN" -c ii >/dev/null 2>&1 &

echo "Riavviato: $QS_BIN -c ii"
