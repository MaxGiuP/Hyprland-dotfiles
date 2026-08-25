local h = require("hyprland.lib")

-- Migrated from legacy/custom/execs.conf. Optional legacy custom module; not loaded by default.
local function exec_on_load(cmd)
    hl.on("hyprland.start", function()
        hl.exec_cmd(h.expand(cmd))
    end)
    hl.on("config.reloaded", function()
        hl.exec_cmd(h.expand(cmd))
    end)
end

-- Regular `exec` from hyprlang runs on config load/reload.
exec_on_load([[sh -c "~/.config/hypr/custom/scripts/combine_audio.sh"]])

-- Quickshell is started once from hyprland/execs.lua to avoid launch races.
h.exec_on_start("~/.config/hypr/custom/scripts/focus_primary_monitor.sh")
h.exec_on_start("~/.config/hypr/custom/scripts/set_primary_xwayland_monitor.sh")
