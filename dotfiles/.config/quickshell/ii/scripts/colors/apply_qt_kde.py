#!/usr/bin/env python3

import configparser
import json
import os
import re
from pathlib import Path


XDG_CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")))
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


def load_colors() -> dict[str, str]:
    with COLORS_JSON.open() as f:
        return json.load(f)


def get(colors: dict[str, str], key: str, fallback: str) -> str:
    return colors.get(key, fallback)


def rgb_triplet(hex_color: str) -> str:
    hex_color = hex_color.lstrip("#")
    return ",".join(str(int(hex_color[i : i + 2], 16)) for i in (0, 2, 4))


def contrast_text(hex_color: str, dark: str = "#1b1b1b", light: str = "#f5f5f5") -> str:
    hex_color = hex_color.lstrip("#")
    r = int(hex_color[0:2], 16)
    g = int(hex_color[2:4], 16)
    b = int(hex_color[4:6], 16)
    brightness = (r * 299 + g * 587 + b * 114) / 1000
    return dark if brightness > 128 else light


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


def update_kdeglobals(colors: dict[str, str]) -> None:
    bg = get(colors, "background", "#19120c")
    surface = get(colors, "surface", bg)
    low = get(colors, "surface_container_low", "#221a14")
    container = get(colors, "surface_container", "#261e18")
    high = get(colors, "surface_container_high", "#312822")
    text = contrast_text(surface)
    muted = get(colors, "on_surface_variant", contrast_text(container))
    primary = get(colors, "primary", "#ffb878")
    on_primary = contrast_text(primary)
    primary_container = get(colors, "primary_container", "#6b3b03")
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
                "BackgroundAlternate": primary,
                "BackgroundNormal": primary,
                "DecorationFocus": primary,
                "DecorationHover": primary_container,
                "ForegroundActive": on_primary,
                "ForegroundInactive": on_primary,
                "ForegroundLink": on_primary,
                "ForegroundNegative": on_primary,
                "ForegroundNeutral": on_primary,
                "ForegroundNormal": on_primary,
                "ForegroundPositive": on_primary,
                "ForegroundVisited": on_primary,
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
        cfg.set("General", "LastUsedCustomAccentColor", rgb_triplet(primary))
        if cfg.has_option("General", "ColorSchemeHash"):
            cfg.remove_option("General", "ColorSchemeHash")
        if cfg.has_section("KDE") and cfg.has_option("KDE", "widgetStyle"):
            cfg.remove_option("KDE", "widgetStyle")

        ensure_section(cfg, "WM")
        cfg.set("WM", "activeBackground", rgb_triplet(high))
        cfg.set("WM", "activeForeground", rgb_triplet(text))
        cfg.set("WM", "inactiveBackground", rgb_triplet(container))
        cfg.set("WM", "inactiveForeground", rgb_triplet(muted))

        write_ini(path, cfg)


def update_qtct_configs() -> None:
    for path in QT_CONF_PATHS:
        cfg = read_ini(path)
        ensure_section(cfg, "Appearance")
        color_path = str(path.parent / "colors" / "material-you.conf")
        cfg.set("Appearance", "color_scheme_path", color_path)
        cfg.set("Appearance", "custom_palette", "true")
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

    on_surface = contrast_text(get(colors, "surface", "#19120c"))
    on_surface_variant = get(colors, "on_surface_variant", "#d6c3b6")
    container = get(colors, "surface_container", "#261e18")
    surface = get(colors, "surface", "#19120c")
    low = get(colors, "surface_container_low", "#221a14")
    high = get(colors, "surface_container_high", "#312822")
    highest = get(colors, "surface_container_highest", "#3c332c")
    primary = get(colors, "primary", "#ffb878")
    on_primary = contrast_text(primary)
    button_fg = contrast_text(high)
    secondary_container = get(colors, "secondary_container", "#5a422d")
    text = KVANTUM_CONFIG.read_text()

    replacements = {
        "window.color": container,
        "base.color": surface,
        "alt.base.color": low,
        "button.color": high,
        "light.color": high,
        "mid.light.color": highest,
        "mid.color": low,
        "highlight.text.color": on_primary,
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
        "Menu": {"text.normal.color": on_surface},
        "MenuItem": {
            "text.normal.color": on_surface,
            "text.focus.color": on_primary,
            "text.press.color": on_primary,
            "text.toggle.color": on_primary,
        },
        "MenuBar": {
            "text.normal.color": on_surface,
            "text.focus.color": on_primary,
            "text.press.color": on_primary,
            "text.toggle.color": on_primary,
        },
        "MenuBarItem": {
            "text.normal.color": on_surface,
            "text.focus.color": on_primary,
            "text.press.color": on_primary,
            "text.toggle.color": on_primary,
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

    KVANTUM_CONFIG.write_text(text)


def main() -> None:
    if not COLORS_JSON.exists():
        return

    colors = load_colors()
    update_kdeglobals(colors)
    update_qtct_configs()
    update_dolphinrc()
    update_kvantum_config(colors)


if __name__ == "__main__":
    main()
