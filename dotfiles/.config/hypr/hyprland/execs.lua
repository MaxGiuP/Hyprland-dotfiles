local h = require("hyprland.lib")

-- Bar, wallpaper
h.exec_on_start("~/.config/hypr/hyprland/scripts/start_geoclue_agent.sh")
h.exec_on_start("~/.config/hypr/hyprland/scripts/__restore_video_wallpaper.sh")
h.exec_on_start("python3 ~/.config/quickshell/$qsConfig/scripts/colors/apply_gnome_accent.py")

-- Core components (authentication, lock screen, notification daemon)
h.exec_on_start("gnome-keyring-daemon --start --components=secrets")
h.exec_on_start("/usr/lib/pam_kwallet_init")
h.exec_on_start("dbus-update-activation-environment --all")
h.exec_on_start("sleep 1 && dbus-update-activation-environment --systemd DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE DBUS_SESSION_BUS_ADDRESS HYPRCURSOR_THEME HYPRCURSOR_SIZE")
h.exec_on_start("~/.config/hypr/hyprland/scripts/quickshell_restart_from_hyprland.sh $qsConfig")

-- Audio
h.exec_on_start("easyeffects --hide-window --service-mode")
h.exec_on_start("sh -c \"~/.config/hypr/hyprland/scripts/combine_audio.sh\"")
h.exec_on_start("~/.config/hypr/hyprland/scripts/start_input_remapper_mechlands_m75.sh")

-- Clipboard: history
-- h.exec_on_start("wl-paste --watch cliphist store &")
h.exec_on_start("wl-paste --type text --watch bash -c 'cliphist store && qs -c $qsConfig ipc call cliphistService update'")
h.exec_on_start("wl-paste --type image --watch bash -c 'cliphist store && qs -c $qsConfig ipc call cliphistService update'")

-- Cursor
h.exec_on_start("hyprctl setcursor Adwaita 32")

-- Monitor and XWayland follow-up
h.exec_on_start("~/.config/hypr/hyprland/scripts/focus_primary_monitor.sh")
h.exec_on_start("~/.config/hypr/hyprland/scripts/set_primary_xwayland_monitor.sh")

-- Fix dock pinned apps not launching properly (https://github.com/end-4/dots-hyprland/issues/2200)
-- This causes https://github.com/end-4/dots-hyprland/issues/2427
-- h.exec_on_start("sleep 3.5 && hyprctl reload && sleep 0.5 && touch ~/.config/quickshell/ii/shell.qml")
