local M = {}

local HOME = os.getenv("HOME") or "/home/linmax"

function M.qs_config()
    return rawget(_G, "QS_CONFIG") or "ii"
end

function M.expand(value)
    value = tostring(value or "")
    value = value:gsub("%$qsConfig", M.qs_config())
    value = value:gsub("%$HOME", HOME)
    value = value:gsub("^~", HOME)
    return value
end

local function shell_quote(value)
    value = M.expand(value)
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function bridge_dispatch(name, params)
    local cmd = shell_quote(HOME .. "/.config/hypr/hyprland/scripts/hypr_dispatch.sh") .. " " .. shell_quote(name)
    if params ~= "" then
        cmd = cmd .. " " .. shell_quote(params)
    end
    return hl.dsp.exec_cmd(cmd)
end

local function numeric_pair(params)
    local x, y = params:match("^%s*([+-]?%d+)%s+([+-]?%d+)%s*$")
    if not x then
        return nil
    end
    return tonumber(x), tonumber(y)
end

local function fullscreen_state_params(params)
    local internal, client, action = params:match("^%s*([+-]?%d+)%s+([+-]?%d+)%s*(%a*)%s*$")
    if not internal then
        return nil
    end
    if action == "" then
        action = nil
    elseif action ~= "set" and action ~= "unset" and action ~= "toggle" then
        return nil
    end
    return tonumber(internal), tonumber(client), action
end

local workspace_chord = {
    workspace_id = nil,
    monitor = nil,
    captured_at = 0,
}

local function current_workspace_context()
    local workspace = hl.get_active_workspace()
    local monitor = nil

    if workspace then
        monitor = workspace.monitor
    end

    if not monitor then
        monitor = hl.get_active_monitor()
    end

    if (not workspace) and monitor then
        workspace = monitor.active_workspace
    end

    if not workspace or not workspace.id or workspace.id <= 0 then
        return nil, monitor
    end

    return workspace.id, monitor
end

local function vector_xy(value)
    if type(value) ~= "table" then
        return nil, nil
    end

    return tonumber(value.x or value[1]), tonumber(value.y or value[2])
end

local focus_cursor_timer = nil

local function center_cursor_on_active_window()
    local window = hl.get_active_window()
    if not window then
        return
    end

    local window_x, window_y = vector_xy(window.at)
    local window_width, window_height = vector_xy(window.size)
    if not window_x or not window_y or not window_width or not window_height then
        return
    end

    hl.dispatch(hl.dsp.cursor.move({
        x = math.floor(window_x + window_width / 2),
        y = math.floor(window_y + window_height / 2),
    }))
end

function M.focus_and_center_cursor(direction)
    return function()
        hl.dispatch(hl.dsp.focus({ direction = direction }))

        if focus_cursor_timer then
            focus_cursor_timer:set_enabled(false)
        end

        focus_cursor_timer = hl.timer(function()
            center_cursor_on_active_window()
            focus_cursor_timer = nil
        end, { timeout = 16, type = "oneshot" })
    end
end

function M.capture_workspace_chord()
    return function()
        local workspace_id, monitor = current_workspace_context()
        workspace_chord.workspace_id = workspace_id
        workspace_chord.monitor = monitor
        workspace_chord.captured_at = os.clock()
    end
end

function M.clear_workspace_chord()
    return function()
        workspace_chord.workspace_id = nil
        workspace_chord.monitor = nil
        workspace_chord.captured_at = 0
    end
end

function M.workspace_slot(mode, slot)
    slot = tonumber(slot)

    return function()
        if not slot or slot < 1 or slot > 10 then
            return
        end

        if mode == "focus" then
            -- Resolve the monitor at keypress time from the pointer, rather than
            -- reusing the workspace captured when Super was first pressed.
            -- That capture can still refer to the monitor we just left.
            hl.exec_cmd(shell_quote(HOME .. "/.config/hypr/hyprland/scripts/workspace_number.sh")
                .. " focus " .. shell_quote(slot))
            return
        end

        local workspace_id = workspace_chord.workspace_id
        local monitor = workspace_chord.monitor
        if not workspace_id or (os.clock() - workspace_chord.captured_at) > 2 then
            workspace_id, monitor = current_workspace_context()
        end

        if not workspace_id then
            return
        end

        local base = math.floor((workspace_id - 1) / 10) * 10
        local target = tostring(base + slot)

        if mode == "move" then
            hl.dispatch(hl.dsp.window.move({ workspace = target }))
        elseif mode == "move-follow" then
            hl.dispatch(hl.dsp.window.move({ workspace = target, follow = true }))
        end
    end
end

function M.keyspec(mods, key)
    mods = M.expand(mods or "")
    key = M.expand(key or "")
    if key:lower() == "catchall" then
        return "catchall"
    end
    mods = mods:gsub("%+", " + "):gsub("%s+", " ")
    mods = mods:gsub("^%s+", ""):gsub("%s+$", "")
    if not mods:find("%+") then
        mods = mods:gsub("%s+", " + ")
    end
    mods = mods:gsub("%s+%+%s+", " + ")
    local normalized = {}
    local aliases = {
        super = "SUPER",
        ctrl = "CTRL",
        control = "CTRL",
        alt = "ALT",
        shift = "SHIFT",
    }
    for part in mods:gmatch("[^+]+") do
        local modifier = part:gsub("^%s+", ""):gsub("%s+$", "")
        local mapped = aliases[modifier:lower()] or modifier
        if mapped ~= "" then
            table.insert(normalized, mapped)
        end
    end
    mods = table.concat(normalized, " + ")
    if mods == "" then
        return key
    end
    return mods .. " + " .. key
end

function M.dispatcher(name, params, opts)
    name = tostring(name or "")
    params = M.expand(params or "")
    opts = opts or {}

    if name == "exec" then
        local dispatcher, dispatcher_params = params:match("^hyprctl%s+dispatch%s+([%w_]+)%s*(.*)$")
        if dispatcher then
            return M.dispatcher(dispatcher, dispatcher_params, opts)
        end
        return hl.dsp.exec_cmd(params)
    end
    if name == "global" then
        return hl.dsp.global(params)
    end
    if name == "workspace" then
        return hl.dsp.focus({ workspace = params })
    end
    if name == "movefocus" then
        return hl.dsp.focus({ direction = params })
    end
    if name == "focusmonitor" then
        return hl.dsp.focus({ monitor = params })
    end
    if name == "focuswindow" then
        return hl.dsp.focus({ window = params })
    end
    if name == "movetoworkspace" then
        local workspace, window = params:match("^([^,]+),(.+)$")
        if workspace and window then
            return hl.dsp.window.move({ workspace = workspace, window = window, follow = true })
        end
        return hl.dsp.window.move({ workspace = params, follow = true })
    end
    if name == "movetoworkspacesilent" then
        local workspace, window = params:match("^([^,]+),(.+)$")
        if workspace and window then
            return hl.dsp.window.move({ workspace = workspace, window = window })
        end
        return hl.dsp.window.move({ workspace = params })
    end
    if name == "layoutmsg" then
        return hl.dsp.layout(params)
    end
    if name == "togglesplit" or name == "swapsplit" then
        return hl.dsp.layout(name)
    end
    if name == "workspaceopt" then
        if params == "" then
            return hl.dsp.exec_raw(name)
        end
        return hl.dsp.exec_raw(name .. " " .. params)
    end
    if name == "movewindow" and opts.mouse then
        return hl.dsp.window.drag()
    end
    if name == "movewindow" then
        return hl.dsp.window.move({ direction = params })
    end
    if name == "resizewindow" and opts.mouse then
        return hl.dsp.window.resize()
    end
    if name == "resizeactive" then
        local exact_x, exact_y = params:match("^%s*exact%s+([+-]?%d+)%s+([+-]?%d+)%s*$")
        if exact_x then
            return hl.dsp.window.resize({ x = tonumber(exact_x), y = tonumber(exact_y) })
        end

        local x, y = numeric_pair(params)
        if x then
            return hl.dsp.window.resize({ x = x, y = y, relative = true })
        end

        return bridge_dispatch(name, params)
    end
    if name == "killactive" and params == "" then
        return hl.dsp.window.close()
    end
    if name == "togglefloating" then
        return hl.dsp.window.float()
    end
    if name == "fullscreen" then
        local mode = "fullscreen"
        if params == "1" then
            mode = "maximized"
        end
        return hl.dsp.window.fullscreen({ mode = mode })
    end
    if name == "fullscreenstate" then
        local internal, client, action = fullscreen_state_params(params)
        if internal then
            local state = { internal = internal, client = client }
            if action then
                state.action = action
            end
            return hl.dsp.window.fullscreen_state(state)
        end
        return bridge_dispatch(name, params)
    end
    if name == "pin" then
        return hl.dsp.window.pin()
    end
    if name == "togglegroup" then
        return hl.dsp.group.toggle()
    end
    if name == "swapwindow" then
        return hl.dsp.window.swap({ direction = params })
    end
    if name == "cyclenext" then
        return hl.dsp.window.cycle_next()
    end
    if name == "bringactivetotop" then
        return hl.dsp.window.bring_to_top()
    end
    if name == "togglespecialworkspace" then
        local special = params
        if special == "" then
            special = nil
        end
        return hl.dsp.workspace.toggle_special(special)
    end
    if name == "closewindow" then
        return hl.dsp.window.close({ window = params })
    end
    if name == "moveworkspacetomonitor" or name == "dpms" then
        if params == "" then
            return hl.dsp.exec_raw(name)
        end
        return hl.dsp.exec_raw(name .. " " .. params)
    end
    if name == "submap" then
        return hl.dsp.submap(params)
    end
    if name == "exit" then
        return hl.dsp.exit()
    end

    return bridge_dispatch(name, params)
end

local function bind_opts(opts)
    return opts or {}
end

function M.bind(mods, key, dispatcher, params, opts)
    opts = opts or {}
    local options = bind_opts(opts)
    if type(dispatcher) == "function" then
        return hl.bind(M.keyspec(mods, key), dispatcher, options)
    end
    return hl.bind(M.keyspec(mods, key), M.dispatcher(dispatcher, params, opts), options)
end

function M.exec_on_start(cmd)
    hl.on("hyprland.start", function()
        hl.exec_cmd(M.expand(cmd))
    end)
end

function M.window_rule(spec)
    return hl.window_rule(spec)
end

function M.layer_rule(spec)
    return hl.layer_rule(spec)
end

return M
