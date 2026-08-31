local h = require("hyprland.lib")
local raw_bind = h.bind

-- Swap Alt and Ctrl in every Super-modified bind.  Bindings containing both
-- modifiers are intentionally left alone: exchanging them would be a no-op.
local function bind(modifiers, ...)
    local has_super = modifiers:match("Super") ~= nil
    local has_alt = modifiers:match("Alt") ~= nil or modifiers:match("ALT") ~= nil
    local has_ctrl = modifiers:match("Ctrl") ~= nil or modifiers:match("CTRL") ~= nil

    if has_super and has_alt ~= has_ctrl then
        local swapped = {}
        for token in modifiers:gmatch("[^+%s]+") do
            local modifier = token
            if modifier == "Alt" or modifier == "ALT" then
                modifier = "Ctrl"
            elseif modifier == "Ctrl" or modifier == "CTRL" then
                modifier = "Alt"
            end
            table.insert(swapped, modifier)
        end
        modifiers = table.concat(swapped, "+")
    end

    return raw_bind(modifiers, ...)
end
local superSearchMenu = [[~/.config/hypr/hyprland/scripts/super_search_menu.sh]]

-- Drop bindings left behind by older Lua reloads before registering the
-- launcher interrupts below. Doing this later also removes those interrupts,
-- allowing Super+Arrow focus round trips to look like an untouched Super tap.
for _, direction_key in ipairs({ "Left", "Right", "Up", "Down" }) do
    hl.unbind("SUPER + " .. direction_key)
end

-- # Lines ending with `# [hidden]` won't be shown on cheatsheet
-- # Lines starting with #! are section headings

-- $mainMod = SUPER

-- #!
-- ##! Shell
-- # These absolutely need to be on top, or they won't work consistently
bind([[Super]], [[Super_L]], h.capture_workspace_chord(), nil, { transparent = true, ignore_mods = true, non_consuming = true }) -- [hidden]
bind([[Super]], [[Super_R]], h.capture_workspace_chord(), nil, { transparent = true, ignore_mods = true, non_consuming = true }) -- [hidden]
bind([[Super]], [[Super_L]], h.clear_workspace_chord(), nil, { release = true, transparent = true, ignore_mods = true, non_consuming = true }) -- [hidden]
bind([[Super]], [[Super_R]], h.clear_workspace_chord(), nil, { release = true, transparent = true, ignore_mods = true, non_consuming = true }) -- [hidden]
bind([[Super]], [[Super_L]], [[exec]], superSearchMenu .. [[ press]], { transparent = true, ignore_mods = true, description = [[Toggle search]] }) -- Toggle search
bind([[Super]], [[Super_R]], [[exec]], superSearchMenu .. [[ press]], { transparent = true, ignore_mods = true, description = [[Toggle search]] }) -- [hidden] Toggle search
bind([[Super]], [[Super_L]], [[exec]], superSearchMenu .. [[ release]], { release = true, transparent = true, ignore_mods = true }) -- [hidden]
bind([[Super]], [[Super_R]], [[exec]], superSearchMenu .. [[ release]], { release = true, transparent = true, ignore_mods = true }) -- [hidden]
for _, key in ipairs({
    [[Shift_L]], [[Shift_R]], [[Control_L]], [[Control_R]], [[Alt_L]], [[Alt_R]],
    [[Tab]], [[V]], [[A]], [[B]], [[O]], [[N]], [[S]], [[Slash]], [[K]], [[M]], [[G]], [[J]],
    [[Print]], [[Period]], [[Left]], [[Right]], [[Up]], [[Down]], [[BracketLeft]], [[BracketRight]],
    [[Q]], [[Space]], [[D]], [[F]], [[P]], [[R]], [[1]], [[2]], [[3]], [[4]], [[5]], [[6]],
    [[7]], [[8]], [[9]], [[0]], [[Page_Down]], [[Page_Up]], [[L]], [[Minus]], [[Equal]],
    [[Return]], [[T]], [[E]], [[W]], [[C]], [[X]], [[I]], [[Backslash]], [[backspace]],
    [[Semicolon]], [[Apostrophe]], [[code:62]], [[code:119]]
}) do
    bind([[Super]], key, [[exec]], superSearchMenu .. [[ cancel]], { non_consuming = true, transparent = true })
end
for _, mods in ipairs({ [[Shift]], [[Alt]], [[Ctrl]], [[Shift+Alt]], [[Ctrl+Shift]], [[Ctrl+Alt]], [[Ctrl+Shift+Alt]] }) do
    bind(mods, [[Super_L]], [[exec]], superSearchMenu .. [[ cancel]], { non_consuming = true, transparent = true }) -- [hidden]
    bind(mods, [[Super_R]], [[exec]], superSearchMenu .. [[ cancel]], { non_consuming = true, transparent = true }) -- [hidden]
end
local mouseWheelCancelOpts = { non_consuming = true, transparent = true }
bind([[Super]], [[mouse_up]], [[exec]], superSearchMenu .. [[ cancel]], mouseWheelCancelOpts) -- [hidden]
bind([[Super]], [[mouse_down]], [[exec]], superSearchMenu .. [[ cancel]], mouseWheelCancelOpts) -- [hidden]
bind([[]], [[mouse:272]], [[global]], [[quickshell:desktopDragMouseLeftRelease]], { release = true, non_consuming = true }) -- [hidden]

bind([[Super]], [[Super_L]], [[global]], [[quickshell:workspaceNumber]], { transparent = true, ignore_mods = true }) -- [hidden]
bind([[Super]], [[Super_R]], [[global]], [[quickshell:workspaceNumber]], { transparent = true, ignore_mods = true }) -- [hidden]
-- Super+Tab is reserved below for moving the active window between workspaces.
bind([[Super]], [[V]], [[global]], [[quickshell:overviewClipboardToggle]], { description = [[Clipboard history >> clipboard]] }) -- Clipboard history >> clipboard
-- #bindd = Super, Period, Emoji >> clipboard, global, quickshell:overviewEmojiToggle # Emoji >> clipboard
bind([[Super]], [[A]], [[global]], [[quickshell:sidebarLeftToggle]], nil) -- Toggle left sidebar
bind([[Super+Shift]], [[A]], [[global]], [[quickshell:sidebarLeftToggleExtend]], nil) -- Toggle left sidebar width
-- Modifiers are swapped by bind() above: these become Super+Shift+Ctrl and
-- Super+Alt respectively when registered with Hyprland.
bind([[Super+Shift+Alt]], [[A]], [[global]], [[quickshell:sidebarLeftToggleDetach]], nil) -- Detach left sidebar
bind([[Ctrl+Super]], [[A]], [[global]], [[quickshell:sidebarLeftTogglePin]], nil) -- Pin left sidebar
bind([[Super]], [[B]], [[global]], [[quickshell:sidebarLeftToggle]], nil) -- [hidden]
bind([[Super]], [[O]], [[global]], [[quickshell:sidebarLeftToggle]], nil) -- [hidden]
bind([[Super]], [[N]], [[global]], [[quickshell:sidebarRightToggle]], { description = [[Toggle right sidebar]] }) -- Toggle right sidebar
bind([[Super]], [[S]], [[global]], [[quickshell:sidebarRightToggle]], { description = [[Toggle right sidebar]] })
-- Modifiers are swapped by bind() above: these register as Super+Ctrl+N and
-- Super+Ctrl+Shift+N respectively.
bind([[Super+Alt]], [[N]], [[global]], [[quickshell:sidebarRightOpen]], { description = [[Open right sidebar]] })
bind([[Super+Shift+Alt]], [[N]], [[global]], [[quickshell:sidebarRightClose]], { description = [[Close right sidebar]] })
bind([[Super]], [[Slash]], [[global]], [[quickshell:cheatsheetToggle]], { description = [[Toggle cheatsheet]] }) -- Toggle cheatsheet
bind([[Super]], [[K]], [[global]], [[quickshell:oskToggle]], { description = [[Toggle on-screen keyboard]] }) -- Toggle on-screen keyboard

bind([[Super]], [[M]], [[global]], [[quickshell:mediaControlsToggle]], { description = [[Toggle media controls]] }) -- Toggle media controls
bind([[Super]], [[G]], [[global]], [[quickshell:overlayToggle]], nil) -- Toggle overlay
bind([[Ctrl+Alt]], [[Delete]], [[global]], [[quickshell:sessionToggle]], { description = [[Toggle session menu]] }) -- Toggle session menu
bind([[Super]], [[J]], [[global]], [[quickshell:barAutoHideToggle]], { description = [[Toggle bar]] }) -- Toggle bar
bind([[Ctrl+Alt]], [[Delete]], [[exec]], [[qs -c $qsConfig ipc call TEST_ALIVE || pkill wlogout || wlogout -p layer-shell]], nil) -- [hidden] Session menu (fallback)
bind([[Shift+Super+Alt]], [[Slash]], [[exec]], [[qs -p ~/.config/quickshell/$qsConfig/welcome.qml]], nil) -- [hidden] Launch welcome app

bind([[]], [[XF86MonBrightnessUp]], [[exec]], [[qs -c $qsConfig ipc call brightness increment || brightnessctl s 5%+]], { repeating = true, locked = true }) -- [hidden]
bind([[]], [[XF86MonBrightnessDown]], [[exec]], [[qs -c $qsConfig ipc call brightness decrement || brightnessctl s 5%-]], { repeating = true, locked = true }) -- [hidden]
bind([[]], [[XF86AudioRaiseVolume]], [[exec]], [[wpctl set-volume -l 2.5 @DEFAULT_AUDIO_SINK@ 2%+]], { repeating = true, locked = true }) -- [hidden]
bind([[]], [[XF86AudioLowerVolume]], [[exec]], [[wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-]], { repeating = true, locked = true }) -- [hidden]

bind([[]], [[XF86AudioMute]], [[exec]], [[wpctl set-mute @DEFAULT_SINK@ toggle]], { locked = true }) -- [hidden]
bind([[Super+Shift]], [[M]], [[exec]], [[wpctl set-mute @DEFAULT_SINK@ toggle]], { locked = true, description = [[Toggle mute]] }) -- [hidden]
bind([[Alt]], [[XF86AudioMute]], [[exec]], [[wpctl set-mute @DEFAULT_SOURCE@ toggle]], { locked = true }) -- [hidden]
bind([[]], [[XF86AudioMicMute]], [[exec]], [[wpctl set-mute @DEFAULT_SOURCE@ toggle]], { locked = true }) -- [hidden]
bind([[Super+Alt]], [[M]], [[exec]], [[wpctl set-mute @DEFAULT_SOURCE@ toggle]], { locked = true, description = [[Toggle mic]] }) -- [hidden]
bind([[Ctrl+Super]], [[T]], [[exec]], [[~/.config/quickshell/$qsConfig/scripts/colors/switchwall.sh]], { description = [[Change wallpaper]] }) -- Change wallpaper
bind([[Ctrl+Super]], [[R]], [[exec]], [[~/.config/hypr/hyprland/scripts/restart_quickshell.sh $qsConfig]], nil) -- Restart widgets

-- ##! Utilities
-- # Screenshot, Record, OCR, Color picker, Clipboard history
bind([[Super]], [[V]], [[exec]], [[qs -c $qsConfig ipc call TEST_ALIVE || pkill fuzzel || cliphist list | fuzzel --match-mode fzf --dmenu | cliphist decode | wl-copy]], { description = [[Copy clipboard history entry]] }) -- [hidden] Clipboard history >> clipboard (fallback)
bind([[Super]], [[Period]], [[exec]], [[qs -c $qsConfig ipc call TEST_ALIVE || pkill fuzzel || ~/.config/hypr/hyprland/scripts/fuzzel-emoji.sh copy]], { description = [[Copy an emoji]] }) -- [hidden] Emoji >> clipboard (fallback)
bind([[Super+Shift]], [[S]], [[exec]], [[qs -p ~/.config/quickshell/$qsConfig/screenshot.qml || pidof slurp || hyprshot --freeze --clipboard-only --mode region --silent]], { description = [[Screen snip]] }) -- Screen snip
-- # OCR
bind([[Super+Shift]], [[T]], [[exec]], [[grim -g "$(slurp $SLURP_ARGS)" "tmp.png" && tesseract "tmp.png" - | wl-copy && rm "tmp.png"]], { description = [[Character recognition]] }) -- [hidden]
-- # Color picker
bind([[Super+Shift]], [[C]], [[exec]], [[hyprpicker -a]], { description = [[Color picker]] }) -- Pick color (Hex) >> clipboard
-- # Fullscreen screenshot
bind([[SUPER]], [[code:119]], [[exec]], [[qs -p "$HOME/.config/quickshell/ii/screenshot.qml"]], nil)
bind([[Super]], [[Print]], [[exec]], [[grim - | wl-copy]], { locked = true, description = [[Screenshot >> clipboard]] }) -- Screenshot >> clipboard
bind([[Ctrl]], [[Print]], [[exec]], [[mkdir -p $(xdg-user-dir PICTURES)/Screenshots && grim $(xdg-user-dir PICTURES)/Screenshots/Screenshot_"$(date '+%Y-%m-%d_%H.%M.%S')".png]], { locked = true, description = [[Screenshot >> clipboard & save]] }) -- Screenshot >> clipboard & file
-- # Recording stuff
bind([[Super+Alt]], [[R]], [[exec]], [[~/.config/hypr/hyprland/scripts/record.sh]], { description = [[Record region (no sound)]] }) -- Record region (no sound)
bind([[Ctrl+Alt]], [[R]], [[exec]], [[~/.config/hypr/hyprland/scripts/record.sh --fullscreen]], { description = [[Record screen (no sound)]] }) -- [hidden] Record screen (no sound)
bind([[Super+Shift+Alt]], [[R]], [[exec]], [[~/.config/hypr/hyprland/scripts/record.sh --fullscreen-sound]], { description = [[Record screen (with sound)]] }) -- Record screen (with sound)
-- # AI
bind([[Super+Shift+Alt]], [[mouse:273]], [[exec]], [[~/.config/hypr/hyprland/scripts/ai/primary-buffer-query.sh]], { description = [[Generate AI summary for selected text]] }) -- AI summary for selected text

-- #!
-- ##! Window
-- # Focusing
-- Interactive mouse binds are registered at the root in hyprland.lua.
-- Hyprland 0.55 does not run these dispatchers correctly from a named submap.
-- #/# bind = Super, ←/↑/→/↓,, # Focus in direction
bind([[Super]], [[Left]], h.focus_and_center_cursor([[l]]), nil, nil) -- [hidden]
bind([[Super]], [[Right]], h.focus_and_center_cursor([[r]]), nil, nil) -- [hidden]
bind([[Super]], [[Up]], h.focus_and_center_cursor([[u]]), nil, nil) -- [hidden]
bind([[Super]], [[Down]], h.focus_and_center_cursor([[d]]), nil, nil) -- [hidden]
bind([[Super]], [[BracketLeft]], [[movefocus]], [[l]], nil) -- [hidden]
bind([[Super]], [[BracketRight]], [[movefocus]], [[r]], nil) -- [hidden]
-- #/# bind = Super+Shift, ←/↑/→/↓,, # Move in direction
bind([[Alt]], [[F4]], [[killactive]], [[]], nil) -- [hidden] Close (Windows)
bind([[Super]], [[Q]], [[killactive]], [[]], nil) -- Close
bind([[Super+Shift+Alt]], [[Q]], [[exec]], [[hyprctl kill]], nil) -- Forcefully zap a window

bind([[Super SHIFT]], [[left]], [[exec]], [[~/.config/hypr/hyprland/scripts/swap_or_move.sh l]], nil)
bind([[Super SHIFT]], [[right]], [[exec]], [[~/.config/hypr/hyprland/scripts/swap_or_move.sh r]], nil)
bind([[Super SHIFT]], [[up]], [[exec]], [[~/.config/hypr/hyprland/scripts/swap_or_move.sh u]], nil)
bind([[Super SHIFT]], [[down]], [[exec]], [[~/.config/hypr/hyprland/scripts/swap_or_move.sh d]], nil)

bind([[Super ALT]], [[right]], [[resizeactive]], [[50 0]], { repeating = true })
bind([[Super ALT]], [[left]], [[resizeactive]], [[-50 0]], { repeating = true })
bind([[Super ALT]], [[down]], [[resizeactive]], [[0 50]], { repeating = true })
bind([[Super ALT]], [[up]], [[resizeactive]], [[0 -50]], { repeating = true })

bind([[Super]], [[Tab]], [[movetoworkspace]], [[r+1]], nil) -- Move active window to next workspace
bind([[Super+Shift]], [[Tab]], [[movetoworkspace]], [[r-1]], nil) -- Move active window to previous workspace

bind([[SUPER]], [[backspace]], [[exec]], [[hyprctl switchxkblayout "input-remapper--------mechlands-m75-forwarded" next]], nil)




-- # Window split ratio
-- #/# binde = Super, ;/',, # Adjust split ratio
bind([[Super]], [[Semicolon]], [[layoutmsg]], [[splitratio -0.1]], { repeating = true }) -- [hidden]
bind([[Super]], [[Apostrophe]], [[layoutmsg]], [[splitratio +0.1]], { repeating = true }) -- [hidden]
-- # Positioning mode
bind([[Super]], [[Space]], [[togglefloating]], [[]], nil) -- Float/Tile
bind([[Super]], [[D]], [[fullscreenstate]], [[1 1 toggle]], nil) -- Maximize
bind([[Super]], [[F]], [[fullscreen]], [[0]], nil) -- Fullscreen
bind([[Super+Alt]], [[F]], [[fullscreenstate]], [[0 3]], nil) -- Fullscreen spoof
bind([[Super]], [[P]], [[exec]], [[mailspring]], { description = [[Open Mailspring]] })
bind([[Super]], [[code:62]], [[layoutmsg]], [[togglesplit]], nil)
bind([[Super]], [[R]], [[global]], [[quickshell:layoutSwitcherToggle]], nil) -- Choose window layout

-- #/# bind = Super+Shift, Hash,, # Send to workspace # (1, 2, 3,...)
for _, workspace in ipairs({
    { key = [[1]], id = 1 },
    { key = [[2]], id = 2 },
    { key = [[3]], id = 3 },
    { key = [[4]], id = 4 },
    { key = [[5]], id = 5 },
    { key = [[6]], id = 6 },
    { key = [[7]], id = 7 },
    { key = [[8]], id = 8 },
    { key = [[9]], id = 9 },
    { key = [[0]], id = 10 },
}) do
    bind([[Super+Shift]], workspace.key, h.workspace_slot([[move]], workspace.id), nil, nil) -- [hidden]
end

-- # #/# bind = Super+Shift, Scroll ↑/↓,, # Send to workspace left/right
bind([[Super+Shift]], [[mouse_down]], [[movetoworkspace]], [[r-1]], nil) -- [hidden]
bind([[Super+Shift]], [[mouse_up]], [[movetoworkspace]], [[r+1]], nil) -- [hidden]
bind([[Super+Alt]], [[mouse_down]], [[movetoworkspace]], [[-1]], nil) -- [hidden]
bind([[Super+Alt]], [[mouse_up]], [[movetoworkspace]], [[+1]], nil) -- [hidden]

-- #/# bind = Super+Shift, Page_↑/↓,, # Send to workspace left/right
bind([[Super+Alt]], [[Page_Down]], [[movetoworkspace]], [[+1]], nil) -- [hidden]
bind([[Super+Alt]], [[Page_Up]], [[movetoworkspace]], [[-1]], nil) -- [hidden]
bind([[Super+Shift]], [[Page_Down]], [[movetoworkspace]], [[r+1]], nil) -- [hidden]
bind([[Super+Shift]], [[Page_Up]], [[movetoworkspace]], [[r-1]], nil) -- [hidden]
bind([[Ctrl+Super+Shift]], [[Right]], [[movetoworkspace]], [[r+1]], nil) -- [hidden]
bind([[Ctrl+Super+Shift]], [[Left]], [[movetoworkspace]], [[r-1]], nil) -- [hidden]

bind([[Super+Alt]], [[S]], [[movetoworkspacesilent]], [[special]], nil) -- Send to scratchpad

bind([[Ctrl+Super]], [[S]], [[togglespecialworkspace]], [[]], nil) -- [hidden]
bind([[Alt]], [[Tab]], [[cyclenext]], [[]], nil) -- [hidden] sus keybind
bind([[Alt]], [[Tab]], [[bringactivetotop]], [[]], nil) -- [hidden] bring it to the top

-- ##! Workspace
-- # Switching
-- #/# bind = Super, Hash,, # Focus workspace # (1, 2, 3,...)
for _, workspace in ipairs({
    { key = [[1]], id = 1 },
    { key = [[2]], id = 2 },
    { key = [[3]], id = 3 },
    { key = [[4]], id = 4 },
    { key = [[5]], id = 5 },
    { key = [[6]], id = 6 },
    { key = [[7]], id = 7 },
    { key = [[8]], id = 8 },
    { key = [[9]], id = 9 },
    { key = [[0]], id = 10 },
}) do
    bind([[Super]], workspace.key, [[global]], [[quickshell:workspacePreview]] .. workspace.id, { non_consuming = true, transparent = true }) -- [hidden]
end

for _, workspace in ipairs({
    { key = [[1]], id = 1 },
    { key = [[2]], id = 2 },
    { key = [[3]], id = 3 },
    { key = [[4]], id = 4 },
    { key = [[5]], id = 5 },
    { key = [[6]], id = 6 },
    { key = [[7]], id = 7 },
    { key = [[8]], id = 8 },
    { key = [[9]], id = 9 },
    { key = [[0]], id = 10 },
}) do
    bind([[Super]], workspace.key, h.workspace_slot([[focus]], workspace.id), nil, nil) -- [hidden]
end

-- #/# bind = Ctrl+Super, ←/→,, # Focus left/right
bind([[Ctrl+Super]], [[Right]], [[workspace]], [[r+1]], nil) -- [hidden]
bind([[Ctrl+Super]], [[Left]], [[workspace]], [[r-1]], nil) -- [hidden]
-- #/# bind = Ctrl+Super+Alt, ←/→,, # [hidden] Focus busy left/right
bind([[Ctrl+Super+Alt]], [[Right]], [[workspace]], [[m+1]], nil) -- [hidden]
bind([[Ctrl+Super+Alt]], [[Left]], [[workspace]], [[m-1]], nil) -- [hidden]
-- #/# bind = Super, Page_↑/↓,, # Focus left/right
bind([[Super]], [[Page_Down]], [[workspace]], [[+1]], nil) -- [hidden]
bind([[Super]], [[Page_Up]], [[workspace]], [[-1]], nil) -- [hidden]
bind([[Ctrl+Super]], [[Page_Down]], [[workspace]], [[r+1]], nil) -- [hidden]
bind([[Ctrl+Super]], [[Page_Up]], [[workspace]], [[r-1]], nil) -- [hidden]
-- #/# bind = Super, Scroll ↑/↓,, # Focus left/right

bind([[Super]], [[mouse_up]], [[workspace]], [[r+1]], nil) -- [hidden]
bind([[Super]], [[mouse_down]], [[workspace]], [[r-1]], nil) -- [hidden]

bind([[Ctrl+Super]], [[mouse_up]], [[workspace]], [[r+1]], nil) -- [hidden]
bind([[Ctrl+Super]], [[mouse_down]], [[workspace]], [[r-1]], nil) -- [hidden]
-- ## Special
-- ## bind = Super, S, togglespecialworkspace, # Toggle scratchpad
bind([[Super]], [[mouse:275]], [[togglespecialworkspace]], [[]], nil) -- [hidden]
bind([[Ctrl+Super]], [[BracketLeft]], [[workspace]], [[-1]], nil) -- [hidden]
bind([[Ctrl+Super]], [[BracketRight]], [[workspace]], [[+1]], nil) -- [hidden]
bind([[Ctrl+Super]], [[Up]], [[workspace]], [[r-5]], nil) -- [hidden]
bind([[Ctrl+Super]], [[Down]], [[workspace]], [[r+5]], nil) -- [hidden]

-- #!
-- # Testing
bind([[Super+Alt]], [[f11]], [[exec]], [=[bash -c 'RANDOM_IMAGE=$(find ~/Pictures -type f | grep -v -i "nipple" | grep -v -i "pussy" | shuf -n 1); ACTION=$(notify-send "Test notification with body image" "This notification should contain your user account <b>image</b> and <a href=\"https://discord.com/app\">Discord</a> <b>icon</b>. Oh and here is a random image in your Pictures folder: <img src=\"$RANDOM_IMAGE\" alt=\"Testing image\"/>" -a "Hyprland keybind" -p -h "string:image-path:/var/lib/AccountsService/icons/$USER" -t 6000 -i "discord" -A "openImage=Open profile image" -A "action2=Open the random image" -A "action3=Useless button"); [[ $ACTION == *openImage ]] && xdg-open "/var/lib/AccountsService/icons/$USER"; [[ $ACTION == *action2 ]] && xdg-open \"$RANDOM_IMAGE\"']=], nil) -- [hidden]
bind([[Super+Alt]], [[f12]], [[exec]], [=[bash -c 'RANDOM_IMAGE=$(find ~/Pictures -type f | grep -v -i "nipple" | grep -v -i "pussy" | shuf -n 1); ACTION=$(notify-send "Test notification" "This notification should contain a random image in your <b>Pictures</b> folder and <a href=\"https://discord.com/app\">Discord</a> <b>icon</b>.\n<i>Flick right to dismiss!</i>" -a "Discord (fake)" -p -h "string:image-path:$RANDOM_IMAGE" -t 6000 -i "discord" -A "openImage=Open profile image" -A "action2=Useless button" -A "action3=Cry more"); [[ $ACTION == *openImage ]] && xdg-open "/var/lib/AccountsService/icons/$USER"']=], nil) -- [hidden]
bind([[Super+Alt]], [[Equal]], [[exec]], [[notify-send "Urgent notification" "Ah hell no" -u critical -a 'Hyprland keybind']], nil) -- [hidden]

-- ##! Session
bind([[Super]], [[L]], [[exec]], [[~/.config/hypr/hyprland/scripts/lock_with_quickshell.sh $qsConfig]], { description = [[Lock]] }) -- Lock
bind([[Super+Shift]], [[L]], [[exec]], [[~/.config/hypr/hyprland/scripts/lock_with_quickshell.sh $qsConfig]], nil) -- [hidden]
bind([[Super+Shift]], [[L]], [[exec]], [[sleep 0.1 && systemctl suspend || loginctl suspend]], { locked = true, description = [[Suspend system]] }) -- Sleep
bind([[Ctrl+Shift+Alt+Super]], [[Delete]], [[exec]], [[systemctl poweroff || loginctl poweroff]], { description = [[Shutdown]] }) -- [hidden] Power off

-- ##! Screen
-- # Zoom
bind([[Super]], [[Minus]], [[exec]], [[qs -c $qsConfig ipc call zoom zoomOut]], { repeating = true }) -- Zoom out
bind([[Super]], [[Equal]], [[exec]], [[qs -c $qsConfig ipc call zoom zoomIn]], { repeating = true }) -- Zoom in
bind([[Super]], [[Minus]], [[exec]], [[qs -c $qsConfig ipc call TEST_ALIVE || ~/.config/hypr/hyprland/scripts/zoom.sh decrease 0.1]], { repeating = true }) -- [hidden] Zoom out
bind([[Super]], [[Equal]], [[exec]], [[qs -c $qsConfig ipc call TEST_ALIVE || ~/.config/hypr/hyprland/scripts/zoom.sh increase 0.1]], { repeating = true }) -- [hidden] Zoom in

-- ##! Media
bind([[Super+Shift]], [[N]], [[exec]], [[playerctl next || playerctl position `bc <<< "100 * $(playerctl metadata mpris:length) / 1000000 / 100"`]], { locked = true }) -- Next track
bind([[]], [[XF86AudioNext]], [[exec]], [[playerctl next || playerctl position `bc <<< "100 * $(playerctl metadata mpris:length) / 1000000 / 100"`]], { locked = true }) -- [hidden]
bind([[]], [[XF86AudioPrev]], [[exec]], [[playerctl previous]], { locked = true }) -- [hidden]
bind([[Super+Shift+Alt]], [[mouse:275]], [[exec]], [[playerctl previous]], nil) -- [hidden]
bind([[Super+Shift+Alt]], [[mouse:276]], [[exec]], [[playerctl next || playerctl position `bc <<< "100 * $(playerctl metadata mpris:length) / 1000000 / 100"`]], nil) -- [hidden]
bind([[Super+Shift]], [[B]], [[exec]], [[playerctl previous]], { locked = true }) -- Previous track
bind([[Super+Shift]], [[P]], [[exec]], [[playerctl play-pause]], { locked = true }) -- Play/pause media
bind([[]], [[XF86AudioPlay]], [[exec]], [[playerctl play-pause]], { locked = true }) -- [hidden]
bind([[]], [[XF86AudioPause]], [[exec]], [[playerctl play-pause]], { locked = true }) -- [hidden]

-- ##! Apps
bind([[Super]], [[Return]], [[exec]], [[~/.config/hypr/hyprland/scripts/launch_first_available.sh "kitty -1" "foot" "alacritty" "wezterm" "konsole" "kgx" "uxterm" "xterm"]], nil) -- Terminal
bind([[Super]], [[T]], [[exec]], [[gnome-text-editor]], { description = [[Open text editor]] })
bind([[Ctrl+Alt]], [[T]], [[exec]], [[~/.config/hypr/hyprland/scripts/launch_first_available.sh "kitty -1" "foot" "alacritty" "wezterm" "konsole" "kgx" "uxterm" "xterm"]], nil) -- [hidden] Kitty (for Ubuntu people)
bind([[Super]], [[E]], [[exec]], [[~/.config/hypr/hyprland/scripts/launch_first_available.sh "dolphin" "org.kde.dolphin" "nautilus --new-window" "pcmanfm-qt" "nemo" "thunar" "kitty -1 fish -c yazi"]], nil) -- File manager
bind([[Super]], [[W]], [[exec]], [[~/.config/hypr/hyprland/scripts/launch_first_available.sh "brave" "google-chrome-stable" "zen-browser" "firefox" "chromium" "microsoft-edge-stable" "opera" "librewolf"]], nil) -- Browser
bind([[Super+Shift]], [[G]], [[exec]], [[~/.config/hypr/hyprland/scripts/tv_mode/start.sh]], { description = [[Start TV mode]] }) -- Start TV mode
bind([[Super]], [[C]], [[exec]], [[gtk-launch nvim]], { description = [[Open Neovim]] })
bind([[Super+Shift]], [[W]], [[exec]], [[~/.config/hypr/hyprland/scripts/launch_first_available.sh "wps" "onlyoffice-desktopeditors"]], nil) -- Office software
bind([[Super]], [[X]], [[exec]], [[code]], { description = [[Open VS Code]] })
bind([[Ctrl+Super]], [[V]], [[exec]], [[~/.config/hypr/hyprland/scripts/launch_first_available.sh "pavucontrol-qt" "pavucontrol"]], nil) -- Volume mixer
bind([[Super]], [[I]], [[exec]], [[~/.config/hypr/hyprland/scripts/launch_quickshell_settings.sh]], nil) -- Settings app
bind([[Ctrl+Shift]], [[Escape]], [[exec]], [[~/.config/hypr/hyprland/scripts/launch_first_available.sh "plasma-systemmonitor" "gnome-system-monitor --page-name Processes" "command -v btop && kitty -1 fish -c btop"]], nil) -- Task manager

-- # Cursed stuff
-- ## Make window not amogus large
bind([[Ctrl+Super]], [[Backslash]], [[resizeactive]], [[exact 640 480]], nil) -- [hidden]
