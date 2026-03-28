#!/usr/bin/env bash
# =============================================================================
# install.sh — Copy repo configs INTO your live system
#
# This is the APPLY direction:  dotfiles/.config/X  →  ~/.config/X
#
# WARNING: This will OVERWRITE your existing system config files.
# Existing files are backed up to <file>.bak.<timestamp> before overwriting.
#
# Usage:
#   bash install.sh          # interactive (confirm before each config)
#   bash install.sh -y       # skip confirmations, install everything
#   bash install.sh -n       # dry-run: show what would change, touch nothing
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$REPO_DIR/dotfiles/.config"

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

backup_dir() {
    local target="$1"
    if [[ -d "$target" && ! -L "$target" ]]; then
        local stamp
        stamp=$(date +%Y%m%d_%H%M%S)
        mv "$target" "${target}.bak.${stamp}"
        warn "Backed up existing $(basename "$target") → $(basename "${target}.bak.${stamp}")"
    fi
}

# ── Parse arguments ───────────────────────────────────────────────────────────
YES=0; DRY=0
for arg in "$@"; do
    case "$arg" in
        -y|--yes)      YES=1 ;;
        -n|--dry-run)  DRY=1 ;;
        -h|--help)
            echo "Usage: bash install.sh [-y] [-n]"
            echo "  -y   skip all confirmations"
            echo "  -n   dry-run, show changes without touching anything"
            exit 0 ;;
        *) err "Unknown argument: $arg"; exit 1 ;;
    esac
done

# ── Sanity checks ─────────────────────────────────────────────────────────────
[[ -d "$SRC_DIR" ]] || { err "dotfiles/.config not found — is this the right repo?"; exit 1; }

echo ""
echo -e "${BLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLD} Hyprland Dotfiles — INSTALL (repo → system)${NC}"
echo -e "${BLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  Repo   : ${CYN}$REPO_DIR${NC}"
echo -e "  Source : ${CYN}$SRC_DIR/<name>${NC}"
echo -e "  Target : ${CYN}~/.config/<name>${NC}"
[[ $DRY -eq 1 ]] && warn "DRY-RUN mode — nothing will be written"
echo ""

warn "⚠  This will OVERWRITE your live system config files."
warn "⚠  Existing directories are backed up as <name>.bak.<timestamp>"
warn "⚠  before being replaced — but review each prompt carefully."
echo ""
warn "Configs that will be installed:"
for cfg in "${MANAGED[@]}"; do
    [[ -d "$SRC_DIR/$cfg" ]] && echo -e "      ${CYN}•  $cfg${NC}"
done
echo ""

[[ $YES -eq 0 ]] && ! confirm "Install all of the above?" && { echo "Aborted."; exit 0; }

# ── Install loop ──────────────────────────────────────────────────────────────
installed=()
skipped=()

for cfg in "${MANAGED[@]}"; do
    src="$SRC_DIR/$cfg"
    dst="$HOME/.config/$cfg"

    if [[ ! -d "$src" ]]; then
        warn "$cfg — not in repo, skipping"
        skipped+=("$cfg")
        continue
    fi

    hdr "  $cfg"
    echo -e "    ${src}  →  ${dst}"

    # Show what would change
    if [[ -d "$dst" ]]; then
        changed=$(rsync -rin --delete "$src/" "$dst/" 2>/dev/null | grep -v '^\.' | head -20 || true)
        if [[ -z "$changed" ]]; then
            ok "$cfg — already up to date"
            installed+=("$cfg")
            continue
        fi
        echo -e "    ${YLW}Changes that will be applied:${NC}"
        echo "$changed" | sed 's/^/      /'
        warn "The existing ~/.config/$cfg will be backed up then replaced."
    else
        info "$cfg — new install (no existing config to overwrite)"
    fi

    if [[ $DRY -eq 1 ]]; then
        info "$cfg — skipped (dry-run)"
        continue
    fi

    if [[ $YES -eq 0 ]]; then
        confirm "Install $cfg?" || { warn "$cfg — skipped by user"; skipped+=("$cfg"); continue; }
    fi

    backup_dir "$dst"
    mkdir -p "$dst"
    rsync -a --delete "$src/" "$dst/"
    ok "$cfg installed"
    installed+=("$cfg")
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLD} Summary${NC}"
echo -e "${BLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
[[ ${#installed[@]} -gt 0 ]] && ok  "Installed : ${installed[*]}"
[[ ${#skipped[@]}   -gt 0 ]] && warn "Skipped   : ${skipped[*]}"

if [[ $DRY -eq 1 ]]; then
    echo ""
    warn "Dry-run complete — no files were changed."
    exit 0
fi

echo ""
ok "Done. Log out and back in (or restart Hyprland) to apply all changes."
