#!/usr/bin/env bash
# Aggiorna pacman, flatpak, yay, paru con scelta S/N per manuale o automatico.
# Nessun uso di opzioni con doppio trattino (eccetto flatpak remote-ls --updates per il riepilogo e la conta, già usato altrove).

# --- Hyprland: rendi la finestra attiva floating 1000x700 e centrata
if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ] && command -v hyprctl >/dev/null 2>&1; then
  sleep 0.05
  hyprctl dispatch setfloating active on
  hyprctl dispatch resizeactive exact 1000 700
  hyprctl dispatch centerwindow
fi
# --- fine sezione Hyprland

set -u

log() { printf "\n[%s] %s\n" "$(date '+%F %T')" "$1"; }
has() { command -v "$1" >/dev/null 2>&1; }

run_cmd() {
  # Esegue un comando mostrando il log e NON interrompe lo script in caso di errore
  # Restituisce sempre 0, ma logga il codice reale
  log "Eseguo: $*"
  bash -lc "$*"
  local code=$?
  if [ $code -ne 0 ]; then
    log "Comando fallito con codice $code"
  fi
  return 0
}

wait_pacman_lock() {
  local lock="/var/lib/pacman/db.lck"
  if [ -e "$lock" ]; then
    log "Attendo lo sblocco di pacman"
    while [ -e "$lock" ]; do sleep 2; done
  fi
}

get_mode() {
  local ans="${1:-}"
  if [ -z "$ans" ]; then
    printf "Aggiornare automaticamente? [S/n]: " >/dev/tty
    read -r ans </dev/tty
  fi
  case "$ans" in
    S|s) echo "automatica" ;;
    N|n) echo "manuale" ;;
    *)   echo "automatica" ;;
  esac
}

# ---- Snapshot pendenti: BEFORE/AFTER ---------------------------------------

# Pacman pendenti (serve pacman-contrib per checkupdates)
list_pending_pacman() {
  if ! has checkupdates; then return 0; fi
  # Output: nomepacchetto
  checkupdates 2>/dev/null | awk '{print $1}' | sort -u
}

# Flatpak pendenti
list_pending_flatpak() {
  if ! has flatpak; then return 0; fi
  # Usiamo la colonna ref per avere un identificatore univoco
  flatpak remote-ls --updates 2>/dev/null --columns=ref | sed '1d' | sort -u
}

# AUR tramite yay
list_pending_yay() {
  if ! has yay; then return 0; fi
  yay -Qua 2>/dev/null | awk '{print $1}' | sort -u
}

# AUR tramite paru
list_pending_paru() {
  if ! has paru; then return 0; fi
  paru -Qua 2>/dev/null | awk '{print $1}' | sort -u
}

# Intersezione insiemi: tiene gli elementi presenti in entrambi (comm richiede liste ordinate)
intersect_sorted() {
  # usa process substitution; richiede bash
  # stdin: niente, usa file temporanei passati come <(echo ...)
  comm -12 "$1" "$2"
}

# ---- Updaters ---------------------------------------------------------------

update_pacman() {
  if ! has pacman; then log "pacman non trovato"; return; fi
  wait_pacman_lock
  if has sudo; then
    if [ "$1" = "automatica" ]; then
      run_cmd "yes y | sudo pacman -Syu"
    else
      run_cmd "sudo pacman -Syu"
    fi
  else
    if [ "$1" = "automatica" ]; then
      run_cmd "yes y | pacman -Syu"
    else
      run_cmd "pacman -Syu"
    fi
  fi
}

update_flatpak() {
  if ! has flatpak; then log "flatpak non trovato"; return; fi
  if [ "$1" = "automatica" ]; then
    run_cmd "flatpak update -y"
  else
    run_cmd "flatpak update"
  fi
}

# In automatico: rifiuta modifica PKGBUILD con 'n' e invia invii vuoti ai prompt successivi
update_yay() {
  if ! has yay; then log "yay non trovato"; return; fi
  if [ "$1" = "automatica" ]; then
    run_cmd "{ printf 'n\n'; yes ''; } | yay -Syu"
  else
    run_cmd "yay -Syu"
  fi
}

update_paru() {
  if ! has paru; then log "paru non trovato"; return; fi
  if [ "$1" = "automatica" ]; then
    run_cmd "{ printf 'n\n'; yes ''; } | paru -Syu"
  else
    run_cmd "paru -Syu"
  fi
}

# ---- Main -------------------------------------------------------------------

main() {
  printf "== Aggiornamento sistema avviato ==\n"
  local mode
  mode="$(get_mode "${1:-}")"
  log "Modalità: $mode"

  # Snapshot BEFORE
  log "Rilevo pacchetti pendenti (prima)"
  mapfile -t PAC_BEFORE < <(list_pending_pacman || true)
  mapfile -t FLAT_BEFORE < <(list_pending_flatpak || true)
  mapfile -t YAY_BEFORE < <(list_pending_yay || true)
  mapfile -t PARU_BEFORE < <(list_pending_paru || true)

  log "Avvio aggiornamenti"
  update_pacman "$mode"
  update_flatpak "$mode"
  update_yay "$mode"
  update_paru "$mode"
  log "Aggiornamenti eseguiti"

  # Snapshot AFTER
  log "Rilevo pacchetti ancora pendenti (dopo)"
  mapfile -t PAC_AFTER < <(list_pending_pacman || true)
  mapfile -t FLAT_AFTER < <(list_pending_flatpak || true)
  mapfile -t YAY_AFTER < <(list_pending_yay || true)
  mapfile -t PARU_AFTER < <(list_pending_paru || true)

  # Intersezione BEFORE ∩ AFTER = falliti o saltati
  # scrivi liste temporanee ordinate
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT

  printf "%s\n" "${PAC_BEFORE[@]:-}"  | sort -u >"$tmpdir/pac_b"
  printf "%s\n" "${PAC_AFTER[@]:-}"   | sort -u >"$tmpdir/pac_a"
  printf "%s\n" "${FLAT_BEFORE[@]:-}" | sort -u >"$tmpdir/flat_b"
  printf "%s\n" "${FLAT_AFTER[@]:-}"  | sort -u >"$tmpdir/flat_a"
  printf "%s\n" "${YAY_BEFORE[@]:-}"  | sort -u >"$tmpdir/yay_b"
  printf "%s\n" "${YAY_AFTER[@]:-}"   | sort -u >"$tmpdir/yay_a"
  printf "%s\n" "${PARU_BEFORE[@]:-}" | sort -u >"$tmpdir/paru_b"
  printf "%s\n" "${PARU_AFTER[@]:-}"  | sort -u >"$tmpdir/paru_a"

  mapfile -t PAC_FAILED  < <(intersect_sorted "$tmpdir/pac_b"  "$tmpdir/pac_a")
  mapfile -t FLAT_FAILED < <(intersect_sorted "$tmpdir/flat_b" "$tmpdir/flat_a")
  mapfile -t YAY_FAILED  < <(intersect_sorted "$tmpdir/yay_b"  "$tmpdir/yay_a")
  mapfile -t PARU_FAILED < <(intersect_sorted "$tmpdir/paru_b" "$tmpdir/paru_a")

  # Report su stdout
  printf "\n== RIEPILOGO PACCHETTI NON AGGIORNATI ==\n"
  if [ "${#PAC_FAILED[@]}" -gt 0 ]; then
    printf "pacman: %s\n" "$(printf "%s " "${PAC_FAILED[@]}")"
  else
    printf "pacman: nessuno\n"
  fi
  if [ "${#FLAT_FAILED[@]}" -gt 0 ]; then
    printf "flatpak: %s\n" "$(printf "%s " "${FLAT_FAILED[@]}")"
  else
    printf "flatpak: nessuno\n"
  fi
  if [ "${#YAY_FAILED[@]}" -gt 0 ]; then
    printf "yay: %s\n" "$(printf "%s " "${YAY_FAILED[@]}")"
  else
    printf "yay: nessuno\n"
  fi
  if [ "${#PARU_FAILED[@]}" -gt 0 ]; then
    printf "paru: %s\n" "$(printf "%s " "${PARU_FAILED[@]}")"
  else
    printf "paru: nessuno\n"
  fi


read -p "Premi INVIO per continuare"

  # Scrivi file per integrazione con la barra
  uid="$(id -u)"
  rund="/run/user/$uid"
  mkdir -p "$rund"
  fail_file="$rund/qs_upd_failed"
  {
    printf "pacman:"
    if [ "${#PAC_FAILED[@]}" -gt 0 ]; then printf " %s" "${PAC_FAILED[@]}"; fi
    printf "\nflatpak:"
    if [ "${#FLAT_FAILED[@]}" -gt 0 ]; then printf " %s" "${FLAT_FAILED[@]}"; fi
    printf "\nyay:"
    if [ "${#YAY_FAILED[@]}" -gt 0 ]; then printf " %s" "${YAY_FAILED[@]}"; fi
    printf "\nparu:"
    if [ "${#PARU_FAILED[@]}" -gt 0 ]; then printf " %s" "${PARU_FAILED[@]}"; fi
    printf "\n"
  } >"$fail_file"

  log "Aggiornamenti completati"
}

main "$@"

# --- aggiorna il contatore condiviso per la barra Quickshell
uid=$(id -u)
rund="/run/user/$uid"
file="$rund/qs_upd_count"
tmp="$rund/qs_upd_count.$$"
p=0; f=0; y=0; r=0
command -v checkupdates >/dev/null 2>&1 && p=$(checkupdates 2>/dev/null | wc -l) || true
command -v flatpak     >/dev/null 2>&1 && f=$(flatpak remote-ls --updates 2>/dev/null | wc -l) || true
command -v yay         >/dev/null 2>&1 && y=$(yay  -Qua 2>/dev/null | wc -l) || true
command -v paru        >/dev/null 2>&1 && r=$(paru -Qua 2>/dev/null | wc -l) || true
n=$((p+f+y+r))
printf "%s\n" "$n" > "$tmp" && mv -f "$tmp" "$file"
