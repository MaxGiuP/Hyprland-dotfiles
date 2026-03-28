#!/usr/bin/env python3

import configparser
import json
import os
from pathlib import Path


HOME = Path(os.environ.get("HOME", str(Path.home())))
XDG_CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config"))
XDG_STATE_HOME = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local" / "state"))

COLORS_JSON = XDG_STATE_HOME / "quickshell" / "user" / "generated" / "colors.json"
ILLOGICAL_CONFIG = XDG_CONFIG_HOME / "illogical-impulse" / "config.json"
FIREFOX_ROOT = HOME / ".mozilla" / "firefox"
FIREFOX_GENERATED_NAME = "generated_quickshell_theme.css"


def load_colors() -> dict[str, str]:
    with COLORS_JSON.open() as f:
        return json.load(f)


def is_gtk_preferred() -> bool:
    if not ILLOGICAL_CONFIG.exists():
        return True
    with ILLOGICAL_CONFIG.open() as f:
        cfg = json.load(f)
    return bool(cfg.get("appearance", {}).get("wallpaperTheming", {}).get("enableGtkApps", True))


def get(colors: dict[str, str], key: str, fallback: str) -> str:
    return colors.get(key, fallback)


def hex_to_rgb(hex_color: str) -> tuple[int, int, int]:
    value = hex_color.lstrip("#")
    return tuple(int(value[i : i + 2], 16) for i in (0, 2, 4))


def rgb_to_hex(rgb: tuple[int, int, int]) -> str:
    return "#{:02x}{:02x}{:02x}".format(*rgb)


def rgb_to_signed_bgra(rgb: tuple[int, int, int]) -> int:
    r, g, b = rgb
    value = 0xFF000000 | (b << 16) | (g << 8) | r
    return value - 2**32 if value >= 2**31 else value


def mix(a: str, b: str, amount: float) -> str:
    ar, ag, ab = hex_to_rgb(a)
    br, bg, bb = hex_to_rgb(b)
    rgb = (
        round(ar + (br - ar) * amount),
        round(ag + (bg - ag) * amount),
        round(ab + (bb - ab) * amount),
    )
    return rgb_to_hex(rgb)


def alpha(hex_color: str, opacity: float) -> str:
    r, g, b = hex_to_rgb(hex_color)
    return f"rgba({r}, {g}, {b}, {opacity:.3f})"


def hex_to_rgba_list(hex_color: str, opacity: float | None = None) -> list[int]:
    values = list(hex_to_rgb(hex_color))
    if opacity is not None:
        values.append(round(max(0.0, min(1.0, opacity)) * 255))
    return values


def brightness(hex_color: str) -> float:
    r, g, b = hex_to_rgb(hex_color)
    return (r * 299 + g * 587 + b * 114) / 1000


def is_dark(hex_color: str) -> bool:
    return brightness(hex_color) < 128


def contrast_text(background: str, dark: str = "#16110d", light: str = "#f7efe8") -> str:
    return light if is_dark(background) else dark


def rgb_list(hex_color: str) -> list[int]:
    return list(hex_to_rgb(hex_color))


def muted(hex_color: str, bg: str, amount: float = 0.45) -> str:
    """Blend fg toward bg — produces a dimmed text colour."""
    return mix(hex_color, bg, amount)


def dedupe(items: list[str]) -> list[str]:
    seen: set[str] = set()
    unique: list[str] = []
    for item in items:
        if item in seen:
            continue
        seen.add(item)
        unique.append(item)
    return unique


def firefox_profile_dir() -> Path | None:
    profiles_ini = FIREFOX_ROOT / "profiles.ini"
    if not profiles_ini.exists():
        return None

    cfg = configparser.RawConfigParser(interpolation=None)
    cfg.read(profiles_ini)

    install_default = None
    for section in cfg.sections():
        if section.startswith("Install") and cfg.has_option(section, "Default"):
            install_default = cfg.get(section, "Default")
            break
    if install_default:
        return FIREFOX_ROOT / install_default

    for section in cfg.sections():
        if section.startswith("Profile") and cfg.get(section, "Default", fallback="0") == "1":
            return FIREFOX_ROOT / cfg.get(section, "Path")
    return None


def ensure_firefox_import(custom_chrome: Path) -> None:
    import_line = f'@import "{FIREFOX_GENERATED_NAME}";'
    if custom_chrome.exists():
        text = custom_chrome.read_text()
    else:
        text = "/* Add your own custom styles here */\n"

    if import_line not in text:
        if text and not text.endswith("\n"):
            text += "\n"
        text = f"{import_line}\n\n{text}"
        custom_chrome.write_text(text)


def build_firefox_css(colors: dict[str, str]) -> str:
    bg = get(colors, "background", "#19120c")
    surface = get(colors, "surface", bg)
    container_low = get(colors, "surface_container_low", mix(surface, "#ffffff", 0.04))
    container = get(colors, "surface_container", mix(surface, "#ffffff", 0.08))
    container_high = get(colors, "surface_container_high", mix(surface, "#ffffff", 0.12))
    outline = get(colors, "outline", mix(surface, "#ffffff", 0.38))
    primary = get(colors, "primary", "#ffb878")
    primary_container = get(colors, "primary_container", mix(primary, surface, 0.55))
    secondary_container = get(colors, "secondary_container", mix(primary, surface, 0.72))
    toolbar_fg = contrast_text(container)
    tab_fg = contrast_text(container_low)
    muted_fg = mix(toolbar_fg, container, 0.42)
    urlbar_bg = mix(surface, "#ffffff" if is_dark(surface) else "#000000", 0.08)
    urlbar_inactive_bg = mix(surface, "#ffffff" if is_dark(surface) else "#000000", 0.04)
    popup_bg = alpha(container, 0.96)
    header_bg = alpha(container, 0.97)
    inactive_header_bg = alpha(container_low, 0.97)
    popup_border = alpha(outline, 0.48)
    hover_bg = alpha(toolbar_fg, 0.10 if is_dark(container) else 0.08)
    active_bg = alpha(toolbar_fg, 0.16 if is_dark(container) else 0.14)
    shadow = (
        f"0 10px 26px {alpha('#000000', 0.28 if is_dark(bg) else 0.16)}, "
        f"0 0 0 1px {alpha(outline, 0.32)}"
    )
    destructive = "#ff5449" if is_dark(bg) else "#c62828"
    destructive_hover = mix(destructive, "#ffffff" if is_dark(bg) else "#000000", 0.10)
    private_header = mix(primary_container, container, 0.25)
    private_tab = mix(primary_container, container, 0.38)

    return f"""/* Generated from Quickshell colors.json. */

:root {{
  --gnome-browser-before-load-background: {bg} !important;
  --gnome-content-page-dialog-background: {container} !important;
  --gnome-content-page-background: {bg} !important;
  --gnome-content-box-background: {surface} !important;
  --gnome-content-page-color: {contrast_text(bg)} !important;
  --theme-primary-color: {primary} !important;
  --theme-primary-hover-color: {mix(primary, "#ffffff" if is_dark(primary) else "#000000", 0.10)} !important;
  --theme-primary-active-color: {mix(primary, "#ffffff" if is_dark(primary) else "#000000", 0.18)} !important;
  --in-content-link-color: {primary} !important;
  --in-content-link-color-hover: {mix(primary, "#ffffff" if is_dark(primary) else "#000000", 0.12)} !important;
  --toolbar-bgcolor: {header_bg} !important;
  --toolbar-color: {toolbar_fg} !important;
  --toolbar-field-background-color: {urlbar_inactive_bg} !important;
  --toolbar-field-color: {contrast_text(urlbar_inactive_bg)} !important;
  --toolbar-field-border-color: {alpha(outline, 0.42)} !important;
  --toolbar-field-focus-background-color: {urlbar_bg} !important;
  --toolbar-field-focus-color: {contrast_text(urlbar_bg)} !important;
  --toolbar-field-focus-border-color: {primary} !important;
  --toolbar-field-focus-box-shadow: 0 0 0 1px {primary}, 0 10px 26px {alpha("#000000", 0.24 if is_dark(bg) else 0.14)} !important;
  --toolbarbutton-icon-fill: {toolbar_fg} !important;
  --toolbarbutton-hover-background: {hover_bg} !important;
  --toolbarbutton-active-background: {active_bg} !important;
  --arrowpanel-background: {popup_bg} !important;
  --arrowpanel-color: {contrast_text(container)} !important;
  --arrowpanel-border-color: {popup_border} !important;
  --panel-background: {popup_bg} !important;
  --panel-color: {contrast_text(container)} !important;
  --panel-border-color: {popup_border} !important;
  --lwt-accent-color: {header_bg} !important;
  --lwt-text-color: {toolbar_fg} !important;
  --tab-selected-bgcolor: {surface} !important;
  --tab-selected-textcolor: {contrast_text(surface)} !important;
  --tab-hover-background-color: {hover_bg} !important;
  --tab-loading-fill: {primary} !important;
  --focus-outline-color: {primary} !important;
  --button-primary-bgcolor: {primary} !important;
  --button-primary-color: {contrast_text(primary)} !important;
  --button-primary-hover-bgcolor: {mix(primary, "#ffffff" if is_dark(primary) else "#000000", 0.10)} !important;
  --button-primary-active-bgcolor: {mix(primary, "#ffffff" if is_dark(primary) else "#000000", 0.18)} !important;
  --button-primary-border-color: {primary} !important;
  --button-text-color-primary: {contrast_text(primary)} !important;
}}

:root {{
  --gnome-toolbar-background: {header_bg} !important;
  --gnome-tabstoolbar-background: {container_low} !important;
  --gnome-findbar-background: {header_bg} !important;
  --gnome-toolbar-color: {toolbar_fg} !important;
  --gnome-toolbar-icon-fill: {toolbar_fg} !important;
  --gnome-toolbar-border-color: {alpha(outline, 0.26)} !important;
  --gnome-inactive-toolbar-color: {muted_fg} !important;
  --gnome-inactive-toolbar-background: {inactive_header_bg} !important;
  --gnome-inactive-toolbar-border-color: {alpha(outline, 0.18)} !important;
  --sidebar-background-color: {surface} !important;
  --gnome-sidebar-background: {surface} !important;
  --gnome-inactive-sidebar-background: {container_low} !important;
  --gnome-sidebar-border-color: {alpha(outline, 0.18)} !important;
  --gnome-menu-background: {popup_bg} !important;
  --gnome-menu-border-color: {popup_border} !important;
  --gnome-popover-background: {popup_bg} !important;
  --gnome-popover-border-color: {popup_border} !important;
  --gnome-popover-shadow: {shadow} !important;
  --gnome-popover-button-hover-background: {hover_bg} !important;
  --gnome-popover-button-active-background: {active_bg} !important;
  --gnome-popover-separator-color: {alpha(outline, 0.18)} !important;
  --gnome-headerbar-background: {header_bg} !important;
  --gnome-headerbar-border-color: {alpha(outline, 0.18)} !important;
  --gnome-headerbar-box-shadow: inset 0 -1px {alpha(outline, 0.14)} !important;
  --gnome-inactive-headerbar-background: {inactive_header_bg} !important;
  --gnome-inactive-headerbar-border-color: {alpha(outline, 0.14)} !important;
  --gnome-inactive-headerbar-box-shadow: inset 0 -1px {alpha(outline, 0.10)} !important;
  --gnome-button-background: linear-gradient(to top, {container_high} 0%, {container} 100%) !important;
  --gnome-button-border-color: {alpha(outline, 0.24)} !important;
  --gnome-button-border-bottom-color: {alpha(outline, 0.32)} !important;
  --gnome-button-box-shadow: inset 0 1px {alpha(toolbar_fg, 0.06)} !important;
  --gnome-button-hover-color: {hover_bg} !important;
  --gnome-button-active-color: {active_bg} !important;
  --gnome-button-hover-background: linear-gradient(to top, {mix(container_high, toolbar_fg, 0.04)} 0%, {mix(container, toolbar_fg, 0.05)} 100%) !important;
  --gnome-button-active-background: {mix(container, toolbar_fg, 0.08)} !important;
  --gnome-button-active-border-color: {alpha(outline, 0.28)} !important;
  --gnome-button-active-border-bottom-color: {alpha(outline, 0.34)} !important;
  --gnome-button-active-box-shadow: inset 0 1px {alpha(toolbar_fg, 0.04)} !important;
  --gnome-button-disabled-background: {container_low} !important;
  --gnome-button-disabled-border-color: {alpha(outline, 0.16)} !important;
  --gnome-inactive-button-background: {container_low} !important;
  --gnome-inactive-button-border-color: {alpha(outline, 0.14)} !important;
  --gnome-button-suggested-action-background: linear-gradient(to top, {primary} 2px, {primary}) !important;
  --gnome-button-suggested-action-border-color: {mix(primary, "#000000", 0.15)} !important;
  --gnome-button-suggested-action-border-bottom-color: {mix(primary, "#000000", 0.28)} !important;
  --gnome-button-suggested-action-box-shadow: inset 0 1px {alpha(contrast_text(primary), 0.08)} !important;
  --gnome-button-suggested-action-hover-background: linear-gradient(to top, {mix(primary, "#ffffff" if is_dark(primary) else "#000000", 0.10)}, {mix(primary, "#ffffff" if is_dark(primary) else "#000000", 0.10)}) !important;
  --gnome-button-suggested-action-active-background: linear-gradient(to top, {mix(primary, "#ffffff" if is_dark(primary) else "#000000", 0.18)}, {mix(primary, "#ffffff" if is_dark(primary) else "#000000", 0.18)}) !important;
  --gnome-button-destructive-action-background: linear-gradient(to top, {destructive} 2px, {destructive}) !important;
  --gnome-button-destructive-action-hover-background: linear-gradient(to top, {destructive_hover}, {destructive_hover}) !important;
  --gnome-button-destructive-action-active-background: linear-gradient(to top, {mix(destructive, "#000000", 0.12)}, {mix(destructive, "#000000", 0.12)}) !important;
  --gnome-headerbar-button-combined-background: {hover_bg} !important;
  --gnome-headerbar-button-hover-background: {hover_bg} !important;
  --gnome-headerbar-button-active-background: {active_bg} !important;
  --gnome-urlbar-background: {urlbar_bg} !important;
  --gnome-urlbar-border-color: {alpha(outline, 0.32)} !important;
  --gnome-urlbar-box-shadow: {shadow} !important;
  --gnome-urlbar-color: {contrast_text(urlbar_bg)} !important;
  --gnome-hover-urlbar-border-color: {alpha(primary, 0.55)} !important;
  --gnome-inactive-urlbar-background: {urlbar_inactive_bg} !important;
  --gnome-inactive-urlbar-border-color: {alpha(outline, 0.22)} !important;
  --gnome-inactive-urlbar-box-shadow: none !important;
  --gnome-inactive-urlbar-color: {contrast_text(urlbar_inactive_bg)} !important;
  --gnome-focused-urlbar-border-color: {primary} !important;
  --gnome-focused-urlbar-highlight-color: {mix(primary, "#ffffff" if is_dark(primary) else "#000000", 0.08)} !important;
  --gnome-private-urlbar-background: {mix(primary_container, urlbar_bg, 0.35)} !important;
  --gnome-tabbar-tab-background: {container_low} !important;
  --gnome-tabbar-tab-color: {tab_fg} !important;
  --gnome-tabbar-tab-border-color: {alpha(outline, 0.14)} !important;
  --gnome-tabbar-tab-hover-background: {mix(container_low, toolbar_fg, 0.06)} !important;
  --gnome-tabbar-tab-hover-border-color: {alpha(outline, 0.16)} !important;
  --gnome-tabbar-tab-hover-color: {toolbar_fg} !important;
  --gnome-tabbar-tab-active-background: {surface} !important;
  --gnome-tabbar-tab-active-border-color: {alpha(outline, 0.18)} !important;
  --gnome-tabbar-tab-active-color: {contrast_text(surface)} !important;
  --gnome-tabbar-tab-active-hover-background: {mix(surface, toolbar_fg, 0.04)} !important;
  --gnome-inactive-tabbar-tab-color: {muted_fg} !important;
  --gnome-inactive-tabbar-tab-background: {container_low} !important;
  --gnome-inactive-tabbar-tab-active-background: {surface} !important;
  --gnome-inactive-tabbar-tab-active-color: {contrast_text(surface)} !important;
  --gnome-tab-attention-icon-color: {primary} !important;
  --gnome-switch-pressed-background: {primary} !important;
  --gnome-switch-pressed-hover-background: {mix(primary, "#ffffff" if is_dark(primary) else "#000000", 0.10)} !important;
  --gnome-switch-pressed-active-background: {mix(primary, "#ffffff" if is_dark(primary) else "#000000", 0.18)} !important;
  --gnome-private-accent: {primary} !important;
  --gnome-private-toolbar-background: {alpha(private_header, 0.97)} !important;
  --gnome-private-inactive-toolbar-background: {inactive_header_bg} !important;
  --gnome-private-menu-background: {popup_bg} !important;
  --gnome-private-headerbar-background: {alpha(private_header, 0.97)} !important;
  --gnome-private-inactive-headerbar-background: {inactive_header_bg} !important;
  --gnome-private-tabbar-tab-hover-background: {mix(private_tab, toolbar_fg, 0.04)} !important;
  --gnome-private-tabbar-tab-active-background: {private_tab} !important;
  --gnome-private-tabbar-tab-active-background-contrast: {mix(private_tab, toolbar_fg, 0.08)} !important;
  --gnome-private-tabbar-tab-active-hover-background: {mix(private_tab, toolbar_fg, 0.10)} !important;
  --gnome-private-inactive-tabbar-tab-hover-background: {mix(container_low, private_tab, 0.30)} !important;
  --gnome-private-inactive-tabbar-tab-active-background: {mix(container_low, private_tab, 0.45)} !important;
  --gnome-private-wordmark: {contrast_text(private_header)} !important;
  --gnome-private-in-content-page-background: {mix(private_header, bg, 0.35)} !important;
  --gnome-private-text-primary-color: {contrast_text(private_header)} !important;
}}

#navigator-toolbox,
#titlebar,
#TabsToolbar,
#nav-bar,
#PersonalToolbar {{
  background: {header_bg} !important;
  color: {toolbar_fg} !important;
}}

#sidebar-box,
#sidebar-header,
#bookmarksPanel,
#historyTree {{
  background: {surface} !important;
  color: {contrast_text(surface)} !important;
}}

#urlbar-background,
#searchbar {{
  background: {urlbar_bg} !important;
  border-color: {alpha(outline, 0.32)} !important;
  color: {contrast_text(urlbar_bg)} !important;
}}

#urlbar[focused="true"] > #urlbar-background,
#searchbar:focus-within {{
  border-color: {primary} !important;
  box-shadow: 0 0 0 1px {primary}, 0 12px 28px {alpha("#000000", 0.24 if is_dark(bg) else 0.14)} !important;
}}

menupopup,
panel,
.panel-arrowcontent,
.PanelUI-subView {{
  background: {popup_bg} !important;
  color: {contrast_text(container)} !important;
  border-color: {popup_border} !important;
}}

toolbarbutton:hover,
.subviewbutton:hover,
.urlbarView-row:hover {{
  background-color: {hover_bg} !important;
}}

toolbarbutton[open="true"],
toolbarbutton:hover:active,
.subviewbutton:hover:active,
.urlbarView-row[selected] {{
  background-color: {active_bg} !important;
}}

.urlbarView-row[selected] .urlbarView-title,
.urlbarView-row[selected] .urlbarView-url,
.subviewbutton[selected] {{
  color: {toolbar_fg} !important;
}}

#tabs-newtab-button,
#new-tab-button,
.tabbrowser-tab {{
  color: {tab_fg} !important;
}}

.tabbrowser-tab[selected="true"] .tab-content {{
  color: {contrast_text(surface)} !important;
}}

#statuspanel-label {{
  background: {container} !important;
  color: {toolbar_fg} !important;
  border-color: {popup_border} !important;
}}
"""


def update_firefox(colors: dict[str, str]) -> None:
    profile_dir = firefox_profile_dir()
    if profile_dir is None:
        return

    chrome_dir = profile_dir / "chrome"
    chrome_dir.mkdir(parents=True, exist_ok=True)
    generated = chrome_dir / FIREFOX_GENERATED_NAME
    custom_chrome = chrome_dir / "customChrome.css"
    generated.write_text(build_firefox_css(colors))
    ensure_firefox_import(custom_chrome)


def main() -> None:
    if not COLORS_JSON.exists():
        return

    colors = load_colors()
    update_firefox(colors)


if __name__ == "__main__":
    main()
