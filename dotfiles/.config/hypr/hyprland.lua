-- Hyprland 0.55+ Lua entrypoint.
-- The old hyprland.conf split is kept as a backup; Hyprland loads this file.

package.path = os.getenv("HOME") .. "/.config/hypr/?.lua;"
    .. os.getenv("HOME") .. "/.config/hypr/?/init.lua;"
    .. package.path

QS_CONFIG = "ii"

hl.define_submap("global", function()
    require("hyprland.keybinds")
    -- Optional additional keybinds kept for reference and cheatsheet parsing.
    -- keybinds.user.lua contains a literal dot in the filename, so use dofile instead of require.
    -- dofile(os.getenv("HOME") .. "/.config/hypr/hyprland/keybinds.user.lua")
end)

-- Keep interactive mouse dispatchers out of the named submap. Hyprland 0.55
-- otherwise registers them but never starts the move/resize operation.
local mouseBindOpts = {
    submap_universal = true,
    transparent = true,
    dont_inhibit = true,
}
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), mouseBindOpts)
hl.bind("SUPER + mouse:274", hl.dsp.window.drag(), mouseBindOpts)
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), mouseBindOpts)

local function restore_global_submap()
    hl.exec_cmd(os.getenv("HOME") .. "/.config/hypr/hyprland/scripts/restore_global_submap.sh")
end

hl.on("hyprland.start", restore_global_submap)
hl.on("config.reloaded", restore_global_submap)

require("hyprland.env")
require("hyprland.execs")
require("hyprland.general")
require("hyprland.peripherals")
require("hyprland.rules")
require("hyprland.colors")
-- Optional legacy custom overrides migrated to Lua; left disabled to preserve current behaviour.
-- require("hyprland.legacy.custom")
require("workspaces")
require("monitors")
