#!/usr/bin/env bash
# =============================================================================
# install.sh — Copy repo configs INTO your live system
#
# This is the APPLY direction:  dotfiles/.config/X  →  ~/.config/X
#
# WARNING: This will OVERWRITE your existing system config files.
# Files that change are backed up under <config>.bak.<timestamp>.
#
# Usage:
#   bash install.sh          # interactive (confirm before each config)
#   bash install.sh -y       # skip confirmations, install everything
#   bash install.sh -n       # dry-run: show what would change, touch nothing
#   bash install.sh --with-settingsd  # also build/install the native settings service
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$REPO_DIR/dotfiles/.config"
WALLPAPER_SRC="$REPO_DIR/wallpapers/dynamic-system"
WALLPAPER_DST="$HOME/Pictures/Wallpapers/dynamic-system"
SETTINGSD_SRC="$REPO_DIR/tools/ii-settingsd"
SETTINGSD_BIN_DST="$HOME/.local/bin/ii-settingsd"
SETTINGSD_UNIT_DST="$HOME/.config/systemd/user/ii-settingsd.service"
SETTINGSD_DOC_DST="$HOME/.local/share/doc/ii-settingsd/README.md"

# Never deploy editor state, backups, build trees, or runtime pseudo-files as
# desktop configuration. Excluded destination files are preserved by rsync.
RSYNC_EXCLUDES=(
    --exclude=__pycache__/
    --exclude=*.pyc
    --exclude='*.bak'
    --exclude='*.bak.*'
    --exclude='.claude/'
    --exclude='.git/'
    --exclude='target/'
    --exclude='desktop_positions.json'
    --exclude='anon_inode:*'
    --exclude='pipe:*'
    --exclude='socket:*'
)

# ── Configs managed by this repo ─────────────────────────────────────────────
MANAGED=(
    hypr
    quickshell
    illogical-impulse
    pkgtrim
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
    systemd
    user-tmpfiles.d
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

backup_file() {
    local target="$1"
    if [[ -e "$target" || -L "$target" ]]; then
        local stamp
        stamp=$(date +%Y%m%d_%H%M%S)
        mv -- "$target" "${target}.bak.${stamp}"
        warn "Backed up existing $(basename "$target") → $(basename "${target}.bak.${stamp}")"
    fi
}

# ── Parse arguments ───────────────────────────────────────────────────────────
YES=0; DRY=0; WITH_SETTINGSD=0
for arg in "$@"; do
    case "$arg" in
        -y|--yes)            YES=1 ;;
        -n|--dry-run)        DRY=1 ;;
        --with-settingsd)    WITH_SETTINGSD=1 ;;
        -h|--help)
            echo "Usage: bash install.sh [-y] [-n] [--with-settingsd]"
            echo "  -y                 skip all confirmations"
            echo "  -n                 dry-run, show changes without touching anything"
            echo "  --with-settingsd   build and deploy the native settings service"
            exit 0 ;;
        *) err "Unknown argument: $arg"; exit 1 ;;
    esac
done

# ── Sanity checks ─────────────────────────────────────────────────────────────
[[ -d "$SRC_DIR" ]] || { err "dotfiles/.config not found — is this the right repo?"; exit 1; }
if [[ $WITH_SETTINGSD -eq 1 ]]; then
    [[ -f "$SETTINGSD_SRC/Cargo.toml" ]] || { err "tools/ii-settingsd/Cargo.toml not found"; exit 1; }
    [[ -f "$SETTINGSD_SRC/Cargo.lock" ]] || { err "tools/ii-settingsd/Cargo.lock not found"; exit 1; }
    [[ -f "$SETTINGSD_SRC/README.md" ]] || { err "ii-settingsd README not found"; exit 1; }
    [[ -f "$SETTINGSD_SRC/systemd/ii-settingsd.service" ]] || { err "ii-settingsd user unit not found"; exit 1; }
    if [[ $DRY -eq 0 ]]; then
        command -v cargo >/dev/null || { err "Cargo is required for --with-settingsd"; exit 1; }
        command -v systemctl >/dev/null || { err "systemctl is required for --with-settingsd"; exit 1; }
    fi
fi

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
warn "⚠  Files that are replaced or deleted are backed up under"
warn "⚠  <name>.bak.<timestamp> — but review each prompt carefully."
echo ""
warn "Configs that will be installed:"
for cfg in "${MANAGED[@]}"; do
    [[ -d "$SRC_DIR/$cfg" ]] && echo -e "      ${CYN}•  $cfg${NC}"
done
if [[ $WITH_SETTINGSD -eq 1 ]]; then
    echo -e "      ${CYN}•  ii-settingsd (optional native service)${NC}"
fi
echo ""

[[ $YES -eq 0 ]] && ! confirm "Install all of the above?" && { echo "Aborted."; exit 0; }

# ── Install loop ──────────────────────────────────────────────────────────────
installed=()
skipped=()

for cfg in "${MANAGED[@]}"; do
    src="$SRC_DIR/$cfg"
    dst="$HOME/.config/$cfg"
    sync_mode_args=(--delete)
    case "$cfg" in
        systemd|user-tmpfiles.d)
            # These shared XDG directories may contain unrelated local files;
            # install the curated repo entries as a non-destructive overlay.
            sync_mode_args=(--checksum --no-times --omit-dir-times)
            ;;
    esac

    if [[ ! -d "$src" ]]; then
        warn "$cfg — not in repo, skipping"
        skipped+=("$cfg")
        continue
    fi

    hdr "  $cfg"
    echo -e "    ${src}  →  ${dst}"

    # Show what would change
    if [[ -d "$dst" ]]; then
        changed=$(rsync -rin "${sync_mode_args[@]}" "${RSYNC_EXCLUDES[@]}" \
            "$src/" "$dst/" 2>/dev/null | grep -v '^\.' | head -20 || true)
        if [[ -z "$changed" ]]; then
            ok "$cfg — already up to date"
            installed+=("$cfg")
            continue
        fi
        echo -e "    ${YLW}Changes that will be applied:${NC}"
        echo "$changed" | sed 's/^/      /'
        warn "Changed/deleted files will be backed up before this config is synchronized."
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

    backup=""
    if [[ -L "$dst" || ( -e "$dst" && ! -d "$dst" ) ]]; then
        backup_file "$dst"
    elif [[ -d "$dst" ]]; then
        stamp=$(date +%Y%m%d_%H%M%S)
        backup="${dst}.bak.${stamp}"
        [[ ! -e "$backup" ]] || backup="${backup}.$$"
        mkdir -p "$backup"
    fi
    mkdir -p "$dst"
    if [[ -n "$backup" ]]; then
        rsync -a "${sync_mode_args[@]}" --no-owner --no-group --backup --backup-dir="$backup" \
            "${RSYNC_EXCLUDES[@]}" "$src/" "$dst/"
        if find "$backup" -mindepth 1 -print -quit | grep -q .; then
            warn "Backed up replaced files → $(basename "$backup")"
        else
            rmdir -- "$backup"
        fi
    else
        rsync -a "${sync_mode_args[@]}" --no-owner --no-group "${RSYNC_EXCLUDES[@]}" "$src/" "$dst/"
    fi
    ok "$cfg installed"
    installed+=("$cfg")
done

if [[ $DRY -eq 0 && " ${installed[*]} " == *" systemd "* ]] \
        && command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload
    ok "systemd user units reloaded"
fi

# ── Curated dynamic wallpaper set ────────────────────────────────────────────
if [[ -d "$WALLPAPER_SRC" ]]; then
    hdr "  dynamic wallpapers"
    echo -e "    ${WALLPAPER_SRC}  →  ${WALLPAPER_DST}"

    wallpaper_changes=""
    for period in morning day evening night; do
        period_changes=$(rsync -rin --delete \
            "$WALLPAPER_SRC/$period/" "$WALLPAPER_DST/$period/" 2>/dev/null || true)
        [[ -n "$period_changes" ]] && wallpaper_changes+="${period}:\n${period_changes}\n"
    done

    if [[ -z "$wallpaper_changes" ]]; then
        ok "dynamic wallpapers — already up to date"
        installed+=("dynamic-wallpapers")
    else
        echo -e "    ${YLW}Changes that will be applied:${NC}"
        echo -e "$wallpaper_changes" | sed '/^$/d; s/^/      /'

        if [[ $DRY -eq 1 ]]; then
            info "dynamic wallpapers — skipped (dry-run)"
        elif [[ $YES -eq 1 ]] || confirm "Install curated dynamic wallpapers?"; then
            stamp=$(date +%Y%m%d_%H%M%S)
            archive_dir="$WALLPAPER_DST/archive-$stamp"
            install -d "$archive_dir"

            for period in morning day evening night; do
                install -d "$WALLPAPER_DST/$period" "$archive_dir/$period"
                find "$WALLPAPER_DST/$period" -maxdepth 1 -type f \
                    -exec mv -t "$archive_dir/$period" -- {} +
                rsync -a "$WALLPAPER_SRC/$period/" "$WALLPAPER_DST/$period/"
            done

            ok "dynamic wallpapers installed; previous active set archived at $archive_dir"
            installed+=("dynamic-wallpapers")
        else
            warn "dynamic wallpapers — skipped by user"
            skipped+=("dynamic-wallpapers")
        fi
    fi
fi

# ── Optional native settings service ─────────────────────────────────────────
if [[ $WITH_SETTINGSD -eq 1 ]]; then
    hdr "  ii-settingsd"
    echo -e "    ${SETTINGSD_SRC}  →  ${SETTINGSD_BIN_DST}"
    echo -e "    ${SETTINGSD_SRC}/systemd/ii-settingsd.service  →  ${SETTINGSD_UNIT_DST}"
    echo -e "    ${SETTINGSD_SRC}/README.md  →  ${SETTINGSD_DOC_DST}"

    if [[ $DRY -eq 1 ]]; then
        info "ii-settingsd — would build --release --locked, install, enable, and start"
    elif [[ $YES -eq 1 ]] || confirm "Build and install ii-settingsd?"; then
        cargo build \
            --release \
            --locked \
            --manifest-path "$SETTINGSD_SRC/Cargo.toml" \
            --target-dir "$SETTINGSD_SRC/target"

        [[ -x "$SETTINGSD_SRC/target/release/ii-settingsd" ]] || {
            err "Cargo completed without producing the ii-settingsd binary"
            exit 1
        }

        backup_file "$SETTINGSD_BIN_DST"
        backup_file "$SETTINGSD_UNIT_DST"
        backup_file "$SETTINGSD_DOC_DST"
        install -Dm755 "$SETTINGSD_SRC/target/release/ii-settingsd" "$SETTINGSD_BIN_DST"
        install -Dm644 "$SETTINGSD_SRC/systemd/ii-settingsd.service" "$SETTINGSD_UNIT_DST"
        install -Dm644 "$SETTINGSD_SRC/README.md" "$SETTINGSD_DOC_DST"

        systemctl --user daemon-reload
        systemctl --user enable ii-settingsd.service
        systemctl --user restart ii-settingsd.service
        ok "ii-settingsd installed, enabled, and started"
        installed+=("ii-settingsd")
    else
        warn "ii-settingsd — skipped by user"
        skipped+=("ii-settingsd")
    fi
fi

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
