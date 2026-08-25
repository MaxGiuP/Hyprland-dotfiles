#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <dispatcher> [args...]" >&2
    exit 2
fi

payload="$1"
shift

for arg in "$@"; do
    payload+=" $arg"
done

dispatcher="${payload%%[[:space:]]*}"
args="${payload#"$dispatcher"}"
args="${args#"${args%%[![:space:]]*}"}"

lua_quote() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '"%s"' "$value"
}

lua_workspace_value() {
    local value="$1"
    if [[ "$value" =~ ^[[:space:]]*([0-9]+)[[:space:]]*$ ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi
    lua_quote "$value"
}

ensure_hypr_env() {
    local runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    export XDG_RUNTIME_DIR="$runtime_dir"

    if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
        local instance_dir
        for instance_dir in "$runtime_dir"/hypr/*; do
            [[ -S "$instance_dir/.socket.sock" ]] || continue
            export HYPRLAND_INSTANCE_SIGNATURE="${instance_dir##*/}"
            break
        done
    fi
}

dispatch_lua() {
    ensure_hypr_env
    local output
    local status

    for _ in 1 2 3 4 5; do
        output="$(hyprctl dispatch "$1" 2>&1)"
        status=$?
        if [[ $status -eq 0 ]]; then
            printf '%s\n' "$output"
            exit 0
        fi

        if [[ "$output" != *"Couldn't set socket timeout"* ]]; then
            printf '%s\n' "$output" >&2
            exit "$status"
        fi

        sleep 0.05
    done

    printf '%s\n' "$output" >&2
    exit "$status"
}

numeric_pair_expr() {
    local value="$1"
    local prefix="${2:-}"
    if [[ "$value" =~ ^[[:space:]]*([+-]?[0-9]+)[[:space:]]+([+-]?[0-9]+)[[:space:]]*$ ]]; then
        printf '%sx = %s, y = %s' "$prefix" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
        return 0
    fi
    return 1
}

raw_dispatch() {
    local raw="$1"
    if [[ -n "${2:-}" ]]; then
        raw+=" $2"
    fi
    lua_payload="$(lua_quote "$raw")"
    dispatch_lua "hl.dsp.exec_raw($lua_payload)"
}

window_move_to_workspace() {
    local follow="$1"
    local workspace="$args"
    local selector=""

    if [[ "$args" == *,* ]]; then
        workspace="${args%%,*}"
        selector="${args#*,}"
    fi

    workspace_payload="$(lua_workspace_value "$workspace")"
    if [[ -n "$selector" ]]; then
        selector_payload="$(lua_quote "$selector")"
        if [[ "$follow" == "true" ]]; then
            dispatch_lua "hl.dsp.window.move({ workspace = $workspace_payload, window = $selector_payload, follow = true })"
        fi
        dispatch_lua "hl.dsp.window.move({ workspace = $workspace_payload, window = $selector_payload })"
    fi

    if [[ "$follow" == "true" ]]; then
        dispatch_lua "hl.dsp.window.move({ workspace = $workspace_payload, follow = true })"
    fi
    dispatch_lua "hl.dsp.window.move({ workspace = $workspace_payload })"
}

case "$dispatcher" in
    workspace)
        lua_payload="$(lua_workspace_value "$args")"
        dispatch_lua "hl.dsp.focus({ workspace = $lua_payload })"
        ;;
    movefocus)
        lua_payload="$(lua_quote "$args")"
        dispatch_lua "hl.dsp.focus({ direction = $lua_payload })"
        ;;
    focusmonitor)
        lua_payload="$(lua_quote "$args")"
        dispatch_lua "hl.dsp.focus({ monitor = $lua_payload })"
        ;;
    focuswindow)
        lua_payload="$(lua_quote "$args")"
        dispatch_lua "hl.dsp.focus({ window = $lua_payload })"
        ;;
    movetoworkspace)
        window_move_to_workspace true
        ;;
    movetoworkspacesilent)
        window_move_to_workspace false
        ;;
    movewindow)
        if [[ "$args" == mon:* ]]; then
            lua_payload="$(lua_quote "${args#mon:}")"
            dispatch_lua "hl.dsp.window.move({ monitor = $lua_payload })"
        fi
        lua_payload="$(lua_quote "$args")"
        dispatch_lua "hl.dsp.window.move({ direction = $lua_payload })"
        ;;
    swapwindow)
        lua_payload="$(lua_quote "$args")"
        dispatch_lua "hl.dsp.window.swap({ direction = $lua_payload })"
        ;;
    resizeactive)
        if [[ "$args" =~ ^[[:space:]]*exact[[:space:]]+([+-]?[0-9]+)[[:space:]]+([+-]?[0-9]+)[[:space:]]*$ ]]; then
            dispatch_lua "hl.dsp.window.resize({ x = ${BASH_REMATCH[1]}, y = ${BASH_REMATCH[2]} })"
        fi
        if resize_expr="$(numeric_pair_expr "$args" "relative = true, ")"; then
            dispatch_lua "hl.dsp.window.resize({ $resize_expr })"
        fi
        ;;
    movecursor)
        if cursor_expr="$(numeric_pair_expr "$args")"; then
            dispatch_lua "hl.dsp.cursor.move({ $cursor_expr })"
        fi
        ;;
    togglefloating)
        dispatch_lua "hl.dsp.window.float()"
        ;;
    fullscreen)
        mode="fullscreen"
        [[ "$args" == "1" ]] && mode="maximized"
        lua_payload="$(lua_quote "$mode")"
        dispatch_lua "hl.dsp.window.fullscreen({ mode = $lua_payload })"
        ;;
    fullscreenstate)
        if [[ "$args" =~ ^[[:space:]]*([+-]?[0-9]+)[[:space:]]+([+-]?[0-9]+)([[:space:]]+(set|unset|toggle))?[[:space:]]*$ ]]; then
            action="${BASH_REMATCH[4]:-}"
            if [[ -n "$action" ]]; then
                lua_payload="$(lua_quote "$action")"
                dispatch_lua "hl.dsp.window.fullscreen_state({ internal = ${BASH_REMATCH[1]}, client = ${BASH_REMATCH[2]}, action = $lua_payload })"
            fi
            dispatch_lua "hl.dsp.window.fullscreen_state({ internal = ${BASH_REMATCH[1]}, client = ${BASH_REMATCH[2]} })"
        fi
        ;;
    layoutmsg)
        lua_payload="$(lua_quote "$args")"
        dispatch_lua "hl.dsp.layout($lua_payload)"
        ;;
    togglesplit|swapsplit)
        lua_payload="$(lua_quote "$dispatcher")"
        dispatch_lua "hl.dsp.layout($lua_payload)"
        ;;
    workspaceopt)
        raw_dispatch "$dispatcher" "$args"
        ;;
    togglespecialworkspace)
        if [[ -n "$args" ]]; then
            lua_payload="$(lua_quote "$args")"
            dispatch_lua "hl.dsp.workspace.toggle_special($lua_payload)"
        fi
        dispatch_lua "hl.dsp.workspace.toggle_special()"
        ;;
    submap)
        lua_payload="$(lua_quote "$args")"
        dispatch_lua "hl.dsp.submap($lua_payload)"
        ;;
    killactive)
        dispatch_lua "hl.dsp.window.close()"
        ;;
    closewindow)
        lua_payload="$(lua_quote "$args")"
        dispatch_lua "hl.dsp.window.close({ window = $lua_payload })"
        ;;
    pin)
        dispatch_lua "hl.dsp.window.pin()"
        ;;
    cyclenext)
        dispatch_lua "hl.dsp.window.cycle_next()"
        ;;
    bringactivetotop)
        dispatch_lua "hl.dsp.window.bring_to_top()"
        ;;
    togglegroup)
        dispatch_lua "hl.dsp.group.toggle()"
        ;;
    exec)
        lua_payload="$(lua_quote "$args")"
        dispatch_lua "hl.dsp.exec_cmd($lua_payload)"
        ;;
    moveworkspacetomonitor|dpms|global)
        raw_dispatch "$dispatcher" "$args"
        ;;
    *)
        echo "Unsupported Hyprland Lua dispatcher bridge: $dispatcher $args" >&2
        exit 2
        ;;
esac
