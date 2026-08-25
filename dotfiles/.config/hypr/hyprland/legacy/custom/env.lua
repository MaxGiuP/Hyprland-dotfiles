local h = require("hyprland.lib")

-- Migrated from legacy/custom/env.conf. Optional legacy custom module; not loaded by default.
hl.env("XCURSOR_THEME", "WhiteSur-cursors")
hl.env("HYPRCURSOR_THEME", "WhiteSur-cursors-hyprcursors")
hl.env("XCURSOR_SIZE", "32")
hl.env("HYPRCURSOR_SIZE", "32")

-- GTK_THEME and GTK_ICON_THEME are managed by applygtk.sh via gsettings/settings.ini.
-- Setting them here hard-codes a theme name that may not exist and overrides everything.
-- hl.env("GDK_BACKEND", "wayland,x11")

-- Language
-- hl.env("LANG", "de_DE.UTF-8")
-- hl.env("LC_TIME", "de_DE.UTF-8")
-- hl.env("LC_CTYPE", "de_DE.UTF-8")
-- hl.env("LC_ALL", "de_DE.UTF-8")
hl.env("LANG", "it_IT.UTF-8")
hl.env("LC_TIME", "it_IT.UTF-8")
hl.env("LC_CTYPE", "it_IT.UTF-8")
hl.env("LC_ALL", "it_IT.UTF-8")
