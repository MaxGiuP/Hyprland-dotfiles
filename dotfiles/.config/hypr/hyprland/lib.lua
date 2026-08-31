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

local function center_cursor_on_monitor(monitor)
    if not monitor then
        return false
    end

    local monitor_x = tonumber(monitor.x)
    local monitor_y = tonumber(monitor.y)
    local monitor_width = tonumber(monitor.width)
    local monitor_height = tonumber(monitor.height)
    if not monitor_x or not monitor_y or not monitor_width or not monitor_height then
        return false
    end

    hl.dispatch(hl.dsp.cursor.move({
        x = math.floor(monitor_x + monitor_width / 2),
        y = math.floor(monitor_y + monitor_height / 2),
    }))
    return true
end

local function center_cursor_on_window(window)
    if not window then
        return false
    end

    local window_x, window_y = vector_xy(window.at)
    local window_width, window_height = vector_xy(window.size)
    if not window_x or not window_y or not window_width or not window_height then
        return false
    end

    hl.dispatch(hl.dsp.cursor.move({
        x = math.floor(window_x + window_width / 2),
        y = math.floor(window_y + window_height / 2),
    }))
    return true
end

local function directional_monitor(source, direction)
    if not source then
        return nil
    end

    local source_x = tonumber(source.x)
    local source_y = tonumber(source.y)
    local source_width = tonumber(source.width)
    local source_height = tonumber(source.height)
    if not source_x or not source_y or not source_width or not source_height then
        return nil
    end

    local source_cx = source_x + source_width / 2
    local source_cy = source_y + source_height / 2
    local nearest = nil
    local nearest_distance = nil

    for _, candidate in ipairs(hl.get_monitors()) do
        if candidate.id ~= source.id then
            local candidate_x = tonumber(candidate.x)
            local candidate_y = tonumber(candidate.y)
            local candidate_width = tonumber(candidate.width)
            local candidate_height = tonumber(candidate.height)
            if candidate_x and candidate_y and candidate_width and candidate_height then
                local candidate_cx = candidate_x + candidate_width / 2
                local candidate_cy = candidate_y + candidate_height / 2
                local in_direction = (direction == "l" and candidate_cx < source_cx)
                    or (direction == "r" and candidate_cx > source_cx)
                    or (direction == "u" and candidate_cy < source_cy)
                    or (direction == "d" and candidate_cy > source_cy)

                if in_direction then
                    local dx = candidate_cx - source_cx
                    local dy = candidate_cy - source_cy
                    local distance = dx * dx + dy * dy
                    if not nearest_distance or distance < nearest_distance then
                        nearest = candidate
                        nearest_distance = distance
                    end
                end
            end
        end
    end

    return nearest
end

local function window_in_direction(window, monitor, direction)
    local workspace = monitor and hl.get_active_workspace(monitor) or nil
    if not window or not workspace or not window.workspace
        or window.workspace.id ~= workspace.id then
        return false
    end

    local window_x, window_y = vector_xy(window.at)
    local window_width, window_height = vector_xy(window.size)
    if not window_x or not window_y or not window_width or not window_height then
        return false
    end

    local window_cx = window_x + window_width / 2
    local window_cy = window_y + window_height / 2
    for _, candidate in ipairs(hl.get_workspace_windows(workspace)) do
        if candidate.address ~= window.address and candidate.mapped and not candidate.hidden then
            local candidate_x, candidate_y = vector_xy(candidate.at)
            local candidate_width, candidate_height = vector_xy(candidate.size)
            if candidate_x and candidate_y and candidate_width and candidate_height then
                local candidate_cx = candidate_x + candidate_width / 2
                local candidate_cy = candidate_y + candidate_height / 2
                if (direction == "l" and candidate_cx < window_cx)
                    or (direction == "r" and candidate_cx > window_cx)
                    or (direction == "u" and candidate_cy < window_cy)
                    or (direction == "d" and candidate_cy > window_cy) then
                    return true
                end
            end
        end
    end

    return false
end

local function workspace_focus_target(monitor)
    local workspace = monitor and hl.get_active_workspace(monitor) or nil
    if not workspace then
        return nil
    end

    local function is_target(window)
        return window and window.mapped and not window.hidden and window.workspace
            and window.workspace.id == workspace.id
    end

    if is_target(workspace.last_window) then
        return workspace.last_window
    end

    local target = nil
    for _, candidate in ipairs(hl.get_workspace_windows(workspace)) do
        if is_target(candidate) and (not target
            or candidate.focus_history_id < target.focus_history_id) then
            target = candidate
        end
    end

    return target
end

local function focus_monitor_target(monitor)
    local window = workspace_focus_target(monitor)
    if window then
        -- Focus the window explicitly instead of using the monitor center as a
        -- probe. The cursor dispatcher does not always make follow_mouse update
        -- the active window before the next Lua callback.
        hl.dispatch(hl.dsp.focus({ window = "address:" .. window.address }))
        center_cursor_on_window(window)
        return
    end

    -- An empty visible workspace has no focus target. Moving the pointer is
    -- still required so follow_mouse activates that monitor without recalling
    -- one of its hidden, occupied workspaces.
    center_cursor_on_monitor(monitor)
end

local function center_cursor_on_focus_target()
    local monitor = hl.get_active_monitor()
    local window = hl.get_active_window()

    -- An empty focused workspace has no active window of its own. Hyprland can
    -- still report the last window from the monitor we just left; warping to
    -- that window would let follow_mouse immediately steal focus back.
    if monitor and (not window or not window.monitor or window.monitor.id ~= monitor.id) then
        center_cursor_on_monitor(monitor)
        return
    end

    if not window then
        return
    end

    center_cursor_on_window(window)
end

function M.focus_and_center_cursor(direction)
    return function()
        local source_monitor = hl.get_active_monitor()
        local source_window = hl.get_active_window()
        local source_window_address = source_window and source_window.address or nil

        if focus_cursor_timer then
            focus_cursor_timer:set_enabled(false)
        end

        -- Directional window focus may select a window from a hidden workspace
        -- on the neighbouring monitor when its visible workspace is empty.
        -- Cross monitors explicitly so their currently visible workspace wins.
        local target_monitor = directional_monitor(source_monitor, direction)
        if target_monitor and not window_in_direction(source_window, source_monitor, direction) then
            focus_monitor_target(target_monitor)
            return
        end

        hl.dispatch(hl.dsp.focus({ direction = direction }))

        -- Focus dispatch is asynchronous.  Waiting two frames ensures the
        -- active-window query below sees the keyboard-selected window before
        -- follow_mouse evaluates the cursor position.
        focus_cursor_timer = hl.timer(function()
            local current_monitor = hl.get_active_monitor()
            local current_window = hl.get_active_window()
            local current_window_address = current_window and current_window.address or nil
            local monitor_changed = source_monitor and current_monitor
                and source_monitor.id ~= current_monitor.id
            local window_changed = source_window_address ~= current_window_address

            -- movefocus has no window to select on an empty neighbouring
            -- workspace. Fall back to the nearest monitor in that direction.
            if not monitor_changed and not window_changed then
                if target_monitor then
                    focus_monitor_target(target_monitor)
                    focus_cursor_timer = nil
                    return
                end
            end

            center_cursor_on_focus_target()
            focus_cursor_timer = nil
        end, { timeout = 32, type = "oneshot" })
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

        -- Resolve the workspace bank at keypress time from the intended monitor.
        -- Relative selectors can otherwise resolve against monitor 1.
        hl.exec_cmd(shell_quote(HOME .. "/.config/hypr/hyprland/scripts/workspace_number.sh")
            .. " " .. shell_quote(mode) .. " " .. shell_quote(slot))
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
