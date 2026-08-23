#!/usr/bin/env python3

import configparser
import json
import os
import re
from pathlib import Path


XDG_CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")))
XDG_DATA_HOME = Path(os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share")))
XDG_STATE_HOME = Path(os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")))

COLORS_JSON = XDG_STATE_HOME / "quickshell" / "user" / "generated" / "colors.json"
KDEGLOBALS_PATHS = [
    XDG_CONFIG_HOME / "kdeglobals",
    XDG_CONFIG_HOME / "kdedefaults" / "kdeglobals",
]
QT_CONF_PATHS = [
    XDG_CONFIG_HOME / "qt5ct" / "qt5ct.conf",
    XDG_CONFIG_HOME / "qt6ct" / "qt6ct.conf",
]
DOLPHINRC = XDG_CONFIG_HOME / "dolphinrc"
KVANTUM_CONFIG = XDG_CONFIG_HOME / "Kvantum" / "MaterialAdw" / "MaterialAdw.kvconfig"
SCHEME_NAME = "MaterialYouDynamic"
COLOR_SCHEME_FILE = XDG_DATA_HOME / "color-schemes" / f"{SCHEME_NAME}.colors"
DEFAULT_DARK_ICON_THEME = "Papirus-Dark"
DEFAULT_LIGHT_ICON_THEME = "Papirus"


def load_colors() -> dict[str, str]:
    with COLORS_JSON.open() as f:
        return json.load(f)


def get(colors: dict[str, str], key: str, fallback: str) -> str:
    return colors.get(key, fallback)


def rgb_triplet(hex_color: str) -> str:
    hex_color = hex_color.lstrip("#")
    return ",".join(str(int(hex_color[i : i + 2], 16)) for i in (0, 2, 4))


def relative_luminance(hex_color: str) -> float:
    channels = [int(hex_color.lstrip("#")[i : i + 2], 16) / 255 for i in (0, 2, 4)]
    linear = [value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4 for value in channels]
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]


def contrast_ratio(first: str, second: str) -> float:
    lighter, darker = sorted((relative_luminance(first), relative_luminance(second)), reverse=True)
    return (lighter + 0.05) / (darker + 0.05)


def contrast_text(hex_color: str, dark: str = "#1b1b1b", light: str = "#f5f5f5") -> str:
    return dark if contrast_ratio(hex_color, dark) >= contrast_ratio(hex_color, light) else light


def accessible_foreground(background: str, preferred: str, minimum: float = 4.5) -> str:
    """Keep Material's semantic foreground unless it misses normal-text contrast."""
    if contrast_ratio(background, preferred) >= minimum:
        return preferred
    fallback = contrast_text(background)
    if contrast_ratio(background, fallback) >= minimum:
        return fallback
    return contrast_text(background, dark="#000000", light="#ffffff")


def is_dark_mode(colors: dict[str, str]) -> bool:
    value = colors.get("darkmode", False)
    return value is True or str(value).lower() == "true"


def ensure_section(cfg: configparser.RawConfigParser, name: str) -> None:
    if not cfg.has_section(name):
        cfg.add_section(name)


def read_ini(path: Path) -> configparser.RawConfigParser:
    cfg = configparser.RawConfigParser(interpolation=None, strict=False)
    cfg.optionxform = str
    if path.exists():
        cfg.read(path)
    return cfg


def write_ini(path: Path, cfg: configparser.RawConfigParser) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w") as f:
        cfg.write(f, space_around_delimiters=False)


def theme_exists(name: str) -> bool:
    return any(
        (base / name / "index.theme").exists()
        for base in (XDG_DATA_HOME / "icons", Path("/usr/share/icons"))
    )


def icon_theme_for_mode(colors: dict[str, str]) -> str:
    settings = XDG_CONFIG_HOME / "gtk-3.0" / "settings.ini"
    dark = is_dark_mode(colors)
    if settings.exists():
        for line in settings.read_text(errors="ignore").splitlines():
            if line.startswith("gtk-icon-theme-name="):
                name = line.split("=", 1)[1].strip().strip('"')
                if name:
                    families = {
                        "Papirus": ("Papirus", "Papirus-Dark", "Papirus-Light"),
                        "WhiteSur": ("WhiteSur", "WhiteSur-dark", "WhiteSur-light"),
                        "Tela": ("Tela", "Tela-dark", "Tela-light"),
                        "breeze": ("breeze", "breeze-dark", "breeze"),
                    }
                    for variants in families.values():
                        if name in variants:
                            candidate = variants[1] if dark else variants[0]
                            if theme_exists(candidate):
                                return candidate
                    if theme_exists(name):
                        return name
    preferred = DEFAULT_DARK_ICON_THEME if dark else DEFAULT_LIGHT_ICON_THEME
    fallback = "breeze-dark" if dark else "breeze"
    return preferred if theme_exists(preferred) else fallback


def update_kdeglobals(colors: dict[str, str]) -> None:
    bg = get(colors, "background", "#19120c")
    surface = get(colors, "surface", bg)
    low = get(colors, "surface_container_low", "#221a14")
    container = get(colors, "surface_container", "#261e18")
    high = get(colors, "surface_container_high", "#312822")
    text = accessible_foreground(surface, get(colors, "on_surface", contrast_text(surface)))
    muted = get(colors, "on_surface_variant", contrast_text(container))
    primary = get(colors, "primary", "#ffb878")
    on_primary = accessible_foreground(primary, get(colors, "on_primary", contrast_text(primary)))
    primary_container = get(colors, "primary_container", "#6b3b03")
    on_primary_container = accessible_foreground(
        primary_container,
        get(colors, "on_primary_container", contrast_text(primary_container)),
    )
    selection_bg = primary_container if is_dark_mode(colors) else primary
    selection_fg = on_primary_container if is_dark_mode(colors) else on_primary
    secondary = get(colors, "secondary", "#e2c0a5")
    secondary_container = get(colors, "secondary_container", "#5a422d")
    tertiary = get(colors, "tertiary", "#c2cb98")
    error = get(colors, "error", "#ffb4ab")
    outline = get(colors, "outline", "#9e8e82")
    visited = secondary_container

    def section_foregrounds(background: str) -> dict[str, str]:
        normal = contrast_text(background)
        inactive = muted if normal.lower() != muted.lower() else outline
        return {
            "ForegroundActive": normal,
            "ForegroundInactive": inactive,
            "ForegroundLink": primary,
            "ForegroundNegative": error,
            "ForegroundNeutral": secondary,
            "ForegroundNormal": normal,
            "ForegroundPositive": tertiary,
            "ForegroundVisited": visited,
            "DecorationFocus": primary,
            "DecorationHover": primary,
        }

    for path in KDEGLOBALS_PATHS:
        cfg = read_ini(path)

        sections = {
            "ColorEffects:Disabled": {
                "Color": low,
                "ColorAmount": "0.4",
                "ColorEffect": "0",
                "ContrastAmount": "0",
                "ContrastEffect": "0",
                "Enable": "true",
                "IntensityAmount": "0",
                "IntensityEffect": "0",
            },
            "ColorEffects:Inactive": {
                "ChangeSelectionColor": "true",
                "Color": bg,
                "ColorAmount": "0.08",
                "ColorEffect": "0",
                "ContrastAmount": "0.1",
                "ContrastEffect": "0",
                "Enable": "true",
                "IntensityAmount": "0",
                "IntensityEffect": "0",
            },
            "Colors:Button": {
                "BackgroundAlternate": high,
                "BackgroundNormal": container,
                **section_foregrounds(container),
            },
            "Colors:Complementary": {
                "BackgroundAlternate": container,
                "BackgroundNormal": container,
                **section_foregrounds(container),
            },
            "Colors:Header": {
                "BackgroundAlternate": container,
                "BackgroundNormal": container,
                **section_foregrounds(container),
            },
            "Colors:Header][Inactive": {
                "BackgroundAlternate": container,
                "BackgroundNormal": container,
                **section_foregrounds(container),
            },
            "Colors:Selection": {
                "BackgroundAlternate": selection_bg,
                "BackgroundNormal": selection_bg,
                "DecorationFocus": primary,
                "DecorationHover": primary_container,
                "ForegroundActive": selection_fg,
                "ForegroundInactive": selection_fg,
                "ForegroundLink": selection_fg,
                "ForegroundNegative": selection_fg,
                "ForegroundNeutral": selection_fg,
                "ForegroundNormal": selection_fg,
                "ForegroundPositive": selection_fg,
                "ForegroundVisited": selection_fg,
            },
            "Colors:Tooltip": {
                "BackgroundAlternate": container,
                "BackgroundNormal": high,
                **section_foregrounds(high),
            },
            "Colors:View": {
                "BackgroundAlternate": low,
                "BackgroundNormal": surface,
                "DecorationFocus": primary,
                "DecorationHover": primary_container,
                **{
                    k: v
                    for k, v in section_foregrounds(surface).items()
                    if not k.startswith("Decoration")
                },
            },
            "Colors:Window": {
                "BackgroundAlternate": container,
                "BackgroundNormal": container,
                **section_foregrounds(container),
            },
        }

        for section, values in sections.items():
            ensure_section(cfg, section)
            for key, value in values.items():
                cfg.set(section, key, value)

        ensure_section(cfg, "General")
        cfg.set("General", "ColorScheme", SCHEME_NAME)
        cfg.set("General", "AccentColor", rgb_triplet(primary))
        cfg.set("General", "LastUsedCustomAccentColor", rgb_triplet(primary))
        cfg.set("General", "accentColorFromWallpaper", "false")
        if cfg.has_option("General", "ColorSchemeHash"):
            cfg.remove_option("General", "ColorSchemeHash")
        if cfg.has_section("KDE") and cfg.has_option("KDE", "widgetStyle"):
            cfg.remove_option("KDE", "widgetStyle")

        ensure_section(cfg, "Icons")
        cfg.set("Icons", "Theme", icon_theme_for_mode(colors))

        ensure_section(cfg, "WM")
        cfg.set("WM", "activeBackground", rgb_triplet(high))
        cfg.set("WM", "activeForeground", rgb_triplet(text))
        cfg.set("WM", "inactiveBackground", rgb_triplet(container))
        cfg.set("WM", "inactiveForeground", rgb_triplet(muted))

        write_ini(path, cfg)


def update_color_scheme_file() -> None:
    kdeglobals = read_ini(KDEGLOBALS_PATHS[0])
    scheme = configparser.RawConfigParser(interpolation=None, strict=False)
    scheme.optionxform = str

    for section in (
        "ColorEffects:Disabled",
        "ColorEffects:Inactive",
        "Colors:Button",
        "Colors:Complementary",
        "Colors:Header",
        "Colors:Header][Inactive",
        "Colors:Selection",
        "Colors:Tooltip",
        "Colors:View",
        "Colors:Window",
        "KDE",
        "WM",
    ):
        if not kdeglobals.has_section(section):
            continue
        ensure_section(scheme, section)
        for key, value in kdeglobals.items(section):
            scheme.set(section, key, value)

    ensure_section(scheme, "General")
    scheme.set("General", "Name", "Material You Dynamic")
    scheme.set("General", "ColorScheme", SCHEME_NAME)
    scheme.set("General", "shadeSortColumn", "true")

    write_ini(COLOR_SCHEME_FILE, scheme)


def update_qtct_configs(colors: dict[str, str]) -> None:
    icon_theme = icon_theme_for_mode(colors)
    for path in QT_CONF_PATHS:
        cfg = read_ini(path)
        ensure_section(cfg, "Appearance")
        color_path = str(path.parent / "colors" / "material-you.conf")
        cfg.set("Appearance", "color_scheme_path", color_path)
        cfg.set("Appearance", "custom_palette", "true")
        cfg.set("Appearance", "icon_theme", icon_theme)
        cfg.set("Appearance", "style", "kvantum")
        write_ini(path, cfg)


def update_dolphinrc() -> None:
    cfg = read_ini(DOLPHINRC)
    ensure_section(cfg, "UiSettings")
    cfg.set("UiSettings", "ColorScheme", SCHEME_NAME)
    write_ini(DOLPHINRC, cfg)


def update_kvantum_config(colors: dict[str, str]) -> None:
    if not KVANTUM_CONFIG.exists():
        return

    svg_path = KVANTUM_CONFIG.with_suffix(".svg")
    old_text = KVANTUM_CONFIG.read_text(errors="ignore")
    previous_accents = set(re.findall(r"^\s*link\.color=(#[0-9a-fA-F]{6})", old_text, flags=re.MULTILINE))

    on_surface = accessible_foreground(
        get(colors, "surface", "#19120c"),
        get(colors, "on_surface", contrast_text(get(colors, "surface", "#19120c"))),
    )
    on_surface_variant = get(colors, "on_surface_variant", "#d6c3b6")
    container = get(colors, "surface_container", "#261e18")
    surface = get(colors, "surface", "#19120c")
    low = get(colors, "surface_container_low", "#221a14")
    high = get(colors, "surface_container_high", "#312822")
    highest = get(colors, "surface_container_highest", "#3c332c")
    primary = get(colors, "primary", "#ffb878")
    on_primary = accessible_foreground(primary, get(colors, "on_primary", contrast_text(primary)))
    primary_container = get(colors, "primary_container", "#6b3b03")
    on_primary_container = accessible_foreground(
        primary_container,
        get(colors, "on_primary_container", contrast_text(primary_container)),
    )
    selection_bg = primary_container if is_dark_mode(colors) else primary
    selection_fg = on_primary_container if is_dark_mode(colors) else on_primary
    button_fg = accessible_foreground(high, get(colors, "on_surface", contrast_text(high)))
    secondary_container = get(colors, "secondary_container", "#5a422d")
    text = old_text

    replacements = {
        "window.color": container,
        "base.color": surface,
        "alt.base.color": low,
        "button.color": high,
        "light.color": high,
        "mid.light.color": highest,
        "mid.color": low,
        "highlight.color": selection_bg,
        "highlight.text.color": selection_fg,
        "link.color": primary,
        "link.visited.color": secondary_container,
        "transparent_dolphin_view": "false",
    }

    for key, value in replacements.items():
        text = re.sub(
            rf"(^\s*{re.escape(key)}=).*$",
            lambda m: f"{m.group(1)}{value}",
            text,
            flags=re.MULTILINE,
        )

    section_keys = {
        "PanelButtonCommand": {
            "text.normal.color": button_fg,
            "text.focus.color": button_fg,
            "text.press.color": button_fg,
            "text.toggle.color": button_fg,
        },
        "PanelButtonTool": {
            "text.normal.color": button_fg,
            "text.focus.color": button_fg,
            "text.press.color": button_fg,
            "text.toggle.color": button_fg,
        },
        "ToolbarButton": {
            "text.normal.color": button_fg,
            "text.focus.color": button_fg,
            "text.press.color": button_fg,
            "text.toggle.color": button_fg,
        },
        "Tab": {
            "text.normal.color": button_fg,
            "text.focus.color": button_fg,
            "text.press.color": button_fg,
            "text.toggle.color": button_fg,
        },
        "HeaderSection": {
            "text.normal.color": button_fg,
            "text.focus.color": button_fg,
            "text.press.color": button_fg,
            "text.toggle.color": button_fg,
        },
        "Toolbar": {
            "text.normal.color": button_fg,
            "text.focus.color": button_fg,
            "text.press.color": button_fg,
            "text.toggle.color": button_fg,
        },
        "ItemView": {
            "text.normal.color": button_fg,
            "text.focus.color": button_fg,
            "text.press.color": button_fg,
            "text.toggle.color": button_fg,
        },
        "LineEdit": {
            "text.normal.color": on_surface,
            "text.focus.color": on_surface,
            "text.press.color": on_surface,
            "text.toggle.color": on_surface,
        },
        "ToolbarLineEdit": {
            "text.normal.color": on_surface,
            "text.focus.color": on_surface,
            "text.press.color": on_surface,
            "text.toggle.color": on_surface,
        },
        "Focus": {},
        "Menu": {"text.normal.color": on_surface},
        "MenuItem": {
            "text.normal.color": on_surface,
            "text.focus.color": selection_fg,
            "text.press.color": selection_fg,
            "text.toggle.color": selection_fg,
        },
        "MenuBar": {
            "text.normal.color": on_surface,
            "text.focus.color": selection_fg,
            "text.press.color": selection_fg,
            "text.toggle.color": selection_fg,
        },
        "MenuBarItem": {
            "text.normal.color": on_surface,
            "text.focus.color": selection_fg,
            "text.press.color": selection_fg,
            "text.toggle.color": selection_fg,
        },
        "ComboBox": {
            "text.normal.color": button_fg,
            "text.focus.color": button_fg,
            "text.press.color": button_fg,
            "text.toggle.color": button_fg,
        },
        "TitleBar": {
            "text.normal.color": on_surface,
            "text.focus.color": on_surface_variant,
        },
    }

    for section, values in section_keys.items():
        pattern = rf"(\[{re.escape(section)}\]\n)(.*?)(?=\n\[|\Z)"
        match = re.search(pattern, text, flags=re.DOTALL)
        if not match:
            continue
        block = match.group(2)
        for key, value in values.items():
            if re.search(rf"(^\s*{re.escape(key)}=).*$", block, flags=re.MULTILINE):
                block = re.sub(
                    rf"(^\s*{re.escape(key)}=).*$",
                    lambda m: f"{m.group(1)}{value}",
                    block,
                    flags=re.MULTILINE,
                )
            else:
                if block and not block.endswith("\n"):
                    block += "\n"
                block += f"{key}={value}\n"
        text = text[: match.start(2)] + block + text[match.end(2) :]

    KVANTUM_CONFIG.write_text(text.rstrip() + "\n")

    if svg_path.exists():
        svg = svg_path.read_text(errors="ignore")
        stale_accents = previous_accents | {
            "#ffb878", "#FFB878", "#f6bc70", "#F6BC70", "#e9873a", "#E9873A",
            "#d5bbfc", "#D5BBFC", "#95cdf7", "#95CDF7",
        }
        for accent in stale_accents:
            if accent.lower() != primary.lower():
                svg = re.sub(re.escape(accent), primary, svg, flags=re.IGNORECASE)
        svg = re.sub(r"(\.ColorScheme-Highlight\s*\{[^}]*?color:)#[0-9a-fA-F]{6}", rf"\g<1>{selection_bg}", svg, flags=re.DOTALL)
        svg = re.sub(r"(\.ColorScheme-Highlight\s*\{[^}]*?stop-color:)#[0-9a-fA-F]{6}", rf"\g<1>{selection_bg}", svg, flags=re.DOTALL)
        svg = re.sub(r"(\.ColorScheme-HighlightedText\s*\{[^}]*?color:)#[0-9a-fA-F]{6}", rf"\g<1>{selection_fg}", svg, flags=re.DOTALL)
        svg = re.sub(r"(\.ColorScheme-HighlightedText\s*\{[^}]*?stop-color:)#[0-9a-fA-F]{6}", rf"\g<1>{selection_fg}", svg, flags=re.DOTALL)
        svg_path.write_text(svg)


def main() -> None:
    if not COLORS_JSON.exists():
        return

    colors = load_colors()
    update_kdeglobals(colors)
    update_color_scheme_file()
    update_qtct_configs(colors)
    update_dolphinrc()
    update_kvantum_config(colors)


if __name__ == "__main__":
    main()
