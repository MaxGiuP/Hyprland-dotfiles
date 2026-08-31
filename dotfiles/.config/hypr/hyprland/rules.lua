local h = require("hyprland.lib")
local window_rule = h.window_rule
local layer_rule = h.layer_rule

-- # ######## Window rules ########

-- # Disable blur for xwayland context menus
window_rule({
    match = {
        class = [[^()$]],
        title = [[^()$]],
    },
    no_blur = true,
})

-- # Frosted glass for app windows.
window_rule({
    match = {
        class = [[.*]],
    },
    no_blur = false,
})
window_rule({
    match = {
        class = [[.*]],
    },
    opacity = [[0.99 0.96]],
})

-- # Extra glass for apps that benefit from more wallpaper bleed-through.
window_rule({
    match = {
        class = [[^(kitty)$]],
    },
    opacity = [[0.90 0.90]],
})
window_rule({
    match = {
        class = [[^(foot|Alacritty|alacritty|org\.wezfurlong\.wezterm|com\.mitchellh\.ghostty)$]],
    },
    opacity = [[0.95 0.95]],
})
window_rule({
    match = {
        class = [[^(codium|Codium|VSCodium|Code|code|code-url-handler|codium-url-handler)$]],
    },
    opacity = [[0.95 0.95]],
})
window_rule({
    match = {
        class = [[^(Mailspring|mailspring)$]],
    },
    opacity = [[0.95 0.95]],
})
window_rule({
    match = {
        class = [[^(org\.kde\.dolphin|dolphin|Dolphin)$]],
    },
    opacity = [[0.95 0.95]],
})

-- # Floating
window_rule({
    match = {
        title = [[^(Open File)(.*)$]],
    },
    center = true,
})
window_rule({
    match = {
        title = [[^(Open File)(.*)$]],
    },
    float = true,
})
window_rule({
    match = {
        title = [[^(Select a File)(.*)$]],
    },
    center = true,
})
window_rule({
    match = {
        title = [[^(Select a File)(.*)$]],
    },
    float = true,
})
window_rule({
    match = {
        title = [[^(Choose wallpaper)(.*)$]],
    },
    center = true,
})
window_rule({
    match = {
        title = [[^(Choose wallpaper)(.*)$]],
    },
    float = true,
})
window_rule({
    match = {
        title = [[^(Choose wallpaper)(.*)$]],
    },
    size = [[(monitor_w*.60) (monitor_h*.65)]],
})
window_rule({
    match = {
        title = [[^(Open Folder)(.*)$]],
    },
    center = true,
})
window_rule({
    match = {
        title = [[^(Open Folder)(.*)$]],
    },
    float = true,
})
window_rule({
    match = {
        title = [[^(Save As)(.*)$]],
    },
    center = true,
})
window_rule({
    match = {
        title = [[^(Save As)(.*)$]],
    },
    float = true,
})
window_rule({
    match = {
        title = [[^(Library)(.*)$]],
    },
    center = true,
})
window_rule({
    match = {
        title = [[^(Library)(.*)$]],
    },
    float = true,
})
window_rule({
    match = {
        title = [[^(File Upload)(.*)$]],
    },
    center = true,
})
window_rule({
    match = {
        title = [[^(File Upload)(.*)$]],
    },
    float = true,
})
window_rule({
    match = {
        title = [[^(.*)(wants to save)$]],
    },
    center = true,
})
window_rule({
    match = {
        title = [[^(.*)(wants to save)$]],
    },
    float = true,
})
window_rule({
    match = {
        title = [[^(.*)(wants to open)$]],
    },
    center = true,
})
window_rule({
    match = {
        title = [[^(.*)(wants to open)$]],
    },
    float = true,
})
window_rule({
    match = {
        class = [[^(blueberry\.py)$]],
    },
    float = true,
})
window_rule({
    match = {
        class = [[^(guifetch)$]],
    },
    float = true,
}) -- FlafyDev/guifetch
window_rule({
    match = {
        class = [[^(pavucontrol)$]],
    },
    float = true,
})
window_rule({
    match = {
        class = [[^(pavucontrol)$]],
    },
    size = [[(monitor_w*.45) (monitor_h*.45)]],
})
window_rule({
    match = {
        class = [[^(pavucontrol)$]],
    },
    center = true,
})
window_rule({
    match = {
        class = [[^(org.pulseaudio.pavucontrol)$]],
    },
    float = true,
})
window_rule({
    match = {
        class = [[^(org.pulseaudio.pavucontrol)$]],
    },
    size = [[(monitor_w*.45) (monitor_h*.45)]],
})
window_rule({
    match = {
        class = [[^(org.pulseaudio.pavucontrol)$]],
    },
    center = true,
})
window_rule({
    match = {
        class = [[^(nm-connection-editor)$]],
    },
    float = true,
})
window_rule({
    match = {
        class = [[^(nm-connection-editor)$]],
    },
    size = [[(monitor_w*.45) (monitor_h*.45)]],
})
window_rule({
    match = {
        class = [[^(nm-connection-editor)$]],
    },
    center = true,
})
window_rule({
    match = {
        class = [[.*plasmawindowed.*]],
    },
    float = true,
})
window_rule({
    match = {
        class = [[kcm_.*]],
    },
    float = true,
})
window_rule({
    match = {
        class = [[.*bluedevilwizard]],
    },
    float = true,
})
window_rule({
    match = {
        title = [[.*Welcome]],
    },
    float = true,
})
window_rule({
    match = {
        title = [[^(.*illogical-impulse.*)$]],
    },
    float = true,
})
window_rule({
    match = {
        title = [[.*Shell conflicts.*]],
    },
    float = true,
})
window_rule({
    match = {
        class = [[org.freedesktop.impl.portal.desktop.kde]],
    },
    float = true,
})
window_rule({
    match = {
        class = [[org.freedesktop.impl.portal.desktop.kde]],
    },
    size = [[(monitor_w*.60) (monitor_h*.65)]],
})
window_rule({
    match = {
        class = [[^(Zotero)$]],
    },
    float = true,
})
window_rule({
    match = {
        class = [[^(Zotero)$]],
    },
    size = [[(monitor_w*.45) (monitor_h*.45)]],
})
window_rule({
    match = {
        class = [[^(kitty)$]],
    },
    center = true,
})
window_rule({
    match = {
        class = [[^(codium)$]],
    },
    no_blur = false,
})

-- # Move
-- # kde-material-you-colors spawns a window when changing dark/light theme. This is to make sure it doesn't interfere at all.
window_rule({
    match = {
        class = [[^(plasma-changeicons)$]],
    },
    float = true,
})
window_rule({
    match = {
        class = [[^(plasma-changeicons)$]],
    },
    no_initial_focus = true,
})
window_rule({
    match = {
        class = [[^(plasma-changeicons)$]],
    },
    move = [[999999 999999]],
})
-- # stupid dolphin copy
window_rule({
    match = {
        title = [[^(Copying — Dolphin)$]],
    },
    move = [[40 80]],
})

-- # Tiling
window_rule({
    match = {
        class = [[^dev\.warp\.Warp$]],
    },
    tile = true,
})

-- # Picture-in-Picture
window_rule({
    match = {
        title = [[^([Pp]icture[-\s]?[Ii]n[-\s]?[Pp]icture)(.*)$]],
    },
    float = true,
})
window_rule({
    match = {
        title = [[^([Pp]icture[-\s]?[Ii]n[-\s]?[Pp]icture)(.*)$]],
    },
    keep_aspect_ratio = true,
})
window_rule({
    match = {
        title = [[^([Pp]icture[-\s]?[Ii]n[-\s]?[Pp]icture)(.*)$]],
    },
    move = [[(monitor_w*.73) (monitor_h*.72)]],
})
window_rule({
    match = {
        title = [[^([Pp]icture[-\s]?[Ii]n[-\s]?[Pp]icture)(.*)$]],
    },
    size = [[(monitor_w*.25) (monitor_h*.25)]],
})
window_rule({
    match = {
        title = [[^([Pp]icture[-\s]?[Ii]n[-\s]?[Pp]icture)(.*)$]],
    },
    float = true,
})
window_rule({
    match = {
        title = [[^([Pp]icture[-\s]?[Ii]n[-\s]?[Pp]icture)(.*)$]],
    },
    pin = true,
})

-- # --- Tearing ---
window_rule({
    match = {
        title = [[.*\.exe]],
    },
    immediate = true,
})
window_rule({
    match = {
        title = [[.*minecraft.*]],
    },
    immediate = true,
})
window_rule({
    match = {
        class = [[^(steam_app).*]],
    },
    immediate = true,
})

-- # Steam: center floating bootstrap/login/update dialogs on the TV instead of
-- # leaving them in a corner while the full UI loads.
window_rule({
    match = {
        class = [[^(steam|Steam|steamwebhelper)$]],
        float = true,
    },
    center = true,
})

-- # TV mode routing is handled by tv-stack-listener only while TV mode is active.
-- # Keep Steam global rules out of Hyprland config so normal Steam launches remain
-- # ordinary desktop windows on the current workspace/monitor.

-- # Fix Jetbrain IDEs focus/rerendering problem
window_rule({
    match = {
        class = [[^jetbrains-.*$]],
        float = true,
        title = [[^$|^\s$|^win\d+$]],
    },
    no_initial_focus = true,
})

-- # No shadow for tiled windows (matches windows that are not floating).
window_rule({
    match = {
        float = false,
    },
    no_shadow = true,
})

-- # ######## Workspace rules ########
hl.workspace_rule({
    workspace = [[special:special]],
    gaps_out = 30,
})
-- # TV workspaces are created dynamically by tv_mode scripts only when the TV
-- # output exists. Static rules pin them to a desktop monitor when HDMI-A-2 is
-- # disconnected, which can trap normal app launches on special:tv.

-- # ######## Layer rules ########
layer_rule({
    match = {
        namespace = [[.*]],
    },
    xray = true,
})
-- # layerrule = match:namespace .*, no_anim on
layer_rule({
    match = {
        namespace = [[walker]],
    },
    no_anim = true,
})
layer_rule({
    match = {
        namespace = [[selection]],
    },
    no_anim = true,
})
layer_rule({
    match = {
        namespace = [[overview]],
    },
    no_anim = true,
})
layer_rule({
    match = {
        namespace = [[anyrun]],
    },
    no_anim = true,
})
layer_rule({
    match = {
        namespace = [[indicator.*]],
    },
    no_anim = true,
})
layer_rule({
    match = {
        namespace = [[osk]],
    },
    no_anim = true,
})
layer_rule({
    match = {
        namespace = [[hyprpicker]],
    },
    no_anim = true,
})

layer_rule({
    match = {
        namespace = [[noanim]],
    },
    no_anim = true,
})
layer_rule({
    match = {
        namespace = [[gtk-layer-shell]],
    },
    blur = true,
})
layer_rule({
    match = {
        namespace = [[gtk-layer-shell]],
    },
    ignore_alpha = false,
})
layer_rule({
    match = {
        namespace = [[launcher]],
    },
    blur = true,
})
layer_rule({
    match = {
        namespace = [[launcher]],
    },
    ignore_alpha = [[0.5]],
})
layer_rule({
    match = {
        namespace = [[notifications]],
    },
    blur = true,
})
layer_rule({
    match = {
        namespace = [[notifications]],
    },
    ignore_alpha = [[0.69]],
})
layer_rule({
    match = {
        namespace = [[logout_dialog]],
    },
}) -- wlogout, blur on

-- # ags
layer_rule({
    match = {
        namespace = [[sideleft.*]],
    },
    animation = [[slide left]],
})
layer_rule({
    match = {
        namespace = [[sideright.*]],
    },
    animation = [[slide right]],
})
layer_rule({
    match = {
        namespace = [[session[0-9]*]],
    },
    blur = true,
})
layer_rule({
    match = {
        namespace = [[bar[0-9]*]],
    },
    blur = true,
})
layer_rule({
    match = {
        namespace = [[bar[0-9]*]],
    },
    ignore_alpha = [[0.6]],
})
layer_rule({
    match = {
        namespace = [[barcorner.*]],
    },
    blur = true,
})
layer_rule({
    match = {
        namespace = [[barcorner.*]],
    },
    ignore_alpha = [[0.6]],
})
layer_rule({
    match = {
        namespace = [[dock[0-9]*]],
    },
    blur = true,
})
layer_rule({
    match = {
        namespace = [[dock[0-9]*]],
    },
    ignore_alpha = [[0.6]],
})
layer_rule({
    match = {
        namespace = [[indicator.*]],
    },
    blur = true,
})
layer_rule({
    match = {
        namespace = [[indicator.*]],
    },
    ignore_alpha = [[0.6]],
})
layer_rule({
    match = {
        namespace = [[overview[0-9]*]],
    },
    blur = true,
})
layer_rule({
    match = {
        namespace = [[overview[0-9]*]],
    },
    ignore_alpha = [[0.6]],
})
layer_rule({
    match = {
        namespace = [[cheatsheet[0-9]*]],
    },
    blur = true,
})
layer_rule({
    match = {
        namespace = [[cheatsheet[0-9]*]],
    },
    ignore_alpha = [[0.6]],
})
layer_rule({
    match = {
        namespace = [[sideright[0-9]*]],
    },
    blur = true,
})
layer_rule({
    match = {
        namespace = [[sideright[0-9]*]],
    },
    ignore_alpha = [[0.6]],
})
layer_rule({
    match = {
        namespace = [[sideleft[0-9]*]],
    },
    blur = true,
})
layer_rule({
    match = {
        namespace = [[sideleft[0-9]*]],
    },
    ignore_alpha = [[0.6]],
})
layer_rule({
    match = {
        namespace = [[indicator.*]],
    },
    blur = true,
})
layer_rule({
    match = {
        namespace = [[indicator.*]],
    },
    ignore_alpha = [[0.6]],
})
layer_rule({
    match = {
        namespace = [[osk[0-9]*]],
    },
    blur = true,
})
layer_rule({
    match = {
        namespace = [[osk[0-9]*]],
    },
    ignore_alpha = [[0.6]],
})

-- # Quickshell
-- # Quickshell: illogical-impulse
layer_rule({
    match = {
        namespace = [[quickshell:.*]],
    },
    blur_popups = true,
})
layer_rule({
    match = {
        namespace = [[quickshell:.*]],
    },
    blur = true,
})
layer_rule({
    match = {
        namespace = [[quickshell:.*]],
    },
    ignore_alpha = [[0.79]],
})
layer_rule({
    match = {
        namespace = [[quickshell:layoutSwitcher]],
    },
    blur = true,
    ignore_alpha = [[0]],
    xray = false,
})
layer_rule({
    match = {
        namespace = [[quickshell:layoutSwitcherDim]],
    },
    animation = [[fade]],
})
layer_rule({
    match = {
        namespace = [[quickshell:bar]],
    },
    animation = [[slide]],
})
layer_rule({
    match = {
        namespace = [[quickshell:actionCenter]],
    },
    no_anim = true,
})
layer_rule({
    match = {
        namespace = [[quickshell:cheatsheet]],
    },
    animation = [[slide bottom]],
})
layer_rule({
    match = {
        namespace = [[quickshell:dock]],
    },
    animation = [[slide bottom]],
})
layer_rule({
    match = {
        namespace = [[quickshell:screenCorners]],
    },
    animation = [[popin 120%]],
})
layer_rule({
    match = {
        namespace = [[quickshell:lockWindowPusher]],
    },
    no_anim = true,
})
layer_rule({
    match = {
        namespace = [[quickshell:notificationPopup]],
    },
    animation = [[fade]],
})
layer_rule({
    match = {
        namespace = [[quickshell:overlay]],
    },
    no_anim = true,
})
layer_rule({
    match = {
        namespace = [[quickshell:overlay]],
    },
    ignore_alpha = true,
})
layer_rule({
    match = {
        namespace = [[quickshell:overview]],
    },
    no_anim = true,
})
layer_rule({
    match = {
        namespace = [[quickshell:osk]],
    },
    animation = [[slide bottom]],
})
layer_rule({
    match = {
        namespace = [[quickshell:polkit]],
    },
    no_anim = true,
})
layer_rule({
    match = {
        namespace = [[quickshell:popup]],
    },
    xray = false,
}) -- No weird color for bar tooltips (this in theory should suffice)
layer_rule({
    match = {
        namespace = [[quickshell:popup]],
    },
    ignore_alpha = true,
}) -- No weird color for bar tooltips (but somehow this is necessary)
layer_rule({
    match = {
        namespace = [[quickshell:mediaControls]],
    },
    ignore_alpha = true,
}) -- Same as above
layer_rule({
    match = {
        namespace = [[quickshell:reloadPopup]],
    },
    animation = [[slide]],
})
layer_rule({
    match = {
        namespace = [[quickshell:regionSelector]],
    },
    no_anim = true,
})
layer_rule({
    match = {
        namespace = [[quickshell:screenshot]],
    },
    no_anim = true,
})
layer_rule({
    match = {
        namespace = [[quickshell:session]],
    },
    blur = true,
})
layer_rule({
    match = {
        namespace = [[quickshell:session]],
    },
    no_anim = true,
})
layer_rule({
    match = {
        namespace = [[quickshell:session]],
    },
    ignore_alpha = false,
})
layer_rule({
    match = {
        namespace = [[quickshell:sidebarRight]],
    },
    animation = [[slide right]],
})
layer_rule({
    match = {
        namespace = [[quickshell:sidebarLeft]],
    },
    animation = [[slide left]],
})
layer_rule({
    match = {
        namespace = [[quickshell:verticalBar]],
    },
    animation = [[slide]],
})
layer_rule({
    match = {
        namespace = [[quickshell:osk]],
    },
    order = -1,
})
-- # Quickshell: waffles
layer_rule({
    match = {
        namespace = [[quickshell:wallpaperSelector]],
    },
    animation = [[slide top]],
})
layer_rule({
    match = {
        namespace = [[quickshell:wNotificationCenter]],
    },
    no_anim = true,
})
layer_rule({
    match = {
        namespace = [[quickshell:wOnScreenDisplay]],
    },
    no_anim = true,
})
layer_rule({
    match = {
        namespace = [[quickshell:wStartMenu]],
    },
    no_anim = true,
})
layer_rule({
    match = {
        namespace = [[quickshell:wTaskView]],
    },
    ignore_alpha = false,
})
layer_rule({
    match = {
        namespace = [[quickshell:wTaskView]],
    },
    no_anim = true,
})

-- # Launchers need to be FAST
layer_rule({
    match = {
        namespace = [[gtk4-layer-shell]],
    },
    no_anim = true,
})

-- # ######## Local window rules ########
window_rule({
    match = {
        class = [[^(org\.quickshell)$]],
        title = [[^(Quickshell Calculator)$]],
    },
    float = true,
    size = [[520 760]],
    center = true,
})
window_rule({
    match = {
        class = [[^(org\.quickshell)$]],
        title = [[^(Quickshell Timers)$]],
    },
    float = true,
    size = [[620 560]],
    center = true,
})
window_rule({
    match = {
        class = [[^(org\.quickshell)$]],
        title = [[^(Quickshell System Dashboard)$]],
    },
    float = true,
    size = [[980 760]],
    center = true,
})
window_rule({
    match = {
        class = [[^(kitty|QSHealth)$]],
        title = [[^(Quickshell Health Logs)$]],
    },
    float = true,
    size = [[1100 760]],
    center = true,
})

window_rule({
    match = {
        class = [[^(kitty)$]],
        title = [[^(QSUpdate)$]],
    },
    float = true,
    size = [[1000 750]],
    center = true,
})

-- # Dedicated floating terminal for the top-bar resource monitor button.
window_rule({
    match = {
        class = [[^(btop)$]],
    },
    float = true,
    size = [[1200 800]],
    center = true,
})
-- #windowrule = match:class ^(kitty)$, opacity 0.96

-- # Thunderbird calendar/reminder popups
window_rule({
    match = {
        class = [[^(thunderbird|Thunderbird)$]],
        title = [[^(.*(Reminder|Promemoria|Calendar|Event).*)$]],
    },
    float = true,
    center = true,
})

-- # KDE portal dialog
window_rule({
    match = {
        class = [[^(org\.freedesktop\.impl\.portal\.desktop\.kde)$]],
    },
    float = true,
    size = [[1000 725]],
    center = true,
})

-- # Thunderbird: compose/event editor windows should open as floating dialogs
window_rule({
    match = {
        class = [[^(thunderbird|Thunderbird)$]],
        title = [[^((Write|Compose|Scrivi|Nuovo messaggio|New Message|Message Compose|Event|New Event|Edit Event|Nuovo evento|Modifica evento).*)$]],
    },
    float = true,
    center = true,
    size = [[1280 860]],
})

-- # GNOME apps use the same frosted glass treatment as the rest of the desktop.
window_rule({
    match = {
        class = [[^(org\.gnome\.Nautilus|nautilus|Nautilus)$]],
    },
    opacity = [[0.99 0.96]],
})
window_rule({
    match = {
        class = [[^(org\.gnome\.Nautilus|nautilus|Nautilus)$]],
    },
    no_blur = false,
})
window_rule({
    match = {
        title = [[^(Files|Nautilus).*$]],
    },
    opacity = [[0.99 0.96]],
})
window_rule({
    match = {
        title = [[^(Files|Nautilus).*$]],
    },
    no_blur = false,
})

-- # Fallback: some GNOME apps report different class names under Wayland.
window_rule({
    match = {
        class = [[^(org\.gnome\..*)$]],
    },
    opacity = [[0.99 0.96]],
})
window_rule({
    match = {
        class = [[^(org\.gnome\..*)$]],
    },
    no_blur = false,
})

-- # Keep TV mode fully opaque. These sit after app-specific glass rules so the TV
-- # workspaces stay clean for games/video while normal desktop workspaces blur.
window_rule({
    match = {
        workspace = [[name:special:tv]],
    },
    name = [[tv-main-opaque]],
    no_blur = true,
    opacity = [[1 1]],
})

window_rule({
    match = {
        workspace = [[name:special:tv-app]],
    },
    name = [[tv-app-opaque]],
    no_blur = true,
    opacity = [[1 1]],
})

window_rule({
    match = {
        workspace = 21,
    },
    name = [[tv-landing-opaque]],
    no_blur = true,
    opacity = [[1 1]],
})

-- # Chromium/Brave: keep browser popups square and shadowless.
window_rule({
    match = {
        class = [[^(Brave-browser|brave-browser|Google-chrome|google-chrome|Chromium|chromium|chromium-browser)$]],
        float = true,
    },
    no_shadow = true,
})
window_rule({
    match = {
        class = [[^(Brave-browser|brave-browser|Google-chrome|google-chrome|Chromium|chromium|chromium-browser)$]],
        float = true,
    },
    rounding = false,
})

-- # Chromium menu shells can arrive as anonymous floating windows with empty
-- # class/title. Strip compositor decoration from those too.
window_rule({
    match = {
        class = [[^$]],
        title = [[^$]],
        float = true,
    },
    no_shadow = true,
})
window_rule({
    match = {
        class = [[^$]],
        title = [[^$]],
        float = true,
    },
    rounding = false,
})
window_rule({
    match = {
        class = [[^$]],
        title = [[^$]],
        float = true,
    },
    no_blur = true,
})
