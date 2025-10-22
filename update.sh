#!/usr/bin/env bash
set -euo pipefail

########################################
# 0) Relaunch self inside a floating Kitty
########################################
if [[ "${DOTFILES_SYNC_INSIDE:-0}" != "1" ]]; then
  SCRIPT_PATH="$(readlink -f "$0")"
  REPO_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
  RUN_CMD="export DOTFILES_SYNC_INSIDE=1; cd \"$REPO_DIR\"; bash \"$SCRIPT_PATH\""

  if command -v kitty >/dev/null 2>&1; then
    if command -v hyprctl >/dev/null 2>&1; then
      hyprctl dispatch exec "[float; size 1100x720; move 180 140; noborder 1]" \
        "kitty --class DotfilesSync -d \"$REPO_DIR\" bash -lc '$RUN_CMD'" \
        >/dev/null 2>&1 || kitty --class DotfilesSync -d "$REPO_DIR" bash -lc "$RUN_CMD" &
    else
      kitty --class DotfilesSync -d "$REPO_DIR" bash -lc "$RUN_CMD" &
    fi
    exit 0
  else
    echo "kitty not found; running in current shell."
    export DOTFILES_SYNC_INSIDE=1
  fi
fi

########################################
# 1) From here on, we’re *inside* the Kitty instance
########################################

# ===== Settings =====
declare -A CFGS=(
  [hypr]="hypr"
  [quickshell]="quickshell"
  [illogical-impulse]="illogical-impulse"
)

# ===== UI helpers =====
BOLD=$(tput bold 2>/dev/null || true)
DIM=$(tput dim 2>/dev/null || true)
RESET=$(tput sgr0 2>/dev/null || true)
GREEN=$(tput setaf 2 2>/dev/null || true)
YELLOW=$(tput setaf 3 2>/dev/null || true)
RED=$(tput setaf 1 2>/dev/null || true)
BLUE=$(tput setaf 4 2>/dev/null || true)
hr(){ printf '%s\n' "${DIM}────────────────────────────────────────────────────────${RESET}"; }
say(){ printf '%b\n' "$*"; }
ok(){  say "${GREEN}✔${RESET} $*"; }
warn(){ say "${YELLOW}⚠${RESET} $*"; }
err(){ say "${RED}✖${RESET} $*"; }

# ===== Repo detection =====
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_DIR"
[[ -d .git ]] || { err "Run from inside your git repo (no .git in $REPO_DIR)"; exit 1; }

# ===== Paths =====
dest_path_for(){ echo "$REPO_DIR/dotfiles/$1/.config/${CFGS[$1]}/"; }
src_path_for(){  echo "$HOME/.config/${CFGS[$1]}/"; }

# ===== Flags / state =====
DRYRUN=0
rsync_flags(){ [[ $DRYRUN -eq 1 ]] && echo "-avn --delete" || echo "-av --delete"; }

# ===== Actions =====
sync_one(){ # $1=name
  local name="$1" src dst
  src="$(src_path_for "$name")"; dst="$(dest_path_for "$name")"
  [[ -d "$src" ]] || { warn "Skipping ${BOLD}$name${RESET} — source missing: $src"; return 0; }
  say "${BLUE}→ Sync ${BOLD}$name${RESET}${BLUE} (${src} → ${dst})${RESET}"
  mkdir -p "$dst"
  # shellcheck disable=SC2046
  rsync $(rsync_flags) "$src" "$dst" && ok "$name synced." || { err "$name sync failed."; return 1; }
  [[ $DRYRUN -eq 0 ]] && git add -A "$dst" || true
}

sync_all(){
  for name in "${!CFGS[@]}"; do sync_one "$name"; done
  [[ $DRYRUN -eq 0 ]] && ok "Staged changes." || warn "Dry-run: nothing staged."
}

choose_and_sync(){
  say "Answer ${BOLD}y/N${RESET} for each:"
  for name in "${!CFGS[@]}"; do
    read -r -p "Sync ${name}? [y/N] " a
    [[ "${a,,}" =~ ^y(es)?$ ]] && sync_one "$name" || say "Skipping $name."
  done
  [[ $DRYRUN -eq 0 ]] && ok "Staged changes." || warn "Dry-run: nothing staged."
}

show_status(){
  hr; say "${BOLD}Git status:${RESET}"; git status --short || true
  hr; say "${BOLD}Staged diff (names):${RESET}"; git diff --cached --name-only || true
  hr
}

commit_and_push(){
  [[ $DRYRUN -eq 1 ]] && { warn "Dry-run ON — not committing."; return 0; }
  if git diff --cached --quiet; then
    if ! git diff --quiet || git ls-files --others --exclude-standard | grep -q .; then
      read -r -p "Nothing staged. Stage ALL changes? [y/N] " a
      [[ "${a,,}" =~ ^y(es)?$ ]] && git add -A
    fi
  fi
  git diff --cached --quiet && { warn "Still nothing staged."; return 0; }
  local changed default_msg msg
  changed=$(git diff --cached --name-only | awk -F'/' '/^dotfiles\//{print $2}' | sort -u | tr '\n' ' ')
  default_msg="Sync ~/.config → repo (${changed:-dotfiles}) on $(date -Iseconds)"
  say "Commit message (blank = default):"; say "  ${DIM}$default_msg${RESET}"
  read -r -p "> " msg; msg="${msg:-$default_msg}"
  git commit -m "$msg"; ok "Committed."
  read -r -p "Push now? [Y/n] " p; [[ -z "$p" || "${p,,}" =~ ^y(es)?$ ]] && { git push; ok "Pushed."; } || warn "Skipped push."
}

toggle_dryrun(){
  if [[ $DRYRUN -eq 0 ]]; then DRYRUN=1; warn "Dry-run ON."; else DRYRUN=0; ok "Dry-run OFF."; fi
}

# ===== NEW A: purge .bak in quickshell trees (delete backups) =====
purge_quickshell_bak(){
  local live repo choices target path
  live="$(src_path_for quickshell)"
  repo="$(dest_path_for quickshell)"

  say "${BOLD}Purge .bak files for quickshell${RESET}"
  say "Choose target:"
  say "  1) Live config   (${live})"
  say "  2) Repo copy     (${repo})"
  say "  3) BOTH"
  read -r -p "Select [1-3]: " target

  case "$target" in
    1) choices=("$live") ;;
    2) choices=("$repo") ;;
    3) choices=("$live" "$repo") ;;
    *) warn "Invalid choice."; return 1 ;;
  esac

  for path in "${choices[@]}"; do
    [[ -d "$path" ]] || { warn "Missing: $path (skipping)"; continue; }
    say "${BLUE}→ Scanning:${RESET} $path"
    mapfile -t hits < <(find "$path" -type f -name '*\.bak*' -print 2>/dev/null | sort)
    if (( ${#hits[@]} == 0 )); then
      ok "No .bak files in $path"
      continue
    fi

    say "${YELLOW}Found ${#hits[@]} backup file(s):${RESET}"
    printf '  %s\n' "${hits[@]}"

    if [[ $DRYRUN -eq 1 ]]; then
      warn "Dry-run ON — nothing deleted."
      continue
    fi

    read -r -p "Delete these files? [y/N] " go
    if [[ "${go,,}" =~ ^y(es)?$ ]]; then
      while IFS= read -r f; do
        rm -f -- "$f" && say "  removed: $f"
      done < <(printf '%s\n' "${hits[@]}")
      ok "Cleanup done for $path"
      if [[ "$path" == "$repo"* ]]; then
        # Stage removals if under repo
        git rm -f --quiet $(printf '"%s" ' "${hits[@]}") 2>/dev/null || true
        ok "Staged removals from repo."
      fi
    else
      warn "Skipped deletion for $path"
    fi
  done
}

# ===== NEW B: restore from .bak in quickshell trees =====
# Restores file names by stripping the FIRST occurrence of ".bak" and everything after it.
# Examples:
#   foo.qml.bak                   -> foo.qml
#   foo.qml.bak.20251021_12       -> foo.qml
#   foo.bak.qml                   -> foo         (first ".bak" wins)
restore_quickshell_bak(){
  local live repo choices target path
  live="$(src_path_for quickshell)"
  repo="$(dest_path_for quickshell)"

  say "${BOLD}Restore from .bak backups (quickshell)${RESET}"
  say "Choose target:"
  say "  1) Live config   (${live})"
  say "  2) Repo copy     (${repo})"
  say "  3) BOTH"
  read -r -p "Select [1-3]: " target

  case "$target" in
    1) choices=("$live") ;;
    2) choices=("$repo") ;;
    3) choices=("$live" "$repo") ;;
    *) warn "Invalid choice."; return 1 ;;
  esac

  for path in "${choices[@]}"; do
    [[ -d "$path" ]] || { warn "Missing: $path (skipping)"; continue; }
    say "${BLUE}→ Scanning:${RESET} $path"

    # Find ANY file whose basename contains ".bak" anywhere (recursive)
    mapfile -t bakfiles < <(find "$path" -type f -name '*\.bak*' -print 2>/dev/null | sort)
    if (( ${#bakfiles[@]} == 0 )); then
      ok "No .bak files in $path"
      continue
    fi

    say "${YELLOW}Plan to restore ${#bakfiles[@]} file(s):${RESET}"
    for f in "${bakfiles[@]}"; do
      dest="$(python3 - <<'PY'
import sys, os
p=sys.argv[1]
d=os.path.dirname(p)
b=os.path.basename(p)
# strip the FIRST ".bak" and everything after it
if ".bak" in b:
    b = b.split(".bak", 1)[0]
print(os.path.join(d,b))
PY
"$f")"
      printf '  %-60s -> %s\n' "$f" "$dest"
    done

    if [[ $DRYRUN -eq 1 ]]; then
      warn "Dry-run ON — nothing restored."
      continue
    fi

    read -r -p "Proceed with restore (overwrite originals)? [y/N] " go
    [[ "${go,,}" =~ ^y(es)?$ ]] || { warn "Skipped restore for $path"; continue; }

    for f in "${bakfiles[@]}"; do
      dest="$(python3 - <<'PY'
import sys, os
p=sys.argv[1]
d=os.path.dirname(p)
b=os.path.basename(p)
if ".bak" in b:
    b = b.split(".bak", 1)[0]
print(os.path.join(d,b))
PY
"$f")"

      # Safety backup of current dest, if it exists
      if [[ -f "$dest" ]]; then
        safe="$dest.restore.$(date -Iseconds | tr -d ':')"
        cp -f -- "$dest" "$safe"
        say "  backup current: $dest -> $safe"
      fi

      # Restore (copy-overwrite) then remove the .bak source
      install -D -m 0644 -- "$f" "$dest"
      say "  restored: $f -> $dest"
      rm -f -- "$f"
    done

    ok "Restore done for $path"

    if [[ "$path" == "$repo"* ]]; then
      # Stage changes for repo copy
      git add -A "$path"
      ok "Staged restored files in repo."
    fi
  done
}

# ===== Menu =====
menu(){
  while true; do
    hr
    say "${BOLD}Dotfiles Sync Menu${RESET}  (${DIM}$REPO_DIR${RESET})"
    say "Dry-run: ${BOLD}$([[ $DRYRUN -eq 1 ]] && echo ON || echo OFF)${RESET}"
    hr
    say "1) Sync ALL configs"
    say "2) Pick configs to sync"
    say "3) Show git status/diff"
    say "4) Commit & push staged changes"
    say "5) Toggle dry-run"
    say "6) Purge .bak files (quickshell)"
    say "7) Restore from .bak (quickshell)"
    say "8) Exit"
    hr
    read -r -p "Choose [1-8]: " c
    case "$c" in
      1) sync_all ;;
      2) choose_and_sync ;;
      3) show_status ;;
      4) commit_and_push ;;
      5) toggle_dryrun ;;
      6) purge_quickshell_bak ;;
      7) restore_quickshell_bak ;;
      8) say "Bye!"; exit 0 ;;
      *) warn "Invalid choice." ;;
    esac
  done
}

say "[*] Ready to sync from ${BOLD}~/.config/*${RESET} → ${BOLD}$REPO_DIR/dotfiles/*${RESET}"
menu
