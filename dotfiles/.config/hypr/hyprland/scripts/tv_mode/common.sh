#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/home/linmax/.config/hypr/hyprland/scripts/tv_mode/config.sh
source "${SCRIPT_DIR}/config.sh"

TV_STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/tv-mode"
TV_STATE_PATH="${TV_STATE_DIR}/state.json"
TV_ACTION_LOCK_PATH="${TV_STATE_DIR}/action.lock"

tv_log() {
    printf '[tv-mode] %s\n' "$*" >&2
}

tv_notify() {
    local title="$1"
    local body="$2"

    if command -v notify-send >/dev/null 2>&1; then
        notify-send "$title" "$body" >/dev/null 2>&1 || true
    else
        printf '%s: %s\n' "$title" "$body" >&2
    fi
}

tv_set_state() {
    local status="$1"
    local message="${2:-}"
    local mode="${3:-}"
    local app="${4:-}"
    local monitor="${5:-}"

    mkdir -p "$TV_STATE_DIR"
    jq -nc \
        --arg status "$status" \
        --arg message "$message" \
        --arg mode "$mode" \
        --arg app "$app" \
        --arg monitor "$monitor" \
        '{
            status: $status,
            message: $message,
            mode: $mode,
            app: $app,
            monitor: $monitor,
            updated_at: (now | floor)
        }' > "$TV_STATE_PATH"
}

tv_clear_state() {
    tv_set_state "stopped" "" "" "" ""
}

tv_action_lock_or_exit() {
    local label="${1:-action}"

    if [[ "${TV_ACTION_LOCK_HELD:-}" == "1" ]]; then
        return 0
    fi

    if ! command -v flock >/dev/null 2>&1; then
        tv_log "flock is unavailable; continuing without TV action lock for ${label}"
        return 0
    fi

    mkdir -p "$TV_STATE_DIR"
    exec 9>"$TV_ACTION_LOCK_PATH"
    if ! flock -n 9; then
        tv_log "TV ${label} ignored because another TV action is still running"
        tv_notify "TV mode" "A TV command is already running. Wait a few seconds, then try again."
        exit 0
    fi

    export TV_ACTION_LOCK_HELD=1
}

tv_require_command() {
    local missing=0
    local cmd

    for cmd in "$@"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            printf 'Missing required command: %s\n' "$cmd" >&2
            missing=1
        fi
    done

    if (( missing )); then
        exit 1
    fi
}

tv_monitor_json() {
    local json

    json="$(hyprctl -j monitors all 2>/dev/null || true)"
    if ! jq -e 'type == "array"' >/dev/null 2>&1 <<<"$json"; then
        json="$(timeout "${TV_HYPRCTL_TIMEOUT:-1.5}" hyprctl -j monitors all 2>/dev/null || true)"
    fi
    if ! jq -e 'type == "array"' >/dev/null 2>&1 <<<"$json"; then
        return 1
    fi

    printf '%s\n' "$json"
}

tv_clients_json() {
    local json

    json="$(hyprctl -j clients 2>/dev/null || true)"
    if ! jq -e 'type == "array"' >/dev/null 2>&1 <<<"$json"; then
        json="$(timeout "${TV_HYPRCTL_TIMEOUT:-1.5}" hyprctl -j clients 2>/dev/null || true)"
    fi
    if ! jq -e 'type == "array"' >/dev/null 2>&1 <<<"$json"; then
        return 1
    fi

    printf '%s\n' "$json"
}

tv_activewindow_json() {
    local json

    json="$(hyprctl -j activewindow 2>/dev/null || true)"
    if ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$json"; then
        json="$(timeout "${TV_HYPRCTL_TIMEOUT:-1.5}" hyprctl -j activewindow 2>/dev/null || true)"
    fi
    if ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$json"; then
        return 1
    fi

    printf '%s\n' "$json"
}

tv_workspace_has_live_windows() {
    local workspace="$1"
    local clients_json

    clients_json="$(tv_clients_json || true)"
    [[ -n "$clients_json" ]] || return 1

    jq -e --arg workspace "$workspace" '
        .[] |
        select(.mapped != false and .hidden != true) |
        select(.workspace.name == $workspace)
    ' >/dev/null 2>&1 <<<"$clients_json"
}

tv_close_windows_on_workspace() {
    local workspace="$1"
    local clients_json address

    clients_json="$(tv_clients_json || true)"
    [[ -n "$clients_json" ]] || return 0

    jq -r --arg workspace "$workspace" '
        .[] |
        select(.mapped != false and .hidden != true) |
        select(.workspace.name == $workspace) |
        .address
    ' <<<"$clients_json" | while IFS= read -r address; do
        [[ -n "$address" ]] || continue
        /home/linmax/.config/hypr/hyprland/scripts/hypr_dispatch.sh closewindow "address:${address}" >/dev/null 2>&1 || true
    done
}

tv_special_selector() {
    printf 'special:%s\n' "$TV_SPECIAL_WORKSPACE_NAME"
}

tv_resolve_monitor() {
    local monitors_json
    local candidate

    if ! monitors_json="$(tv_monitor_json)"; then
        return 1
    fi

    for candidate in "${TV_MONITOR_CANDIDATES[@]}"; do
        if printf '%s\n' "$monitors_json" | jq -e --arg name "$candidate" '.[] | select(.name == $name)' >/dev/null; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

tv_ensure_monitor() {
    local monitor

    if ! monitor="$(tv_resolve_monitor)"; then
        tv_stop_tv_workspaces_without_monitor
        tv_notify "TV mode" "No TV monitor matched ${TV_MONITOR_CANDIDATES[*]}."
        exit 1
    fi

    printf '%s\n' "$monitor"
}

tv_configure_monitor() {
    local monitor="$1"
    hyprctl keyword monitor "${monitor},preferred,auto-right,1" >/dev/null 2>&1 || true
}

tv_assign_special_workspace_rule() {
    local monitor="$1"
    local pinned_monitor

    pinned_monitor="$(tv_resolve_monitor || true)"
    if [[ -n "$pinned_monitor" && "$monitor" != "$pinned_monitor" ]]; then
        monitor="$pinned_monitor"
    fi

    hyprctl keyword workspace "$(tv_special_selector), persistent:true, monitor:${monitor}, gapsin:0, gapsout:0, border:false, rounding:false, decorate:false" >/dev/null 2>&1 || true
    hyprctl keyword workspace "special:tv-app, persistent:true, monitor:${monitor}, gapsin:0, gapsout:0, border:false, rounding:false, decorate:false" >/dev/null 2>&1 || true
    /home/linmax/.config/hypr/hyprland/scripts/hypr_dispatch.sh moveworkspacetomonitor "$(tv_special_selector)" "$monitor" >/dev/null 2>&1 || true
    /home/linmax/.config/hypr/hyprland/scripts/hypr_dispatch.sh moveworkspacetomonitor "special:tv-app" "$monitor" >/dev/null 2>&1 || true
}

tv_resolve_audio_sink() {
    local configured="${TV_AUDIO_SINK_NAME:-}"
    local nick="${TV_AUDIO_SINK_NICK:-HDTV}"
    local sinks

    command -v pactl >/dev/null 2>&1 || return 1

    if [[ -n "$configured" ]] && pactl list short sinks 2>/dev/null | awk '{print $2}' | grep -Fxq "$configured"; then
        printf '%s\n' "$configured"
        return 0
    fi

    pactl list sinks 2>/dev/null | awk -v nick="$nick" '
        /^Sink #/ {
            if (matched && name != "") {
                print name
                exit
            }
            matched = 0
            name = ""
        }
        $1 == "Name:" {
            name = $2
        }
        $0 ~ "node.nick = \"" nick "\"" || $0 ~ "alsa.name = \"" nick "\"" {
            matched = 1
        }
        END {
            if (matched && name != "")
                print name
        }
    ' | head -n 1
}

tv_switch_audio_to_tv() {
    local sink current input_id

    sink="$(tv_resolve_audio_sink || true)"
    [[ -n "$sink" ]] || return 0

    current="$(pactl get-default-sink 2>/dev/null || true)"
    if [[ "$current" != "$sink" ]]; then
        pactl set-default-sink "$sink" >/dev/null 2>&1 || return 0
    fi

    pactl list short sink-inputs 2>/dev/null | awk '{print $1}' | while IFS= read -r input_id; do
        [[ -n "$input_id" ]] || continue
        pactl move-sink-input "$input_id" "$sink" >/dev/null 2>&1 || true
    done
}

tv_special_visible_monitor() {
    local special

    special="$(tv_special_selector)"
    tv_monitor_json | jq -r --arg special "$special" '
        .[] | select(.specialWorkspace.name == $special) | .name
    ' | head -n 1
}

tv_monitor_has_special_visible() {
    local monitor="$1"
    local special

    special="$(tv_special_selector)"
    tv_monitor_json | jq -e --arg name "$monitor" --arg special "$special" '
        .[] | select(.name == $name and .specialWorkspace.name == $special)
    ' >/dev/null
}

tv_special_short_name() {
    local workspace="$1"
    printf '%s\n' "${workspace#special:}"
}

tv_visible_monitor_for_special_workspace() {
    local workspace="$1"

    tv_monitor_json | jq -r --arg workspace "$workspace" '
        .[] | select(.specialWorkspace.name == $workspace) | .name
    ' | head -n 1
}

tv_visible_special_on_monitor() {
    local monitor="$1"

    tv_monitor_json | jq -r --arg monitor "$monitor" '
        .[] | select(.name == $monitor) | .specialWorkspace.name // ""
    ' | head -n 1
}

tv_monitor_has_special_workspace_visible() {
    local monitor="$1"
    local workspace="$2"

    tv_monitor_json | jq -e --arg name "$monitor" --arg workspace "$workspace" '
        .[] | select(.name == $name and .specialWorkspace.name == $workspace)
    ' >/dev/null
}

tv_toggle_special_workspace_on_monitor() {
    local workspace="$1"
    local monitor="$2"
    local follow_mouse

    follow_mouse="$(hyprctl getoption input:follow_mouse 2>/dev/null | awk '/^int:/ { print $2; exit }')"
    [[ -n "$follow_mouse" ]] || follow_mouse=1
    hyprctl keyword input:follow_mouse 0 >/dev/null 2>&1 || true
    /home/linmax/.config/hypr/hyprland/scripts/hypr_dispatch.sh moveworkspacetomonitor "$workspace" "$monitor" >/dev/null 2>&1 || true
    /home/linmax/.config/hypr/hyprland/scripts/hypr_dispatch.sh focusmonitor "$monitor" >/dev/null 2>&1 || true
    /home/linmax/.config/hypr/hyprland/scripts/hypr_dispatch.sh togglespecialworkspace "$(tv_special_short_name "$workspace")" >/dev/null 2>&1 || true
    /home/linmax/.config/hypr/hyprland/scripts/hypr_dispatch.sh moveworkspacetomonitor "$workspace" "$monitor" >/dev/null 2>&1 || true
    hyprctl keyword input:follow_mouse "$follow_mouse" >/dev/null 2>&1 || true
}

tv_toggle_special_on_focused_monitor() {
    local monitor

    monitor="$(tv_ensure_monitor)"
    tv_toggle_special_workspace_on_monitor "$(tv_special_selector)" "$monitor"
}

tv_hide_special_workspace_everywhere() {
    local workspace="$1"
    local visible

    for _ in $(seq 1 6); do
        visible="$(tv_visible_monitor_for_special_workspace "$workspace" || true)"
        [[ -n "$visible" ]] || return 0

        /home/linmax/.config/hypr/hyprland/scripts/hypr_dispatch.sh focusmonitor "$visible" >/dev/null 2>&1 || true
        tv_toggle_special_workspace_on_monitor "$workspace" "$visible" || true
        sleep 0.05
    done
}

tv_hide_special_everywhere() {
    local visible

    for _ in $(seq 1 6); do
        visible="$(tv_special_visible_monitor || true)"
        [[ -n "$visible" ]] || return 0

        /home/linmax/.config/hypr/hyprland/scripts/hypr_dispatch.sh focusmonitor "$visible" >/dev/null 2>&1 || true
        tv_toggle_special_workspace_on_monitor "$(tv_special_selector)" "$visible" || true
        sleep 0.05
    done
}

tv_hide_tv_workspaces_everywhere() {
    tv_hide_special_workspace_everywhere "$(tv_special_selector)"
    tv_hide_special_workspace_everywhere "special:tv-app"
}

tv_stop_tv_workspaces_without_monitor() {
    local tv_workspace

    tv_workspace="$(tv_special_selector)"
    tv_close_windows_on_workspace "$tv_workspace"
    tv_close_windows_on_workspace "special:tv-app"

    for _ in $(seq 1 20); do
        if ! tv_workspace_has_live_windows "$tv_workspace" && ! tv_workspace_has_live_windows "special:tv-app"; then
            break
        fi
        sleep 0.10
    done

    tv_hide_tv_workspaces_everywhere
    tv_clear_state
}

tv_show_special_workspace_on_monitor() {
    local workspace="$1"
    local monitor="$2"
    local currently_visible
    local target_visible

    tv_assign_special_workspace_rule "$monitor"
    /home/linmax/.config/hypr/hyprland/scripts/hypr_dispatch.sh moveworkspacetomonitor "$workspace" "$monitor" >/dev/null 2>&1 || true

    currently_visible="$(tv_visible_monitor_for_special_workspace "$workspace" || true)"
    if [[ "$currently_visible" == "$monitor" ]]; then
        return 0
    fi

    target_visible="$(tv_visible_special_on_monitor "$monitor" || true)"
    if [[ -n "$target_visible" && "$target_visible" != "$workspace" ]]; then
        tv_toggle_special_workspace_on_monitor "$target_visible" "$monitor" || true
        sleep 0.05
    fi

    if [[ -n "$currently_visible" ]]; then
        tv_hide_special_workspace_everywhere "$workspace"
    fi

    /home/linmax/.config/hypr/hyprland/scripts/hypr_dispatch.sh focusmonitor "$monitor" >/dev/null 2>&1 || true
    /home/linmax/.config/hypr/hyprland/scripts/hypr_dispatch.sh moveworkspacetomonitor "$workspace" "$monitor" >/dev/null 2>&1 || true
    if ! tv_monitor_has_special_workspace_visible "$monitor" "$workspace"; then
        tv_toggle_special_workspace_on_monitor "$workspace" "$monitor" || true
    fi

    currently_visible="$(tv_visible_monitor_for_special_workspace "$workspace" || true)"
    if [[ -n "$currently_visible" && "$currently_visible" != "$monitor" ]]; then
        tv_hide_special_workspace_everywhere "$workspace"
        tv_toggle_special_workspace_on_monitor "$workspace" "$monitor" || true
    fi
}

tv_show_special_on_monitor() {
    local monitor="$1"
    tv_show_special_workspace_on_monitor "$(tv_special_selector)" "$monitor"
}

tv_focus_monitor_center() {
    local monitor="$1"

    /home/linmax/.config/hypr/hyprland/scripts/hypr_dispatch.sh focusmonitor "$monitor" >/dev/null 2>&1 || true
}

tv_focus_window_on_monitor() {
    local address="$1"
    local monitor="$2"
    local fullscreen="${3:-false}"
    local follow_mouse
    local geometry cursor_json cursor_x cursor_y monitor_x monitor_y monitor_w monitor_h

    [[ -n "$address" ]] || return 0
    geometry="$(tv_monitor_geometry "$monitor")"
    [[ -n "$geometry" ]] || return 0
    read -r monitor_x monitor_y monitor_w monitor_h <<<"$geometry"

    cursor_json="$(hyprctl cursorpos -j 2>/dev/null || true)"
    cursor_x="$(jq -r '.x // empty' 2>/dev/null <<<"$cursor_json")"
    cursor_y="$(jq -r '.y // empty' 2>/dev/null <<<"$cursor_json")"
    if [[ -z "$cursor_x" || -z "$cursor_y" ]]; then
        read -r cursor_x cursor_y <<<"$(hyprctl cursorpos 2>/dev/null | tr -d ',')"
    fi
    [[ -n "$cursor_x" && -n "$cursor_y" ]] || return 0

    if (( cursor_x < monitor_x || cursor_x >= monitor_x + monitor_w || cursor_y < monitor_y || cursor_y >= monitor_y + monitor_h )); then
        return 0
    fi

    follow_mouse="$(hyprctl getoption input:follow_mouse 2>/dev/null | awk '/^int:/ { print $2; exit }')"
    [[ -n "$follow_mouse" ]] || follow_mouse=1
    hyprctl keyword input:follow_mouse 0 >/dev/null 2>&1 || true
    /home/linmax/.config/hypr/hyprland/scripts/hypr_dispatch.sh focusmonitor "$monitor" >/dev/null 2>&1 || true
    /home/linmax/.config/hypr/hyprland/scripts/hypr_dispatch.sh focuswindow "address:${address}" >/dev/null 2>&1 || true
    if [[ "$fullscreen" == "true" ]]; then
        /home/linmax/.config/hypr/hyprland/scripts/hypr_dispatch.sh fullscreenstate 2 2 >/dev/null 2>&1 || true
    fi
    hyprctl keyword input:follow_mouse "$follow_mouse" >/dev/null 2>&1 || true
}

tv_monitor_geometry() {
    local monitor="$1"

    tv_monitor_json | jq -r --arg name "$monitor" '
        map(select(.name == $name)) | first |
        if . then "\(.x) \(.y) \(.width) \(.height)" else empty end
    ' || true
}

tv_prepare_special_workspace() {
    local monitor="$1"

    tv_configure_monitor "$monitor"
    tv_assign_special_workspace_rule "$monitor"
    tv_show_special_on_monitor "$monitor"
}

tv_command_string() {
    local cmd_string
    printf -v cmd_string '%q ' "$@"
    printf '%s\n' "${cmd_string% }"
}

tv_list_client_addresses() {
    local match_regex="$1"
    local clients_json

    clients_json="$(tv_clients_json)" || return 0
    jq -r --arg match_regex "$match_regex" '
        .[] |
        select(
            ((.class // "") | test($match_regex)) or
            ((.initialClass // "") | test($match_regex)) or
            ((.title // "") | test($match_regex)) or
            ((.initialTitle // "") | test($match_regex))
        ) |
        .address
    ' 2>/dev/null <<<"$clients_json" | sort -u
}

tv_active_window_address() {
    local active_json

    active_json="$(tv_activewindow_json)" || return 0
    jq -r '.address // empty' 2>/dev/null <<<"$active_json"
}

tv_address_matches_regex() {
    local address="$1"
    local match_regex="$2"
    local clients_json

    clients_json="$(tv_clients_json)" || return 1
    jq -e --arg address "$address" --arg match_regex "$match_regex" '
        .[] |
        select(.address == $address) |
        select(
            ((.class // "") | test($match_regex)) or
            ((.initialClass // "") | test($match_regex)) or
            ((.title // "") | test($match_regex)) or
            ((.initialTitle // "") | test($match_regex))
        )
    ' >/dev/null 2>&1 <<<"$clients_json"
}

tv_select_matching_window_address() {
    local match_regex="$1"
    local workspace_name="${2:-}"
    local clients_json

    clients_json="$(tv_clients_json)" || return 0
    jq -r --arg match_regex "$match_regex" --arg workspace_name "$workspace_name" '
        [
            .[] |
            select(
                ((.class // "") | test($match_regex)) or
                ((.initialClass // "") | test($match_regex)) or
                ((.title // "") | test($match_regex)) or
                ((.initialTitle // "") | test($match_regex))
            ) |
            select($workspace_name == "" or .workspace.name == $workspace_name)
        ] |
        sort_by(.focusHistoryID // -1) |
        reverse |
        .[0].address // empty
    ' 2>/dev/null <<<"$clients_json"
}

tv_address_in_list() {
    local address="$1"
    local addresses="${2:-}"

    [[ -n "$address" ]] || return 1
    grep -Fqx "$address" <<<"$addresses"
}

tv_move_window_to_special() {
    local address="$1"
    /home/linmax/.config/hypr/hyprland/scripts/hypr_dispatch.sh movetoworkspacesilent "$(tv_special_selector),address:${address}" >/dev/null
}

tv_move_matching_windows_to_special() {
    local match_regex="$1"
    local address

    while IFS= read -r address; do
        [[ -z "$address" ]] && continue
        tv_move_window_to_special "$address"
    done < <(tv_list_client_addresses "$match_regex" || true)
}

tv_special_has_windows() {
    local clients_json

    clients_json="$(tv_clients_json)" || return 1
    jq -e --arg special "$(tv_special_selector)" '
        .[] | select(.workspace.name == $special)
    ' >/dev/null 2>&1 <<<"$clients_json"
}

tv_launch_and_move_to_special() {
    local monitor="$1"
    local match_regex="$2"
    shift 2

    local before before_active before_special after new_addresses address active_address special
    special="$(tv_special_selector)"

    before="$(tv_list_client_addresses "$match_regex" || true)"
    before_active="$(tv_active_window_address || true)"
    before_special="$(tv_select_matching_window_address "$match_regex" "$special" || true)"
    "$@" >/dev/null 2>&1 &

    for _ in $(seq 1 120); do
        after="$(tv_list_client_addresses "$match_regex" || true)"
        new_addresses="$(
            comm -13 \
                <(printf '%s\n' "$before" | sed '/^$/d') \
                <(printf '%s\n' "$after" | sed '/^$/d')
        )"

        if [[ -n "$new_addresses" ]]; then
            while IFS= read -r address; do
                [[ -z "$address" ]] && continue
                tv_move_window_to_special "$address"
            done <<<"$new_addresses"

            tv_show_special_on_monitor "$monitor"
            address="$(printf '%s\n' "$new_addresses" | tail -n 1)"
            tv_focus_window_on_monitor "$address" "$monitor"
            return 0
        fi

        address="$(tv_select_matching_window_address "$match_regex" "$special" || true)"
        if [[ -n "$before_special" && -n "$address" ]]; then
            tv_show_special_on_monitor "$monitor"
            tv_focus_window_on_monitor "$address" "$monitor"
            return 0
        fi

        active_address="$(tv_active_window_address || true)"
        if [[ -n "$active_address" ]] && tv_address_matches_regex "$active_address" "$match_regex"; then
            if [[ "$active_address" != "$before_active" ]] || ! tv_address_in_list "$active_address" "$before"; then
                tv_move_window_to_special "$active_address"
                tv_show_special_on_monitor "$monitor"
                tv_focus_window_on_monitor "$active_address" "$monitor"
                return 0
            fi
        fi

        sleep 0.10
    done

    tv_notify "TV mode" "Launched command but did not detect a new window for $(tv_special_selector)."
    return 1
}

tv_browser_command() {
    local browser="${1:-auto}"

    case "$browser" in
        chrome)
            [[ -x "$TV_CHROME_BIN" ]] && printf '%s\n' "$TV_CHROME_BIN" && return 0
            ;;
        auto)
            [[ -x "$TV_CHROME_BIN" ]] && printf '%s\n' "$TV_CHROME_BIN" && return 0
            ;;
    esac

    return 1
}
