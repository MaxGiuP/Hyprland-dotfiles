local h = require("hyprland.lib")
local bind = h.bind

-- # See https://wiki.hyprland.org/Configuring/Binds/
-- # This file is kept for reference and quickshell cheatsheet parsing.
-- # It is not sourced by hyprland.lua unless you uncomment it there.
-- #!
-- ##! User
bind([[Ctrl+Super]], [[Slash]], [[exec]], [[xdg-open ~/.config/illogical-impulse/config.json]], nil) -- Edit shell config
bind([[Ctrl+Super+Alt]], [[Slash]], [[exec]], [[xdg-open ~/.config/hypr/hyprland/keybinds.user.lua]], nil) -- Edit extra keybinds

-- # Add stuff here
-- # Use #! to add an extra column on the cheatsheet
-- # Use ##! to add a section in that column
-- # Add a comment after a bind to add a description, like above





-- #ML4W keybinds
-- # -----------------------------------------------------
-- # Key bindings
-- # name: "Default"
-- # -----------------------------------------------------

-- # SUPER KEY
-- $mainMod = SUPER
-- $HYPRSCRIPTS = ~/.config/hypr/hyprland/scripts
-- $SCRIPTS = ~/.config/hypr/hyprland/scripts

-- # Applications
bind([[Super]], [[RETURN]], [[exec]], [[~/.config/ml4w/settings/terminal.sh]], nil) -- Open the terminal
bind([[Super]], [[B]], [[exec]], [[~/.config/ml4w/settings/browser.sh]], nil) -- Open the browser
bind([[Super]], [[E]], [[exec]], [[~/.config/ml4w/settings/filemanager.sh]], nil) -- Open the filemanager
bind([[Super CTRL]], [[E]], [[exec]], [[~/.config/ml4w/settings/emojipicker.sh]], nil) -- Open the emoji picker
bind([[Super CTRL]], [[C]], [[exec]], [[~/.config/ml4w/settings/calculator.sh]], nil) -- Open the calculator

-- # Display
bind([[Super SHIFT]], [[mouse_down]], [[exec]], [[hyprctl keyword cursor:zoom_factor $(awk "BEGIN {print $(hyprctl getoption cursor:zoom_factor | grep 'float:' | awk '{print $2}') + 0.5}")]], nil) -- Increase display zoom
bind([[Super SHIFT]], [[mouse_up]], [[exec]], [[hyprctl keyword cursor:zoom_factor $(awk "BEGIN {print $(hyprctl getoption cursor:zoom_factor | grep 'float:' | awk '{print $2}') - 0.5}")]], nil) -- Decrease display zoom
bind([[Super SHIFT]], [[Z]], [[exec]], [[hyprctl keyword cursor:zoom_factor 1]], nil) -- Reset display zoom

-- # Windows
bind([[Super]], [[Q]], [[killactive]], [[]], nil) -- Kill active window
bind([[Super SHIFT]], [[Q]], [[exec]], [[hyprctl activewindow | grep pid | tr -d 'pid:' | xargs kill]], nil) -- Quit active window and all open instances
bind([[Super]], [[F]], [[fullscreen]], [[0]], nil) -- Set active window to fullscreen
bind([[Super]], [[M]], [[fullscreen]], [[1]], nil) -- Maximize Window
bind([[Super]], [[T]], [[togglefloating]], [[]], nil) -- Toggle active windows into floating mode
bind([[Super SHIFT]], [[T]], [[workspaceopt]], [[allfloat]], nil) -- Toggle all windows into floating mode
bind([[Super]], [[J]], [[togglesplit]], [[]], nil) -- Toggle split
bind([[Super]], [[left]], [[movefocus]], [[l]], nil) -- Move focus left
bind([[Super]], [[right]], [[movefocus]], [[r]], nil) -- Move focus right
bind([[Super]], [[up]], [[movefocus]], [[u]], nil) -- Move focus up
bind([[Super]], [[down]], [[movefocus]], [[d]], nil) -- Move focus down
bind([[Super]], [[mouse:272]], [[movewindow]], [[]], { mouse = true }) -- Move window with the mouse
bind([[Super]], [[mouse:273]], [[resizewindow]], [[]], { mouse = true }) -- Resize window with the mouse
bind([[Super SHIFT]], [[right]], [[resizeactive]], [[100 0]], nil) -- Increase window width with keyboard
bind([[Super SHIFT]], [[left]], [[resizeactive]], [[-100 0]], nil) -- Reduce window width with keyboard
bind([[Super SHIFT]], [[down]], [[resizeactive]], [[0 100]], nil) -- Increase window height with keyboard
bind([[Super SHIFT]], [[up]], [[resizeactive]], [[0 -100]], nil) -- Reduce window height with keyboard
bind([[Super]], [[G]], [[togglegroup]], [[]], nil) -- Toggle window group
bind([[Super]], [[K]], [[swapsplit]], [[]], nil) -- Swapsplit
bind([[Super ALT]], [[left]], [[swapwindow]], [[l]], nil) -- Swap tiled window left
bind([[Super ALT]], [[right]], [[swapwindow]], [[r]], nil) -- Swap tiled window right
bind([[Super ALT]], [[up]], [[swapwindow]], [[u]], nil) -- Swap tiled window up
bind([[Super ALT]], [[down]], [[swapwindow]], [[d]], nil) -- Swap tiled window down
bind([[ALT]], [[Tab]], [[cyclenext]], [[]], { repeating = true }) -- Cycle between windows
bind([[ALT]], [[Tab]], [[bringactivetotop]], [[]], { repeating = true }) -- Bring active window to the top

-- # Actions
bind([[Super CTRL]], [[R]], [[exec]], [[hyprctl reload]], nil) -- Reload Hyprland configuration
bind([[Super SHIFT]], [[A]], [[exec]], [[~/.config/hypr/hyprland/scripts/toggle-animations.sh]], nil) -- Toggle animations
bind([[Super]], [[PRINT]], [[exec]], [[~/.config/hypr/hyprland/scripts/screenshot.sh]], nil) -- Take a screenshot
bind([[Super ALT]], [[F]], [[exec]], [[~/.config/hypr/hyprland/scripts/screenshot.sh --instant]], nil) -- Take an instant full-screen screenshot
bind([[Super ALT]], [[S]], [[exec]], [[~/.config/hypr/hyprland/scripts/screenshot.sh --instant-area]], nil) -- Take an instant area screenshot
bind([[Super CTRL]], [[Q]], [[exec]], [[~/.config/ml4w/scripts/wlogout.sh]], nil) -- Start wlogout
bind([[Super SHIFT]], [[W]], [[exec]], [[waypaper --random]], nil) -- Change the wallpaper
bind([[Super CTRL]], [[W]], [[exec]], [[waypaper]], nil) -- Open wallpaper selector
bind([[Super ALT]], [[W]], [[exec]], [[~/.config/hypr/hyprland/scripts/wallpaper-automation.sh]], nil) -- Start random wallpaper script
bind([[Super CTRL]], [[RETURN]], [[exec]], [[pkill rofi || rofi -show drun -replace -i]], nil) -- Open application launcher
bind([[Super CTRL]], [[K]], [[exec]], [[~/.config/hypr/hyprland/scripts/keybindings.sh]], nil) -- Show keybindings
bind([[Super SHIFT]], [[B]], [[exec]], [[~/.config/waybar/launch.sh]], nil) -- Reload waybar
bind([[Super CTRL]], [[B]], [[exec]], [[~/.config/waybar/toggle.sh]], nil) -- Toggle waybar
bind([[Super SHIFT]], [[R]], [[exec]], [[~/.config/hypr/hyprland/scripts/loadconfig.sh]], nil) -- Reload hyprland config
bind([[Super]], [[V]], [[exec]], [[~/.config/hypr/hyprland/scripts/cliphist.sh]], nil) -- Open clipboard manager
bind([[Super CTRL]], [[T]], [[exec]], [[~/.config/waybar/themeswitcher.sh]], nil) -- Open waybar theme switcher
bind([[Super CTRL]], [[S]], [[exec]], [[flatpak run com.ml4w.settings]], nil) -- Open ML4W Dotfiles Settings app
bind([[Super ALT]], [[G]], [[exec]], [[~/.config/hypr/hyprland/scripts/gamemode.sh]], nil) -- Toggle game mode
bind([[Super CTRL]], [[L]], [[exec]], [[~/.config/hypr/scripts/power.sh lock]], nil) -- Launch Hyprshade
bind([[Super SHIFT]], [[H]], [[exec]], [[~/.config/hypr/hyprland/scripts/hyprshade.sh]], nil) -- Start wlogout
bind([[CTRL]], [[Tab]], [[exec]], [[~/.config/ml4w/scripts/focus.sh]], nil) -- Open Select Window Menu

-- # Sidepad
bind([[Super CTRL]], [[right]], [[exec]], [[~/.config/ml4w/scripts/sidepad.sh]], nil) -- Open Sidepad
bind([[Super CTRL]], [[left]], [[exec]], [[~/.config/ml4w/scripts/sidepad.sh --hide]], nil) -- Close Sidepad
bind([[Super]], [[S]], [[exec]], [[~/.config/ml4w/scripts/sidepad.sh --init]], nil) -- Init Sidepad
bind([[Super SHIFT]], [[S]], [[exec]], [[~/.config/ml4w/scripts/sidepad.sh --select]], nil) -- Select Sidepad

-- # Workspaces
bind([[Super]], [[1]], [[workspace]], [[r~1]], nil) -- Open workspace 1
bind([[Super]], [[2]], [[workspace]], [[r~2]], nil) -- Open workspace 2
bind([[Super]], [[3]], [[workspace]], [[r~3]], nil) -- Open workspace 3
bind([[Super]], [[4]], [[workspace]], [[r~4]], nil) -- Open workspace 4
bind([[Super]], [[5]], [[workspace]], [[r~5]], nil) -- Open workspace 5
bind([[Super]], [[6]], [[workspace]], [[r~6]], nil) -- Open workspace 6
bind([[Super]], [[7]], [[workspace]], [[r~7]], nil) -- Open workspace 7
bind([[Super]], [[8]], [[workspace]], [[r~8]], nil) -- Open workspace 8
bind([[Super]], [[9]], [[workspace]], [[r~9]], nil) -- Open workspace 9
bind([[Super]], [[0]], [[workspace]], [[r~10]], nil) -- Open workspace 10

bind([[Super SHIFT]], [[1]], [[movetoworkspace]], [[r~1]], nil) -- Move active window to workspace 1
bind([[Super SHIFT]], [[2]], [[movetoworkspace]], [[r~2]], nil) -- Move active window to workspace 2
bind([[Super SHIFT]], [[3]], [[movetoworkspace]], [[r~3]], nil) -- Move active window to workspace 3
bind([[Super SHIFT]], [[4]], [[movetoworkspace]], [[r~4]], nil) -- Move active window to workspace 4
bind([[Super SHIFT]], [[5]], [[movetoworkspace]], [[r~5]], nil) -- Move active window to workspace 5
bind([[Super SHIFT]], [[6]], [[movetoworkspace]], [[r~6]], nil) -- Move active window to workspace 6
bind([[Super SHIFT]], [[7]], [[movetoworkspace]], [[r~7]], nil) -- Move active window to workspace 7
bind([[Super SHIFT]], [[8]], [[movetoworkspace]], [[r~8]], nil) -- Move active window to workspace 8
bind([[Super SHIFT]], [[9]], [[movetoworkspace]], [[r~9]], nil) -- Move active window to workspace 9
bind([[Super SHIFT]], [[0]], [[movetoworkspace]], [[r~10]], nil) -- Move active window to workspace 10

-- # bind = $mainMod, Tab, workspace, m+1       # Open next workspace
-- # bind = $mainMod SHIFT, Tab, workspace, m-1 # Open previous workspace

bind([[Super CTRL]], [[1]], [[exec]], [[~/.config/hypr/hyprland/scripts/moveTo.sh 1]], nil) -- Move all windows to workspace 1
bind([[Super CTRL]], [[2]], [[exec]], [[~/.config/hypr/hyprland/scripts/moveTo.sh 2]], nil) -- Move all windows to workspace 2
bind([[Super CTRL]], [[3]], [[exec]], [[~/.config/hypr/hyprland/scripts/moveTo.sh 3]], nil) -- Move all windows to workspace 3
bind([[Super CTRL]], [[4]], [[exec]], [[~/.config/hypr/hyprland/scripts/moveTo.sh 4]], nil) -- Move all windows to workspace 4
bind([[Super CTRL]], [[5]], [[exec]], [[~/.config/hypr/hyprland/scripts/moveTo.sh 5]], nil) -- Move all windows to workspace 5
bind([[Super CTRL]], [[6]], [[exec]], [[~/.config/hypr/hyprland/scripts/moveTo.sh 6]], nil) -- Move all windows to workspace 6
bind([[Super CTRL]], [[7]], [[exec]], [[~/.config/hypr/hyprland/scripts/moveTo.sh 7]], nil) -- Move all windows to workspace 7
bind([[Super CTRL]], [[8]], [[exec]], [[~/.config/hypr/hyprland/scripts/moveTo.sh 8]], nil) -- Move all windows to workspace 8
bind([[Super CTRL]], [[9]], [[exec]], [[~/.config/hypr/hyprland/scripts/moveTo.sh 9]], nil) -- Move all windows to workspace 9
bind([[Super CTRL]], [[0]], [[exec]], [[~/.config/hypr/hyprland/scripts/moveTo.sh 10]], nil) -- Move all windows to workspace 10

bind([[Super]], [[mouse_down]], [[workspace]], [[e+1]], nil) -- Open next workspace
bind([[Super]], [[mouse_up]], [[workspace]], [[e-1]], nil) -- Open previous workspace
bind([[Super CTRL]], [[down]], [[workspace]], [[empty]], nil) -- Open the next empty workspace

-- # Fn keys
bind([[]], [[XF86MonBrightnessUp]], [[exec]], [[brightnessctl -q s +10%]], nil) -- Increase brightness by 10%
bind([[]], [[XF86MonBrightnessDown]], [[exec]], [[brightnessctl -q s 10%-]], nil) -- Reduce brightness by 10%
bind([[]], [[XF86AudioRaiseVolume]], [[exec]], [[wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 2%+]], { repeating = true, locked = true }) -- Increase volume by 5% (max 100% limit also added hold to raise volume)
bind([[]], [[XF86AudioLowerVolume]], [[exec]], [[wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-]], { repeating = true, locked = true }) -- Reduce volume by 5% (min 0% limit also added hold to lower volume)
bind([[]], [[XF86AudioMute]], [[exec]], [[pactl set-sink-mute @DEFAULT_SINK@ toggle]], nil) -- Toggle mute
bind([[]], [[XF86AudioPlay]], [[exec]], [[playerctl play-pause]], nil) -- Audio play pause
bind([[]], [[XF86AudioPause]], [[exec]], [[playerctl pause]], nil) -- Audio pause
bind([[]], [[XF86AudioNext]], [[exec]], [[playerctl next]], nil) -- Audio next
bind([[]], [[XF86AudioPrev]], [[exec]], [[playerctl previous]], nil) -- Audio previous
bind([[]], [[XF86AudioMicMute]], [[exec]], [[pactl set-source-mute @DEFAULT_SOURCE@ toggle]], nil) -- Toggle microphone
bind([[]], [[XF86Calculator]], [[exec]], [[~/.config/ml4w/settings/calculator.sh]], nil) -- Open calculator
bind([[]], [[XF86Lock]], [[exec]], [[~/.config/hypr/hyprland/scripts/lock_with_quickshell.sh ii]], nil) -- Open screenlock
bind([[]], [[XF86Tools]], [[exec]], [[flatpak run com.ml4w.settings]], nil) -- Open ML4W Dotfiles Settings app

bind([[]], [[code:238]], [[exec]], [[brightnessctl -d smc::kbd_backlight s +10]], nil)
bind([[]], [[code:237]], [[exec]], [[brightnessctl -d smc::kbd_backlight s 10-]], nil)
