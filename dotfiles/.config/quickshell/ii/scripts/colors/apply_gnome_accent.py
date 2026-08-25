#!/usr/bin/env python3
"""Apply a wallpaper-derived GNOME accent in Hyprland.

GNOME Shell extensions do not run under Hyprland, but GTK/libadwaita apps still
honour org.gnome.desktop.interface accent-color. This script maps the generated
wallpaper primary colour to GNOME's fixed accent enum without clobbering the
user's selected GTK, icon, or cursor themes.
"""

from __future__ import annotations

import colorsys
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote, urlparse


HEX_RE = re.compile(r"^#?[0-9a-fA-F]{6}$")
RGB_RE = re.compile(r"(?:srgb|rgb)\((\d+),(\d+),(\d+)\)")


def xdg_path(env_name: str, fallback: str) -> Path:
    return Path(os.environ.get(env_name, fallback)).expanduser()


HOME = Path.home()
XDG_CONFIG_HOME = xdg_path("XDG_CONFIG_HOME", str(HOME / ".config"))
XDG_STATE_HOME = xdg_path("XDG_STATE_HOME", str(HOME / ".local/state"))
COLORS_JSON = XDG_STATE_HOME / "quickshell/user/generated/colors.json"
SHELL_CONFIG = XDG_CONFIG_HOME / "illogical-impulse/config.json"
WALLPAPER_PATH = XDG_STATE_HOME / "quickshell/user/generated/wallpaper/path.txt"


def normalise_hex(value: str | None) -> str | None:
    if not value:
        return None
    value = value.strip()
    if not HEX_RE.match(value):
        return None
    return value if value.startswith("#") else f"#{value}"


def read_generated_primary() -> str | None:
    try:
        data = json.loads(COLORS_JSON.read_text())
    except Exception:
        return None

    for key in ("primary", "surface_tint", "secondary"):
        colour = normalise_hex(data.get(key))
        if colour:
            return colour
    return None


def file_uri_to_path(value: str) -> str:
    value = value.strip().strip("'\"")
    if value.startswith("file://"):
        parsed = urlparse(value)
        return unquote(parsed.path)
    return value


def read_wallpaper_path() -> Path | None:
    try:
        config = json.loads(SHELL_CONFIG.read_text())
        background = config.get("background", {})
        wallpaper = background.get("wallpaperPath") or ""
        thumbnail = background.get("thumbnailPath") or ""
        lower = wallpaper.lower()
        if lower.endswith((".mp4", ".webm", ".mkv", ".avi", ".mov")) and thumbnail:
            path = thumbnail
        else:
            path = wallpaper
        if path:
            return Path(file_uri_to_path(path)).expanduser()
    except Exception:
        pass

    try:
        path = WALLPAPER_PATH.read_text().strip()
        if path:
            return Path(file_uri_to_path(path)).expanduser()
    except Exception:
        pass

    for key in ("picture-uri-dark", "picture-uri"):
        try:
            result = subprocess.run(
                ["gsettings", "get", "org.gnome.desktop.background", key],
                check=False,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
            )
        except FileNotFoundError:
            continue
        path = file_uri_to_path(result.stdout)
        if path:
            return Path(path).expanduser()
    return None


def average_image_colour(path: Path) -> str | None:
    if not path.is_file():
        return None
    try:
        result = subprocess.run(
            [
                "magick",
                str(path),
                "-resize",
                "1x1!",
                "-format",
                "%[pixel:p{0,0}]",
                "info:",
            ],
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
    except FileNotFoundError:
        return None

    text = result.stdout.strip()
    if HEX_RE.match(text):
        return normalise_hex(text)
    match = RGB_RE.search(text)
    if not match:
        return None
    r, g, b = (max(0, min(255, int(part))) for part in match.groups())
    return f"#{r:02x}{g:02x}{b:02x}"


def pick_gnome_accent(hex_colour: str) -> str:
    raw = hex_colour.lstrip("#")
    r = int(raw[0:2], 16) / 255
    g = int(raw[2:4], 16) / 255
    b = int(raw[4:6], 16) / 255
    hue, saturation, _value = colorsys.rgb_to_hsv(r, g, b)
    if saturation < 0.15:
        return "slate"

    degrees = hue * 360
    if degrees < 15 or degrees >= 345:
        return "red"
    if degrees < 45:
        return "orange"
    if degrees < 75:
        return "yellow"
    if degrees < 150:
        return "green"
    if degrees < 195:
        return "teal"
    if degrees < 255:
        return "blue"
    if degrees < 315:
        return "purple"
    return "pink"


def gsettings_set(schema: str, key: str, value: str) -> None:
    subprocess.run(
        ["gsettings", "set", schema, key, value],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def schema_exists(schema: str) -> bool:
    result = subprocess.run(
        ["gsettings", "list-schemas"],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    return schema in result.stdout.splitlines()


def main() -> int:
    colour = read_generated_primary()
    source = "generated"
    if not colour:
        wallpaper = read_wallpaper_path()
        colour = average_image_colour(wallpaper) if wallpaper else None
        source = str(wallpaper) if wallpaper else "none"

    if not colour:
        print("apply_gnome_accent: no wallpaper colour available", file=sys.stderr)
        return 1

    accent = pick_gnome_accent(colour)
    interface = "org.gnome.desktop.interface"
    gsettings_set(interface, "accent-color", accent)

    print(f"apply_gnome_accent: {accent} from {colour} ({source})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
