#!/usr/bin/env python3

import json
import os
from pathlib import Path


XDG_STATE_HOME = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local" / "state"))
XDG_CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))

COLORS_PATH = XDG_STATE_HOME / "quickshell" / "user" / "generated" / "colors.json"
SETTINGS_PATH = XDG_CONFIG_HOME / "VSCodium" / "User" / "settings.json"


def read_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        try:
            return json.load(handle)
        except json.JSONDecodeError:
            return {}


def write_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=4)
        handle.write("\n")


def alpha(hex_color: str, opacity: str) -> str:
    return f"{hex_color}{opacity}"


def build_customizations(colors: dict) -> dict:
    glass_surface = alpha(colors["surface"], "c8")
    glass_base = alpha(colors["background"], "c8")
    glass_lowest = alpha(colors["surface_container_lowest"], "b8")
    glass_low = alpha(colors["surface_container_low"], "c4")
    glass_container = alpha(colors["surface_container"], "cc")
    glass_high = alpha(colors["surface_container_high"], "d0")

    return {
        "editor.background": glass_surface,
        "editor.foreground": colors["on_surface"],
        "editor.lineHighlightBackground": alpha(colors["surface_container"], "88"),
        "editor.selectionBackground": f'{colors["primary"]}40',
        "editor.selectionHighlightBackground": f'{colors["secondary"]}30',
        "editorCursor.foreground": colors["primary"],
        "editorWhitespace.foreground": f'{colors["outline"]}55',
        "editorIndentGuide.background1": f'{colors["outline_variant"]}80',
        "editorIndentGuide.activeBackground1": colors["outline"],
        "editorLineNumber.foreground": colors["outline"],
        "editorLineNumber.activeForeground": colors["primary"],
        "editorGroupHeader.tabsBackground": glass_surface,
        "editorGroupHeader.tabsBorder": colors["outline_variant"],
        "tab.activeBackground": glass_low,
        "tab.activeForeground": colors["on_surface"],
        "tab.inactiveBackground": glass_surface,
        "tab.inactiveForeground": colors["on_surface_variant"],
        "tab.border": colors["outline_variant"],
        "tab.activeBorderTop": colors["primary"],
        "tab.hoverBackground": glass_container,
        "titleBar.activeBackground": glass_low,
        "titleBar.activeForeground": colors["on_surface"],
        "titleBar.inactiveBackground": glass_surface,
        "titleBar.inactiveForeground": colors["on_surface_variant"],
        "activityBar.background": glass_lowest,
        "activityBar.activeBorder": colors["primary"],
        "activityBar.activeFocusBorder": colors["primary"],
        "activityBar.foreground": colors["primary"],
        "activityBar.inactiveForeground": colors["on_surface_variant"],
        "activityBar.border": colors["outline_variant"],
        "activityBarTop.activeBorder": colors["primary"],
        "activityBarBadge.background": colors["primary"],
        "activityBarBadge.foreground": colors["on_primary"],
        "sideBar.background": glass_surface,
        "sideBar.foreground": colors["on_surface"],
        "sideBar.border": colors["outline_variant"],
        "sideBarSectionHeader.background": glass_low,
        "sideBarSectionHeader.foreground": colors["on_surface"],
        "list.activeSelectionBackground": colors["secondary_container"],
        "list.activeSelectionForeground": colors["on_secondary_container"],
        "list.hoverBackground": glass_container,
        "list.inactiveSelectionBackground": glass_high,
        "menu.background": glass_container,
        "menu.foreground": colors["on_surface"],
        "menu.border": colors["outline_variant"],
        "menu.separatorBackground": colors["outline_variant"],
        "menu.selectionBackground": colors["primary"],
        "menu.selectionForeground": colors["on_primary"],
        "menu.selectionBorder": colors["primary"],
        "menubar.selectionBackground": f'{colors["primary"]}22',
        "menubar.selectionForeground": colors["primary"],
        "menubar.selectionBorder": colors["primary"],
        "statusBar.background": glass_low,
        "statusBar.foreground": colors["on_surface"],
        "statusBar.border": colors["outline_variant"],
        "statusBar.debuggingBackground": colors["tertiary_container"],
        "statusBar.debuggingForeground": colors["on_tertiary_container"],
        "panel.background": glass_surface,
        "panel.border": colors["outline_variant"],
        "terminal.background": glass_base,
        "terminal.foreground": colors["on_background"],
        "terminal.ansiBlack": colors["surface_container_lowest"],
        "terminal.ansiRed": colors["error"],
        "terminal.ansiGreen": colors["tertiary"],
        "terminal.ansiYellow": colors["primary"],
        "terminal.ansiBlue": colors["secondary"],
        "terminal.ansiMagenta": colors["tertiary_fixed_dim"],
        "terminal.ansiCyan": colors["secondary_fixed_dim"],
        "terminal.ansiWhite": colors["on_surface"],
        "terminal.ansiBrightBlack": colors["outline_variant"],
        "terminal.ansiBrightRed": colors["error"],
        "terminal.ansiBrightGreen": colors["tertiary_fixed"],
        "terminal.ansiBrightYellow": colors["primary_fixed"],
        "terminal.ansiBrightBlue": colors["secondary_fixed"],
        "terminal.ansiBrightMagenta": colors["tertiary"],
        "terminal.ansiBrightCyan": colors["secondary"],
        "terminal.ansiBrightWhite": colors["inverse_surface"],
        "button.background": colors["primary"],
        "button.foreground": colors["on_primary"],
        "button.hoverBackground": colors["primary_fixed_dim"],
        "input.background": glass_container,
        "input.foreground": colors["on_surface"],
        "input.border": colors["outline"],
        "focusBorder": colors["primary"],
        "dropdown.background": glass_container,
        "dropdown.foreground": colors["on_surface"],
        "dropdown.border": colors["outline"],
        "badge.background": colors["secondary_container"],
        "badge.foreground": colors["on_secondary_container"],
        "notifications.background": glass_low,
        "notifications.foreground": colors["on_surface"],
        "notificationCenterHeader.background": glass_container,
        "pickerGroup.foreground": colors["primary"],
    }


def is_dark(hex_color: str) -> bool:
    hex_value = hex_color.lstrip("#")
    red = int(hex_value[0:2], 16)
    green = int(hex_value[2:4], 16)
    blue = int(hex_value[4:6], 16)
    luminance = (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255
    return luminance < 0.5


def main() -> int:
    if not COLORS_PATH.exists():
        raise SystemExit(f"Missing palette file: {COLORS_PATH}")

    colors = read_json(COLORS_PATH)
    settings = read_json(SETTINGS_PATH) if SETTINGS_PATH.exists() else {}

    settings["workbench.colorTheme"] = "Default Dark Modern" if is_dark(colors["background"]) else "Default Light Modern"
    settings["workbench.colorCustomizations"] = build_customizations(colors)
    settings["material-code.primaryColor"] = colors["primary"]

    write_json(SETTINGS_PATH, settings)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
