#!/usr/bin/env bash
set -euo pipefail

PACMAN_CONF="/etc/pacman.conf"

usage() {
  echo "Usage:"
  echo "  $0 show"
  echo "  $0 add    pkg1 [pkg2 ...]"
  echo "  $0 remove pkg1 [pkg2 ...]"
  exit 1
}

get_current_ignorepkgs() {
  awk '
    /^[[:space:]]*IgnorePkg[[:space:]]*=/ {
      for (i = 3; i <= NF; i++) {
        print $i
      }
    }
  ' "$PACMAN_CONF"
}

write_ignorepkgs_line() {
  local joined="$1"
  local tmp
  tmp=$(mktemp)

  awk -v new="$joined" '
    BEGIN { done = 0 }
    /^[[:space:]]*IgnorePkg[[:space:]]*=/ {
      if (!done) {
        print new
        done = 1
      }
      next
    }
    { print }
    END {
      if (!done && new != "") {
        print new
      }
    }
  ' "$PACMAN_CONF" > "$tmp"

  sudo mv "$tmp" "$PACMAN_CONF"
}

cmd_show() {
  mapfile -t current < <(get_current_ignorepkgs || true)

  if [[ ${#current[@]} -eq 0 ]]; then
    echo "IgnorePkg is not set."
  else
    echo "Current IgnorePkg packages:"
    printf "  %s\n" "${current[@]}"
  fi
}

cmd_add() {
  if [[ $# -lt 1 ]]; then
    echo "Nothing to add."
    usage
  fi

  mapfile -t current < <(get_current_ignorepkgs || true)
  declare -A seen

  for pkg in "${current[@]}"; do
    seen["$pkg"]=1
  done

  for pkg in "$@"; do
    if [[ -z "${seen[$pkg]+x}" ]]; then
      current+=("$pkg")
      seen["$pkg"]=1
    fi
  done

  if [[ ${#current[@]} -eq 0 ]]; then
    echo "No packages to set in IgnorePkg."
    write_ignorepkgs_line ""
    return
  fi

  local joined="IgnorePkg = ${current[*]}"
  echo "New IgnorePkg line:"
  echo "  $joined"
  write_ignorepkgs_line "$joined"
}

cmd_remove() {
  if [[ $# -lt 1 ]]; then
    echo "Nothing to remove."
    usage
  fi

  mapfile -t current < <(get_current_ignorepkgs || true)
  if [[ ${#current[@]} -eq 0 ]]; then
    echo "IgnorePkg is empty, nothing to remove."
    return
  fi

  declare -A to_remove
  for pkg in "$@"; do
    to_remove["$pkg"]=1
  done

  new_list=()
  for pkg in "${current[@]}"; do
    if [[ -z "${to_remove[$pkg]+x}" ]]; then
      new_list+=("$pkg")
    fi
  done

  if [[ ${#new_list[@]} -eq 0 ]]; then
    echo "All packages removed. IgnorePkg line will be removed."
    write_ignorepkgs_line ""
    return
  fi

  local joined="IgnorePkg = ${new_list[*]}"
  echo "New IgnorePkg line:"
  echo "  $joined"
  write_ignorepkgs_line "$joined"
}

main() {
  if [[ $# -lt 1 ]]; then
    usage
  fi

  local cmd="$1"
  shift || true

  case "$cmd" in
    show)
      cmd_show
      ;;
    add)
      cmd_add "$@"
      ;;
    remove)
      cmd_remove "$@"
      ;;
    *)
      usage
      ;;
  esac
}

main "$@"

