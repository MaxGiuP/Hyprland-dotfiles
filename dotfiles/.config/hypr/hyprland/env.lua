local h = require("hyprland.lib")

-- Wayland
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- Applications
hl.env("XDG_DATA_DIRS", "/usr/local/share:/usr/share:/var/lib/flatpak/exports/share:" .. h.expand("$HOME/.local/share/flatpak/exports/share"))

-- Themes
hl.env("QT_QPA_PLATFORM", "wayland")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")

-- Virtual environment
hl.env("ILLOGICAL_IMPULSE_VIRTUAL_ENV", h.expand("~/.local/state/quickshell/.venv"))

-- Terminal application
hl.env("TERMINAL", "kitty -1")
-- MaterialYou carries WhiteSur's full theme resources with generated colors.
hl.env("GTK_THEME", "MaterialYou")
-- hl.env("GTK_USE_PORTAL", "1")

-- Cursor
hl.env("XCURSOR_THEME", "Adwaita")
-- HYPRCURSOR_THEME is intentionally unset so Hyprland falls back to the Adwaita XCursor theme.
hl.env("XCURSOR_SIZE", "32")
hl.env("HYPRCURSOR_SIZE", "32")

-- GTK_THEME and GTK_ICON_THEME are managed through gsettings/settings.ini.
-- Setting them here hard-codes a theme name and overrides theme sync behavior.
-- hl.env("GDK_BACKEND", "wayland,x11")

-- Language
hl.env("LANG", "de_DE.UTF-8")
hl.env("LC_TIME", "de_DE.UTF-8")
hl.env("LC_CTYPE", "de_DE.UTF-8")
hl.env("LC_MESSAGES", "de_DE.UTF-8")
hl.env("LC_ALL", "de_DE.UTF-8")
