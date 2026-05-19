#!/usr/bin/env bash

set -euo pipefail

log_path="/tmp/rpcs3-steam.log"

strip_steam_input_environment() {
    local name

    while IFS='=' read -r name _; do
        case "$name" in
            Steam*|STEAM_*|GAMEOVERLAYRENDERER|GAMEOVERLAYRENDERER64|SDL_GAMECONTROLLER_ALLOW_STEAM_VIRTUAL_GAMEPAD)
                unset "$name"
                ;;
        esac
    done < <(env)
}

cd "$HOME"

unset LD_PRELOAD
unset GAMEOVERLAYRENDERER
unset GAMEOVERLAYRENDERER64
unset STEAM_COMPAT_CLIENT_INSTALL_PATH
unset STEAM_COMPAT_DATA_PATH
unset SDL_GAMECONTROLLERCONFIG
unset SDL_GAMECONTROLLER_IGNORE_DEVICES
unset SDL_GAMECONTROLLER_IGNORE_DEVICES_EXCEPT
strip_steam_input_environment

export SDL_GAMECONTROLLER_ALLOW_STEAM_VIRTUAL_GAMEPAD=0
export SDL_HINT_JOYSTICK_HIDAPI=0
export SDL_HINT_JOYSTICK_HIDAPI_STEAM=0
export SDL_HINT_JOYSTICK_HIDAPI_STEAMDECK=0
export QT_QPA_PLATFORM=xcb

exec /usr/bin/rpcs3 "$@" >"$log_path" 2>&1
