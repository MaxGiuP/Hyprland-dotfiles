#!/usr/bin/env bash
# Usage: uninstall_app.sh <app_id> <app_name>
APP_ID="$1"
APP_NAME="$2"
EVENT_LOG="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/launchpad_uninstall_events.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

mkdir -p "$(dirname "$EVENT_LOG")"

log_event() {
    printf '%s\t%s\n' "$APP_ID" "$1" >> "$EVENT_LOG"
}

echo -e "${BOLD}Uninstalling: ${APP_NAME}${NC}"
echo "  App ID: ${APP_ID}"
echo ""

# ── 1. Flatpak ────────────────────────────────────────────────────────────
if flatpak info "$APP_ID" &>/dev/null; then
    echo -e "${YELLOW}→ Found via Flatpak${NC}"
    if flatpak uninstall --delete-data -y "$APP_ID"; then
        echo -e "${GREEN}✓ Uninstalled successfully.${NC}"
        log_event success
        sleep 1
        exit 0
    fi
fi

# ── 2. Find desktop file and owning pacman package ───────────────────────
DESKTOP_FILE=""
for SEARCH_PATH in \
    "/usr/share/applications/${APP_ID}.desktop" \
    "$HOME/.local/share/applications/${APP_ID}.desktop" \
    "/usr/share/applications/${APP_ID,,}.desktop"
do
    if [ -f "$SEARCH_PATH" ]; then
        DESKTOP_FILE="$SEARCH_PATH"
        break
    fi
done

if [ -z "$DESKTOP_FILE" ]; then
    # Try fuzzy match
    DESKTOP_FILE=$(find /usr/share/applications -maxdepth 1 -iname "*${APP_ID##*.}*.desktop" 2>/dev/null | head -1)
fi

if [ -n "$DESKTOP_FILE" ]; then
    PKG=$(pacman -Qoq "$DESKTOP_FILE" 2>/dev/null || true)
    if [ -n "$PKG" ]; then
        echo -e "${YELLOW}→ Found package '${PKG}' via pacman${NC}"
        if command -v paru &>/dev/null; then
            echo "  Using: paru"
            paru -Rns "$PKG"
        elif command -v yay &>/dev/null; then
            echo "  Using: yay"
            yay -Rns "$PKG"
        else
            echo "  Using: sudo pacman"
            sudo pacman -Rns "$PKG"
        fi
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Uninstalled successfully.${NC}"
            log_event success
            sleep 1
            exit 0
        fi
    fi
fi

echo -e "${RED}✗ Could not find '${APP_NAME}' in known package managers.${NC}"
log_event failed
echo ""
echo "Tried:"
echo "  • Flatpak:  flatpak info ${APP_ID}"
echo "  • pacman:   pacman -Qoq ${DESKTOP_FILE:-/usr/share/applications/${APP_ID}.desktop}"
echo ""
echo "You may need to uninstall it manually."
echo ""
echo "Press Enter to close..."
read
