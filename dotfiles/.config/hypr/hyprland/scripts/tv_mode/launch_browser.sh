#!/usr/bin/env bash
# Open Chrome (TV profile) as an app window with the given URL.
# Steam Big Picture passes the URL via the shortcut's launch options.
# Hyprland windowrules send class chrome-*-TV to special:tv-app and fullscreen it.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/home/linmax/.config/hypr/hyprland/scripts/tv_mode/config.sh
source "${SCRIPT_DIR}/config.sh"

URL="${1:?URL required}"
case "$URL" in
    web) URL="$TV_WEB_URL" ;;
    youtube) URL="$TV_YOUTUBE_URL" ;;
    netflix) URL="$TV_NETFLIX_URL" ;;
    rumble) URL="$TV_RUMBLE_URL" ;;
esac

tv_clients_json() {
    local json
    json="$(hyprctl -j clients 2>/dev/null || true)"
    jq -e 'type == "array"' >/dev/null 2>&1 <<<"$json" || return 1
    printf '%s\n' "$json"
}

tv_browser_windows() {
    local clients_json
    clients_json="$(tv_clients_json)" || return 0
    jq -r '
        .[] |
        select(.mapped != false and .hidden != true) |
        select(.workspace.name == "special:tv-app") |
        select((.class // "") | test("^chrome-.*-TV$")) |
        .address
    ' <<<"$clients_json"
}

tv_wait_for_new_browser_window() {
    local before="$1"
    local after address

    for _ in $(seq 1 120); do
        after="$(tv_browser_windows || true)"
        address="$(
            comm -13 \
                <(printf '%s\n' "$before" | sed '/^$/d' | sort -u) \
                <(printf '%s\n' "$after" | sed '/^$/d' | sort -u) |
                head -n 1
        )"
        if [[ -n "$address" ]]; then
            printf '%s\n' "$address"
            return 0
        fi

        address="$(printf '%s\n' "$after" | sed '/^$/d' | head -n 1)"
        if [[ -n "$address" ]]; then
            printf '%s\n' "$address"
            return 0
        fi

        sleep 0.10
    done

    return 1
}

tv_window_exists() {
    local address="$1"
    tv_browser_windows | grep -Fxq "$address"
}

tv_wait_for_window_close() {
    local address="$1"
    while tv_window_exists "$address"; do
        sleep 0.20
    done
}

# Steam should track the visible TV app window, not Chrome's profile-wide
# background process. Chrome may stay alive after the app window closes.
before_windows="$(tv_browser_windows || true)"

env \
    -u LD_PRELOAD \
    -u LD_LIBRARY_PATH \
    -u STEAM_RUNTIME \
    -u STEAM_RUNTIME_LIBRARY_PATH \
    -u STEAM_RUNTIME_PREFER_HOST_LIBRARIES \
    -u STEAM_COMPAT_CLIENT_INSTALL_PATH \
    -u STEAM_COMPAT_DATA_PATH \
    -u SteamAppId \
    -u SteamGameId \
    -u STEAM_GAME_ID \
    "$TV_CHROME_BIN" \
        --user-data-dir="${HOME}/.config/google-chrome" \
        --profile-directory="$TV_CHROME_PROFILE_DIR" \
        --remote-debugging-address=127.0.0.1 \
        --remote-debugging-port=9222 \
        --app="$URL" \
        --start-fullscreen \
        --disable-gpu \
        --disable-gpu-compositing \
        --disable-features=Vulkan &
chrome_launcher_pid="$!"

if address="$(tv_wait_for_new_browser_window "$before_windows")"; then
    tv_wait_for_window_close "$address"
    exit 0
fi

# If Chrome never mapped a window, keep Steam's state tied to the launched
# process when possible so failed starts still report sensibly.
if kill -0 "$chrome_launcher_pid" 2>/dev/null; then
    wait "$chrome_launcher_pid" || true
fi

exit 0
