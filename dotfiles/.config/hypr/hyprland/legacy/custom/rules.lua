local h = require("hyprland.lib")
local window_rule = h.window_rule

-- Migrated from legacy/custom/rules.conf. Optional legacy custom module; not loaded by default.

-- QSUpdate (kitty)
window_rule({
    match = { class = [[^(kitty)$]], title = [[^(QSUpdate)$]] },
    float = true,
    size = [[1000 750]],
    center = true,
})
-- window_rule({ match = { class = [[^(kitty)$]] }, opacity = [[0.96]] })

-- Thunderbird calendar/reminder popups
window_rule({
    match = {
        class = [[^(thunderbird|Thunderbird)$]],
        title = [[^(.*(Reminder|Promemoria|Calendar|Event).*)$]],
    },
    float = true,
    center = true,
})

-- KDE portal dialog
window_rule({
    match = { class = [[^(org\.freedesktop\.impl\.portal\.desktop\.kde)$]] },
    float = true,
    size = [[1000 725]],
    center = true,
})

-- Thunderbird: compose/event editor windows should open as floating dialogs
window_rule({
    match = {
        class = [[^(thunderbird|Thunderbird)$]],
        title = [[^((Write|Compose|Scrivi|Nuovo messaggio|New Message|Message Compose|Event|New Event|Edit Event|Nuovo evento|Modifica evento).*)$]],
    },
    float = true,
    center = true,
    size = [[1280 860]],
})

-- Nautilus/Files: keep fully opaque and disable blur bleed-through
window_rule({ match = { class = [[^(org\.gnome\.Nautilus|nautilus|Nautilus)$]] }, opacity = [[1]] })
window_rule({ match = { class = [[^(org\.gnome\.Nautilus|nautilus|Nautilus)$]] }, no_blur = true })
window_rule({ match = { title = [[^(Files|Nautilus).*$]] }, opacity = [[1]] })
window_rule({ match = { title = [[^(Files|Nautilus).*$]] }, no_blur = true })

-- Fallback: some GNOME apps report different class names under Wayland
window_rule({ match = { class = [[^(org\.gnome\..*)$]] }, opacity = [[1]] })
window_rule({ match = { class = [[^(org\.gnome\..*)$]] }, no_blur = true })

-- Chromium/Brave: keep browser popups square and shadowless.
window_rule({
    match = { class = [[^(Brave-browser|brave-browser|Google-chrome|google-chrome|Chromium|chromium|chromium-browser)$]], float = true },
    no_shadow = true,
})
window_rule({
    match = { class = [[^(Brave-browser|brave-browser|Google-chrome|google-chrome|Chromium|chromium|chromium-browser)$]], float = true },
    rounding = 0,
})

-- Chromium menu shells can arrive as anonymous floating windows with empty class/title.
-- Strip compositor decoration from those too.
window_rule({ match = { class = [[^$]], title = [[^$]], float = true }, no_shadow = true })
window_rule({ match = { class = [[^$]], title = [[^$]], float = true }, rounding = 0 })
window_rule({ match = { class = [[^$]], title = [[^$]], float = true }, no_blur = true })
