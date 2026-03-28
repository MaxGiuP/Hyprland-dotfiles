#!/usr/bin/env bash
# =============================================================================
# update.sh — Copy live system configs INTO this repo
#
# This is the CAPTURE direction:  ~/.config/X  →  dotfiles/.config/X
#
# Run this whenever you've changed your config and want to save it to git.
# It will OVERWRITE whatever is already in the repo with your system files.
#
# Usage:
#   bash update.sh          # interactive (confirm before each config)
#   bash update.sh -y       # skip confirmations, sync everything
#   bash update.sh -n       # dry-run: show what would change, touch nothing
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_DIR="$REPO_DIR/dotfiles/.config"

# ── Configs managed by this repo ─────────────────────────────────────────────
MANAGED=(
    hypr
    quickshell
    illogical-impulse
    rofi
    kitty
    foot
    dunst
    wlogout
    swaylock
    swaync
    gtk-3.0
    gtk-4.0
    Kvantum
    nwg-look
    fish
)

# ── Colour helpers ────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    RED='\033[0;31m' YLW='\033[0;33m' GRN='\033[0;32m'
    CYN='\033[0;36m' BLD='\033[1m'    NC='\033[0m'
else
    RED='' YLW='' GRN='' CYN='' BLD='' NC=''
fi

info()  { echo -e "${CYN}  →  ${*}${NC}"; }
ok()    { echo -e "${GRN}  ✓  ${*}${NC}"; }
warn()  { echo -e "${YLW}  !  ${*}${NC}"; }
err()   { echo -e "${RED}  ✗  ${*}${NC}" >&2; }
hdr()   { echo -e "\n${BLD}${*}${NC}"; }

confirm() {
    local msg="$1"
    local default="${2:-y}"
    local prompt
    [[ "$default" == "y" ]] && prompt="[Y/n]" || prompt="[y/N]"
    read -rp "$(echo -e "    ${YLW}${msg} ${prompt}${NC} ")" ans
    case "${ans:-$default}" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

# ── Parse arguments ───────────────────────────────────────────────────────────
YES=0; DRY=0
for arg in "$@"; do
    case "$arg" in
        -y|--yes)      YES=1 ;;
        -n|--dry-run)  DRY=1 ;;
        -h|--help)
            echo "Usage: bash update.sh [-y] [-n]"
            echo "  -y   skip all confirmations"
            echo "  -n   dry-run, show changes without touching anything"
            exit 0 ;;
        *) err "Unknown argument: $arg"; exit 1 ;;
    esac
done

# ── Sanity checks ─────────────────────────────────────────────────────────────
[[ -d "$REPO_DIR/.git" ]] || { err "Not a git repo: $REPO_DIR"; exit 1; }

echo ""
echo -e "${BLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLD} Hyprland Dotfiles — UPDATE (system → repo)${NC}"
echo -e "${BLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  Repo   : ${CYN}$REPO_DIR${NC}"
echo -e "  Source : ${CYN}~/.config/<name>${NC}"
echo -e "  Target : ${CYN}$DEST_DIR/<name>${NC}"
[[ $DRY -eq 1 ]] && warn "DRY-RUN mode — nothing will be written"
echo ""
warn "This will OVERWRITE repo files with your live system files."
warn "Any uncommitted changes already in the repo will be lost."
echo ""

[[ $YES -eq 0 ]] && ! confirm "Continue?" && { echo "Aborted."; exit 0; }

# ── Sync loop ─────────────────────────────────────────────────────────────────
synced=()
skipped=()

for cfg in "${MANAGED[@]}"; do
    src="$HOME/.config/$cfg"
    dst="$DEST_DIR/$cfg"

    if [[ ! -d "$src" ]]; then
        warn "$cfg — not found in ~/.config/, skipping"
        skipped+=("$cfg")
        continue
    fi

    hdr "  $cfg"
    echo -e "    ${src}  →  ${dst}"

    # Show a quick summary of what will change
    if [[ -d "$dst" ]]; then
        changed=$(rsync -rin --delete "$src/" "$dst/" 2>/dev/null | grep -v '^\.' | head -20 || true)
        if [[ -z "$changed" ]]; then
            ok "$cfg — already up to date"
            synced+=("$cfg")
            continue
        fi
        echo -e "    ${YLW}Changes:${NC}"
        echo "$changed" | sed 's/^/      /'
    else
        info "$cfg — new (not yet in repo)"
    fi

    if [[ $DRY -eq 1 ]]; then
        info "$cfg — skipped (dry-run)"
        continue
    fi

    if [[ $YES -eq 0 ]]; then
        confirm "Sync $cfg?" || { warn "$cfg — skipped by user"; skipped+=("$cfg"); continue; }
    fi

    mkdir -p "$dst"
    rsync -a --delete "$src/" "$dst/"
    ok "$cfg synced"
    synced+=("$cfg")
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLD} Summary${NC}"
echo -e "${BLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
[[ ${#synced[@]}  -gt 0 ]] && ok  "Synced  : ${synced[*]}"
[[ ${#skipped[@]} -gt 0 ]] && warn "Skipped : ${skipped[*]}"

[[ $DRY -eq 1 ]] && { echo ""; warn "Dry-run complete — no files were changed."; exit 0; }

# ── Git status ────────────────────────────────────────────────────────────────
echo ""
cd "$REPO_DIR"
git_status=$(git status --short 2>/dev/null || true)
if [[ -z "$git_status" ]]; then
    ok "Git: nothing to commit — repo already matches system"
    exit 0
fi

hdr "  Git status"
echo "$git_status" | head -30 | sed 's/^/    /'

echo ""
if [[ $YES -eq 1 ]] || confirm "Commit these changes?"; then
    read -rp "$(echo -e "    ${CYN}Commit message (leave blank for auto): ${NC}")" msg
    if [[ -z "$msg" ]]; then
        changed_names=$(git diff --name-only HEAD 2>/dev/null | awk -F'/' '{print $3}' | sort -u | tr '\n' ' ' || echo "configs")
        msg="Update dotfiles from system: ${changed_names}"
    fi
    git add -A
    git commit -m "$msg"
    ok "Committed"

    echo ""
    if [[ $YES -eq 1 ]] || confirm "Push to remote?"; then
        git push
        ok "Pushed"
    else
        info "Run 'git push' when ready"
    fi
fi
