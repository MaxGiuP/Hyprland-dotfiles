#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/home/linmax/.config/hypr/hyprland/scripts/tv_mode/common.sh
source "${SCRIPT_DIR}/common.sh"

tv_require_command hyprctl jq pkill pgrep steam python3
tv_action_lock_or_exit "Steam launch"

mode="${1:-gamepadui}"
monitor="$(tv_ensure_monitor)"
match_regex='^(steam|Steam|steamwebhelper|steam_app_.*)$'
bigpicture_title_regex='Steam Big Picture Mode|Modalità Big Picture di Steam'
special_selector="$(tv_special_selector)"
steam_process_regex='(/Steam/steam\.sh|/Steam/ubuntu12_32/steam|steamwebhelper|steam-runtime-launcher-service|steam-runtime-l)'
steam_kill_regex="$steam_process_regex"

tv_any_steam_running() {
    local clients_json

    clients_json="$(tv_clients_json)" || return 1
    jq -e '
        .[] |
        select(
            ((.class // "") | test("^(steam|Steam|steamwebhelper|steam_app_.*)$")) or
            ((.initialClass // "") | test("^(steam|Steam|steamwebhelper|steam_app_.*)$")) or
            ((.title // "") | test("Steam")) or
            ((.initialTitle // "") | test("Steam"))
        )
    ' >/dev/null 2>&1 <<<"$clients_json"
}

tv_any_steam_process_running() {
    pgrep -af "$steam_process_regex" >/dev/null 2>&1
}

tv_wait_for_steam_process_exit() {
    for _ in $(seq 1 150); do
        if ! tv_any_steam_process_running; then
            return 0
        fi

        sleep 0.10
    done

    return 1
}

tv_wait_for_bigpicture_window() {
    local address clients_json
    local max_attempts="${1:-30}"

    for _ in $(seq 1 "$max_attempts"); do
        clients_json="$(tv_clients_json || true)"
        if [[ -n "$clients_json" ]]; then
            address="$(tv_select_bigpicture_address "$clients_json")"

            if [[ -n "$address" ]]; then
                tv_move_window_to_special "$address"
                tv_show_special_on_monitor "$monitor"
                tv_focus_window_on_monitor "$address" "$monitor" true
                return 0
            fi
        fi

        sleep 0.25
    done

    return 1
}

tv_kill_lingering_steam() {
    if tv_focus_usable_steam_window; then
        return 0
    fi

    tv_notify "TV mode" "Cleaning stale Steam process before launching Big Picture."

    tv_steam_env -shutdown >/dev/null 2>&1 || true
    tv_wait_for_steam_process_exit && return 0

    pkill -TERM -f "$steam_kill_regex" >/dev/null 2>&1 || true
    tv_wait_for_steam_process_exit && return 0

    pkill -KILL -f "$steam_kill_regex" >/dev/null 2>&1 || true
    tv_wait_for_steam_process_exit || true
}

tv_configure_steam_tv_input() {
    if tv_any_steam_process_running; then
        return 0
    fi

    python3 "${SCRIPT_DIR}/configure_steam_tv_input.py" >/dev/null 2>&1 || true
}

tv_sync_steam_shortcuts() {
    python3 "${SCRIPT_DIR}/sync_steam_shortcuts.py" >/dev/null 2>&1 || true
}

tv_steam_env() {
    env \
        -u QT_QPA_PLATFORM \
        -u QT_QPA_PLATFORMTHEME \
        steam "$@"
}

tv_start_steam_background() {
    local unit

    unit="tv-steam-client-$(date +%s%N)"
    if command -v systemd-run >/dev/null 2>&1; then
        systemd-run \
            --user \
            --collect \
            --quiet \
            --property=KillMode=process \
            --property=StandardOutput=journal \
            --property=StandardError=journal \
            "--unit=${unit}" \
            env \
                -u QT_QPA_PLATFORM \
                -u QT_QPA_PLATFORMTHEME \
                steam "$@" >/dev/null 2>&1 || true
        tv_log "started Steam command in service ${unit}: steam $*"
        return 0
    fi

    setsid -f env \
        -u QT_QPA_PLATFORM \
        -u QT_QPA_PLATFORMTHEME \
        steam "$@" >/dev/null 2>&1 || true
}

tv_loaded_nvidia_version() {
    awk '
        /^NVRM version:/ {
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^[0-9]+[.][0-9]+[.][0-9]+$/) {
                    print $i
                    exit
                }
            }
        }
    ' /proc/driver/nvidia/version 2>/dev/null || true
}

tv_installed_nvidia_userspace_version() {
    command -v pacman >/dev/null 2>&1 || return 0
    pacman -Q nvidia-utils 2>/dev/null | awk '{ print $2 }' | sed 's/-.*//' || true
}

tv_abort_on_nvidia_driver_mismatch() {
    local loaded_version installed_version

    loaded_version="$(tv_loaded_nvidia_version)"
    installed_version="$(tv_installed_nvidia_userspace_version)"

    if [[ -z "$loaded_version" || -z "$installed_version" || "$loaded_version" == "$installed_version" ]]; then
        return 1
    fi

    tv_set_state "error" "Steam cannot start until the NVIDIA driver reloads" "$mode" "steam" "$monitor"
    tv_notify "TV mode" "Steam cannot start: loaded NVIDIA module is ${loaded_version}, but nvidia-utils is ${installed_version}. Reboot to load the updated driver."
    return 0
}

tv_steam_client_filter() {
    cat <<'JQ'
        (((.class // "") | test("^(steam|Steam|steamwebhelper|steam_app_.*)$")) or
         ((.initialClass // "") | test("^(steam|Steam|steamwebhelper|steam_app_.*)$")) or
         ((.title // "") | test("Steam")) or
         ((.initialTitle // "") | test("Steam")))
JQ
}

tv_has_steam_client_window() {
    local clients_json

    clients_json="$(tv_clients_json)" || return 1
    jq -e ".[] | select($(tv_steam_client_filter))" >/dev/null 2>&1 <<<"$clients_json"
}

tv_wait_for_steam_client_window() {
    for _ in $(seq 1 80); do
        if tv_has_steam_client_window; then
            return 0
        fi

        sleep 0.25
    done

    return 1
}

tv_select_bigpicture_address() {
    local clients_json="$1"
    local workspace_name="${2:-}"

    jq -r --arg workspace_name "$workspace_name" --arg title_regex "$bigpicture_title_regex" '
        .[] |
        select($workspace_name == "" or .workspace.name == $workspace_name) |
        select(
            (((.class // "") | test("^(steam|Steam|steamwebhelper)$")) or
             ((.initialClass // "") | test("^(steam|Steam|steamwebhelper)$"))) and
            (((.title // "") | test($title_regex)) or
             ((.initialTitle // "") | test($title_regex)))
        ) |
        .address
    ' <<<"$clients_json" | head -n 1
}

tv_select_usable_steam_address() {
    local clients_json="$1"
    local workspace_name="${2:-}"

    jq -r --arg workspace_name "$workspace_name" --arg title_regex "$bigpicture_title_regex" '
        [
            .[] |
            select($workspace_name == "" or .workspace.name == $workspace_name) |
            select(
                (((.class // "") | test("^(steam|Steam|steamwebhelper)$")) or
                 ((.initialClass // "") | test("^(steam|Steam|steamwebhelper)$"))) and
                (((.title // "") | test($title_regex)) or
                 ((.initialTitle // "") | test($title_regex)))
            )
        ] |
        sort_by(.focusHistoryID // -1) |
        reverse |
        .[0].address // empty
    ' <<<"$clients_json" | head -n 1
}

tv_select_any_steam_address() {
    local clients_json="$1"

    jq -r '
        [
            .[] |
            select(
                (((.class // "") | test("^(steam|Steam|steamwebhelper|steam_app_.*)$")) or
                 ((.initialClass // "") | test("^(steam|Steam|steamwebhelper|steam_app_.*)$")) or
                 ((.title // "") | test("Steam")) or
                 ((.initialTitle // "") | test("Steam")))
            )
        ] |
        sort_by(.focusHistoryID // -1) |
        .[0].address // empty
    ' <<<"$clients_json" | head -n 1
}

tv_select_existing_couch_address() {
    local clients_json="$1"

    jq -r --arg special "$special_selector" --arg title_regex "$bigpicture_title_regex" '
        [
            .[] |
            select(.workspace.name == $special) |
            select(
                ((.class // "") | test("^(steam|Steam|steamwebhelper)$")) or
                ((.initialClass // "") | test("^(steam|Steam|steamwebhelper)$"))
            ) |
            select(
                (((.title // "") | test($title_regex)) or
                 ((.initialTitle // "") | test($title_regex))) | not
            )
        ] |
        sort_by(.focusHistoryID // -1) |
        .[0].address // empty
    ' <<<"$clients_json" | head -n 1
}

tv_promote_special_steam_to_bigpicture() {
    local clients_json address

    clients_json="$(tv_clients_json || true)"
    [[ -n "$clients_json" ]] || return 1

    address="$(tv_select_existing_couch_address "$clients_json")"
    [[ -n "$address" ]] || return 1

    tv_move_window_to_special "$address"
    tv_show_special_on_monitor "$monitor"
    tv_focus_window_on_monitor "$address" "$monitor" true
    tv_start_steam_background "$steam_uri"
    tv_wait_for_bigpicture_window 40
}

tv_focus_usable_steam_window() {
    local clients_json address

    clients_json="$(tv_clients_json || true)"
    [[ -n "$clients_json" ]] || return 1

    address="$(tv_select_usable_steam_address "$clients_json")"
    [[ -n "$address" ]] || return 1

    tv_move_window_to_special "$address"
    tv_show_special_on_monitor "$monitor"
    tv_focus_window_on_monitor "$address" "$monitor" true
    return 0
}

tv_focus_any_steam_window() {
    local clients_json address

    clients_json="$(tv_clients_json || true)"
    [[ -n "$clients_json" ]] || return 1

    address="$(tv_select_any_steam_address "$clients_json")"
    [[ -n "$address" ]] || return 1

    tv_move_window_to_special "$address"
    tv_show_special_on_monitor "$monitor"
    tv_focus_window_on_monitor "$address" "$monitor" true
    return 0
}

tv_wait_for_steam_and_move_to_special() {
    local monitor_name="$1"
    local address clients_json

    for _ in $(seq 1 180); do
        clients_json="$(tv_clients_json || true)"
        if [[ -n "$clients_json" ]]; then
            address="$(tv_select_bigpicture_address "$clients_json")"
            [[ -n "$address" ]] || address="$(tv_select_existing_couch_address "$clients_json")"

            if [[ -n "$address" ]]; then
                tv_move_window_to_special "$address"
                tv_show_special_on_monitor "$monitor_name"
                tv_focus_window_on_monitor "$address" "$monitor_name"
                return 0
            fi
        fi

        sleep 0.50
    done

    tv_notify "TV mode" "Steam launch did not produce a detectable TV window."
    return 1
}

case "$mode" in
    bigpicture)
        steam_args=(-tenfoot -fulldesktopres)
        steam_uri='steam://open/bigpicture'
        ;;
    gamepadui|steamdeck|steamos)
        steam_args=(-gamepadui -fulldesktopres)
        steam_uri='steam://open/bigpicture'
        ;;
    *)
        printf 'Unsupported Steam TV mode: %s\n' "$mode" >&2
        exit 1
        ;;
esac

tv_set_state "starting" "Launching Steam Big Picture on ${monitor}" "$mode" "steam" "$monitor"
tv_notify "TV mode" "Steam focus command registered. Focusing or launching Big Picture on ${monitor} and switching audio."
tv_prepare_special_workspace "$monitor"

focused_steam=false
if tv_promote_special_steam_to_bigpicture; then
    focused_steam=true
elif tv_focus_usable_steam_window; then
    focused_steam=true
elif tv_abort_on_nvidia_driver_mismatch; then
    exit 1
elif tv_any_steam_process_running; then
    tv_focus_any_steam_window || true
    tv_start_steam_background "$steam_uri"
    if ! tv_wait_for_bigpicture_window 32; then
        if tv_focus_usable_steam_window; then
            focused_steam=true
        elif tv_has_steam_client_window; then
            if tv_focus_any_steam_window; then
                focused_steam=true
            fi
            tv_notify "TV mode" "Steam is running and was moved to the TV workspace. It was not force-quit; use Back + Start + LT + RT for stale cleanup."
        else
            tv_notify "TV mode" "Steam process exists but no client window appeared. Use Back + Start + LT + RT to clean stale Steam state."
        fi
    else
        focused_steam=true
    fi
else
    tv_configure_steam_tv_input
    tv_sync_steam_shortcuts
    # Starting directly with -gamepadui can crash current Steam builds here.
    # Bring up the client first, then ask the running client to enter Big Picture.
    tv_start_steam_background
    tv_wait_for_steam_client_window || true
    tv_start_steam_background "$steam_uri"
    if tv_wait_for_bigpicture_window 80; then
        focused_steam=true
    fi
fi

tv_show_special_on_monitor "$monitor"
if [[ "$focused_steam" == "true" ]]; then
    tv_switch_audio_to_tv
    tv_set_state "active" "Steam Big Picture is on ${monitor}" "$mode" "steam" "$monitor"
    tv_notify "TV mode" "Sent Steam Big Picture to ${monitor} special workspace $(tv_special_selector)."
else
    tv_set_state "error" "Steam did not produce a detectable window on ${monitor}" "$mode" "steam" "$monitor"
    tv_notify "TV mode" "Steam did not produce a detectable TV window on ${monitor}."
    exit 1
fi
