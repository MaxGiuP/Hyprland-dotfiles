#!/usr/bin/env bash
# Aggiorna pacman, flatpak, yay, paru con scelta S/n per manuale o automatica.
# Ora esegue tutti gli updater in un UNICO comando concatenato con &&.
# Prima dell'esecuzione fa sudo -v per chiedere la password una sola volta
# e tenerla in cache per pacman / yay / paru.

###############################################################################
# Sezione Hyprland: rende la finestra attiva floating 1000x700 e centrata
###############################################################################
if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && command -v hyprctl >/dev/null 2>&1; then
  sleep 0.05
  hyprctl dispatch setfloating active on
  hyprctl dispatch resizeactive exact 1000 700
  hyprctl dispatch centerwindow
fi
# fine sezione Hyprland

set -u

###############################################################################
# Funzioni di utilità
###############################################################################

log() {
  printf "\n[%s] %s\n" "$(date '+%F %T')" "$1"
}

# Ritorna 0 se il comando esiste
has() {
  command -v "$1" >/dev/null 2>&1
}

# Esegue un comando mostrando il log e NON interrompe lo script in caso di errore
# Restituisce sempre 0, ma stampa il codice reale
run_cmd() {
  log "Eseguo: $*"
  bash -lc "$*"
  local code=$?
  if [ $code -ne 0 ]; then
    log "Comando fallito con codice $code"
  fi
  return 0
}

# Aspetta che pacman non sia bloccato
wait_pacman_lock() {
  local lock="/var/lib/pacman/db.lck"
  if [ -e "$lock" ]; then
    log "Attendo lo sblocco di pacman"
    while [ -e "$lock" ]; do
      sleep 2
    done
  fi
}

# Chiede all'utente se aggiornare automaticamente o manualmente
# Ritorna la stringa "automatica" o "manuale"
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

###############################################################################
# Snapshot pacchetti pendenti (prima e dopo)
###############################################################################

# Pacman pendenti (serve pacman-contrib per checkupdates)
list_pending_pacman() {
  if ! has checkupdates; then return 0; fi
  # Output: pacchetto
  checkupdates 2>/dev/null | awk '{print $1}' | sort -u
}

# Flatpak pendenti
list_pending_flatpak() {
  if ! has flatpak; then return 0; fi
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

# Intersezione tra due liste ordinate
intersect_sorted() {
  comm -12 "$1" "$2"
}

###############################################################################
# Costruzione del comando unico di aggiornamento
###############################################################################
# build_update_command <mode>
# mode: "automatica" oppure "manuale"
# produce una stringa tipo:
#   (yes y | sudo pacman -Syu) && (flatpak update -y) && ({ printf 'n\n'; yes ''; } | yay -Syu) && ({ printf 'n\n'; yes ''; } | paru -Syu)
#
build_update_command() {
  local mode="$1"
  local cmds=()
  local snippet=""

  # pacman
  if has pacman; then
    if has sudo; then
      if [ "$mode" = "automatica" ]; then
        snippet="(yes S | sudo pacman -Syu)"
      else
        snippet="(sudo pacman -Syu)"
      fi
    else
      if [ "$mode" = "automatica" ]; then
        snippet="(yes S | pacman -Syu)"
      else
        snippet="(pacman -Syu)"
      fi
    fi
    cmds+=("$snippet")
  fi

  # flatpak
  if has flatpak; then
    if [ "$mode" = "automatica" ]; then
      snippet="(flatpak update -y)"
    else
      snippet="(flatpak update)"
    fi
    cmds+=("$snippet")
  fi

  # yay
  if has yay; then
    if [ "$mode" = "automatica" ]; then
      # Rifiuta modifica PKGBUILD ('n') e poi yes '' per continuare senza fermarsi
      snippet="({ printf 'n\n'; yes ''; } | yay -Syu)"
    else
      snippet="(yay -Syu)"
    fi
    cmds+=("$snippet")
  fi

  # paru
  if has paru; then
    if [ "$mode" = "automatica" ]; then
      snippet="({ printf 'n\n'; yes ''; } | paru -Syu)"
    else
      snippet="(paru -Syu)"
    fi
    cmds+=("$snippet")
  fi

  # Join con &&
  local joined=""
  local c
  for c in "${cmds[@]}"; do
    if [ -z "$joined" ]; then
      joined="$c"
    else
      joined="$joined && $c"
    fi
  done

  printf "%s" "$joined"
}

###############################################################################
# Main
###############################################################################

main() {
  printf "== Aggiornamento sistema avviato ==\n"

  local mode
  mode="$(get_mode "${1:-}")"
  log "Modalità: $mode"

  # Snapshot BEFORE
  log "Rilevo pacchetti pendenti (prima)"
  mapfile -t PAC_BEFORE  < <(list_pending_pacman   || true)
  mapfile -t FLAT_BEFORE < <(list_pending_flatpak  || true)
  mapfile -t YAY_BEFORE  < <(list_pending_yay      || true)
  mapfile -t PARU_BEFORE < <(list_pending_paru     || true)

  # Se pacman esiste, aspetta lock
  if has pacman; then
    wait_pacman_lock
  fi

  # Pre-autenticazione sudo per cercare di chiedere la password solo una volta
  if has sudo; then
    log "Autenticazione"
    sudo -v || log "sudo -v non riuscito o annullato"
  fi

  # Costruisci il comando unico
  local big_cmd
  big_cmd="$(build_update_command "$mode")"

  log "Avvio aggiornamenti in un singolo comando concatenato con &&"
  if [ -n "$big_cmd" ]; then
    run_cmd "$big_cmd"
  else
    log "Nessun gestore di pacchetti trovato (pacman / flatpak / yay / paru)"
  fi

  log "Aggiornamenti eseguiti"

  # Snapshot AFTER
  log "Rilevo pacchetti ancora pendenti (dopo)"
  mapfile -t PAC_AFTER  < <(list_pending_pacman   || true)
  mapfile -t FLAT_AFTER < <(list_pending_flatpak  || true)
  mapfile -t YAY_AFTER  < <(list_pending_yay      || true)
  mapfile -t PARU_AFTER < <(list_pending_paru     || true)

  # Intersezione BEFORE ∩ AFTER = roba non aggiornata
  local tmpdir
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

  # Report a schermo
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

  # pausa prima di chiudere la finestra kitty/Hyprland
  read -p "Premi INVIO per continuare"

  # Scrivi file per integrazione con la barra Quickshell
  local uid rund fail_file
  uid="$(id -u)"
  rund="/run/user/$uid"
  mkdir -p "$rund"
  fail_file="$rund/qs_upd_failed"

  {
    printf "pacman:"
    if [ "${#PAC_FAILED[@]}" -gt 0 ]; then
      printf " %s" "${PAC_FAILED[@]}"
    fi
    printf "\n"

    printf "flatpak:"
    if [ "${#FLAT_FAILED[@]}" -gt 0 ]; then
      printf " %s" "${FLAT_FAILED[@]}"
    fi
    printf "\n"

    printf "yay:"
    if [ "${#YAY_FAILED[@]}" -gt 0 ]; then
      printf " %s" "${YAY_FAILED[@]}"
    fi
    printf "\n"

    printf "paru:"
    if [ "${#PARU_FAILED[@]}" -gt 0 ]; then
      printf " %s" "${PARU_FAILED[@]}"
    fi
    printf "\n"
  } >"$fail_file"

  log "Aggiornamenti completati"
}

###############################################################################
# Esegui main
###############################################################################
main "$@"

###############################################################################
# Aggiorna il contatore condiviso per la barra Quickshell
# (numero totale di update ancora pendenti dopo l'aggiornamento)
###############################################################################
uid=$(id -u)
rund="/run/user/$uid"
file="$rund/qs_upd_count"
tmp="$rund/qs_upd_count.$$"

p=0
f=0
y=0
r=0

command -v checkupdates >/dev/null 2>&1 && p=$(checkupdates 2>/dev/null | wc -l) || true
command -v flatpak     >/dev/null 2>&1 && f=$(flatpak remote-ls --updates 2>/dev/null | wc -l) || true
command -v yay         >/dev/null 2>&1 && y=$(yay  -Qua 2>/dev/null | wc -l) || true
command -v paru        >/dev/null 2>&1 && r=$(paru -Qua 2>/dev/null | wc -l) || true

n=$((p+f+y+r))

printf "%s\n" "$n" > "$tmp" && mv -f "$tmp" "$file"
