#!/usr/bin/env python3

from __future__ import annotations

import os
import struct
import time
import zlib
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:  # Steam shortcuts still sync if Pillow is unavailable.
    Image = None
    ImageDraw = None
    ImageFont = None


HOME = Path.home()
SCRIPT_DIR = HOME / ".config" / "hypr" / "hyprland" / "scripts" / "tv_mode"
APP_DIR = HOME / ".local" / "share" / "applications"
STEAM_DATA_DIR = HOME / ".local" / "share" / "Steam" / "userdata"
SHORTCUT_ICON = "video-display"
ART_DIR_NAME = "steam_art"
SOURCE_ART_DIR_NAME = "source_art"
OBSOLETE_SHORTCUT_NAMES = {
    "TV Web",
}
RENAMED_SHORTCUT_NAMES = {
    "FIFA 19 (RPCS3)": "RPCS3",
}
LEGACY_ART_APPIDS = {
    "RPCS3": (
        4092870270,  # Previous hard-coded FIFA/RPCS3 shortcut id.
        3999110953,  # CRC id for the previous FIFA/RPCS3 shortcut name.
    ),
}

ART_STYLES = {
    "RPCS3": {
        "label": "RPCS3",
        "sub": "PlayStation 3 Emulator",
        "accent": "#6b55d8",
        "bg1": "#10141c",
        "bg2": "#26324a",
        "icon": "3",
        "source": SCRIPT_DIR / "images" / "rpcs3.png",
        "icon_source": SCRIPT_DIR / "images" / "rpcs3.png",
        "footer": "Emulator",
    },
    "TV Web": {
        "label": "Web",
        "sub": "TV",
        "accent": "#4aa3ff",
        "bg1": "#081522",
        "bg2": "#123c69",
        "icon": "WEB",
    },
    "TV YouTube": {
        "label": "YouTube",
        "sub": "TV",
        "accent": "#ff0033",
        "bg1": "#080808",
        "bg2": "#2a1010",
        "icon": "YT",
        "source": SCRIPT_DIR / "images" / "youtube-play-red-logo-png-transparent-background-6.png",
    },
    "TV Netflix": {
        "label": "Netflix",
        "sub": "TV",
        "accent": "#e50914",
        "bg1": "#050505",
        "bg2": "#260406",
        "icon": "N",
        "source": SCRIPT_DIR / "images" / SOURCE_ART_DIR_NAME / "netflix-wordmark.png",
        "icon_source": SCRIPT_DIR / "images" / SOURCE_ART_DIR_NAME / "netflix-n-logo.png",
    },
    "TV Rumble": {
        "label": "Rumble",
        "sub": "TV",
        "accent": "#85c742",
        "bg1": "#071007",
        "bg2": "#213c18",
        "icon": "R",
        "source": SCRIPT_DIR / "images" / "rumble-logo-freelogovectors.net_.png",
    },
    "TV Odysee": {
        "label": "Odysee",
        "sub": "TV",
        "accent": "#ef1970",
        "bg1": "#0e0712",
        "bg2": "#2b1434",
        "icon": "O",
    },
}

PRESERVED_SHORTCUT_FIELDS = (
    "LaunchOptions",
    "LastPlayTime",
)


def encode_app_id(exe: str, app_name: str) -> int:
    return (zlib.crc32(f"{exe}{app_name}".encode("utf-8")) | 0x80000000) & 0xFFFFFFFF


class BinaryVdfReader:
    def __init__(self, data: bytes):
        self.data = data
        self.pos = 0

    def read_byte(self) -> int:
        value = self.data[self.pos]
        self.pos += 1
        return value

    def read_cstring(self) -> str:
        end = self.data.index(0, self.pos)
        value = self.data[self.pos:end].decode("utf-8")
        self.pos = end + 1
        return value

    def read_object(self) -> dict:
        result: dict[str, object] = {}

        while True:
            value_type = self.read_byte()
            if value_type == 0x08:
                return result

            key = self.read_cstring()

            if value_type == 0x00:
                result[key] = self.read_object()
            elif value_type == 0x01:
                result[key] = self.read_cstring()
            elif value_type == 0x02:
                result[key] = struct.unpack_from("<I", self.data, self.pos)[0]
                self.pos += 4
            else:
                raise ValueError(f"Unsupported VDF type: {value_type:#x}")


def write_cstring(parts: list[bytes], value: str) -> None:
    parts.append(value.encode("utf-8") + b"\x00")


def write_object(parts: list[bytes], obj: dict[str, object]) -> None:
    for key, value in obj.items():
        if isinstance(value, dict):
            parts.append(b"\x00")
            write_cstring(parts, key)
            write_object(parts, value)
        elif isinstance(value, int):
            parts.append(b"\x02")
            write_cstring(parts, key)
            parts.append(struct.pack("<I", value))
        else:
            parts.append(b"\x01")
            write_cstring(parts, key)
            write_cstring(parts, str(value))

    parts.append(b"\x08")


def parse_shortcuts(path: Path) -> list[dict[str, object]]:
    if not path.exists():
        return []

    root = BinaryVdfReader(path.read_bytes()).read_object()
    shortcuts_root = root.get("shortcuts", {})
    if not isinstance(shortcuts_root, dict):
        return []

    shortcuts: list[dict[str, object]] = []
    for key in sorted(shortcuts_root.keys(), key=lambda item: int(item)):
        entry = shortcuts_root[key]
        if isinstance(entry, dict):
            shortcuts.append(entry)
    return shortcuts


def dump_shortcuts(path: Path, shortcuts: list[dict[str, object]]) -> None:
    shortcuts_root = {str(index): entry for index, entry in enumerate(shortcuts)}
    root = {"shortcuts": shortcuts_root}
    parts: list[bytes] = []
    write_object(parts, root)
    path.write_bytes(b"".join(parts))


def detect_steam_user() -> Path:
    user_dirs = [path for path in STEAM_DATA_DIR.iterdir() if path.is_dir() and path.name.isdigit() and path.name != "0"]
    if not user_dirs:
        raise FileNotFoundError("No non-anonymous Steam userdata directory found.")
    return max(user_dirs, key=lambda path: int(path.name))


def desired_shortcuts() -> list[dict[str, object]]:
    now = int(time.time())
    entries = []
    specs = [
        ("TV YouTube", APP_DIR / "tv-youtube.desktop", SCRIPT_DIR / "launch_browser.sh", "https://www.youtube.com/"),
        ("TV Netflix", APP_DIR / "tv-netflix.desktop", SCRIPT_DIR / "launch_browser.sh", "https://www.netflix.com/browse"),
        ("TV Rumble", APP_DIR / "tv-rumble.desktop", SCRIPT_DIR / "launch_browser.sh", "https://rumble.com/"),
    ]

    for app_name, shortcut_path, script_path, target in specs:
        exe = f'"{script_path}"'
        entry = {
            "appid": encode_app_id(exe, app_name),
            "AppName": app_name,
            "Exe": exe,
            "StartDir": f'"{SCRIPT_DIR}"',
            "icon": str(art_icon_path(app_name)),
            "ShortcutPath": str(shortcut_path),
            "LaunchOptions": target,
            "IsHidden": 0,
            "AllowDesktopConfig": 0,
            "AllowOverlay": 0,
            "OpenVR": 0,
            "Devkit": 0,
            "DevkitGameID": "",
            "DevkitOverrideAppID": 0,
            "LastPlayTime": now,
            "FlatpakAppID": "",
            "tags": {"0": "TV"},
        }
        entries.append(entry)

    rpcs3_exe = f'"{SCRIPT_DIR / "launch_rpcs3_steam.sh"}"'
    entries.append(
        {
            "appid": 3749863798,
            "AppName": "RPCS3",
            "Exe": rpcs3_exe,
            "StartDir": f'"{SCRIPT_DIR}"',
            "icon": str(art_icon_path("RPCS3")),
            "ShortcutPath": str(APP_DIR / "RPCS3" / "RPCS3.desktop"),
            "LaunchOptions": "",
            "IsHidden": 0,
            "AllowDesktopConfig": 0,
            "AllowOverlay": 0,
            "OpenVR": 0,
            "Devkit": 0,
            "DevkitGameID": "",
            "DevkitOverrideAppID": 0,
            "LastPlayTime": now,
            "FlatpakAppID": "",
            "sortas": "RPCS3",
            "tags": {"0": "RPCS3"},
        }
    )

    return entries


def with_tv_icon(entry: dict[str, object]) -> dict[str, object]:
    app_name = entry.get("AppName")
    if not isinstance(app_name, str) or not app_name.startswith("TV"):
        return entry

    icon = entry.get("icon")
    if icon not in ("", SHORTCUT_ICON, None):
        return entry

    updated = dict(entry)
    updated["icon"] = str(art_icon_path(app_name))
    return updated


def merge_shortcut(existing: dict[str, object], desired: dict[str, object]) -> dict[str, object]:
    merged = dict(desired)

    for field in PRESERVED_SHORTCUT_FIELDS:
        if field == "LaunchOptions" and desired.get("AppName") == "RPCS3":
            continue
        if field in existing:
            merged[field] = existing[field]

    existing_icon = existing.get("icon")
    desired_icon = desired.get("icon")
    if isinstance(existing_icon, str) and existing_icon and desired_icon == SHORTCUT_ICON:
        merged["icon"] = existing_icon

    return with_tv_icon(merged)



def merge_shortcuts(existing: list[dict[str, object]], desired: list[dict[str, object]]) -> list[dict[str, object]]:
    desired_by_name = {entry["AppName"]: entry for entry in desired}
    merged: list[dict[str, object]] = []
    seen: set[str] = set()

    for entry in existing:
        app_name = entry.get("AppName")
        if isinstance(app_name, str) and app_name in RENAMED_SHORTCUT_NAMES:
            app_name = RENAMED_SHORTCUT_NAMES[app_name]
        if isinstance(app_name, str) and app_name in OBSOLETE_SHORTCUT_NAMES:
            continue
        if isinstance(app_name, str) and app_name in desired_by_name:
            merged.append(merge_shortcut(entry, desired_by_name[app_name]))
            seen.add(app_name)
        else:
            merged.append(with_tv_icon(entry))

    for app_name in sorted(desired_by_name):
        if app_name not in seen:
            merged.append(desired_by_name[app_name])

    return merged


def hex_color(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[index:index + 2], 16) for index in (0, 2, 4))


def slugify(value: str) -> str:
    return "".join(char.lower() if char.isalnum() else "-" for char in value).strip("-")


def art_icon_path(app_name: str) -> Path:
    return SCRIPT_DIR / "images" / ART_DIR_NAME / f"{slugify(app_name)}-icon.png"


def art_style(app_name: str) -> dict[str, object]:
    if app_name in ART_STYLES:
        return ART_STYLES[app_name]

    label = app_name[3:] if app_name.startswith("TV ") else app_name
    return {
        "label": label,
        "sub": "TV",
        "accent": "#2dd4bf",
        "bg1": "#07111c",
        "bg2": "#17303a",
        "icon": "".join(word[:1] for word in label.split())[:3].upper() or "TV",
    }


def load_font(size: int, bold: bool = False):
    if ImageFont is None:
        return None

    candidates = [
        "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/TTF/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/TTF/Inter-Bold.ttf" if bold else "/usr/share/fonts/TTF/Inter-Regular.ttf",
    ]

    for candidate in candidates:
        if Path(candidate).exists():
            return ImageFont.truetype(candidate, size)

    return ImageFont.load_default()


def text_size(draw, text: str, font) -> tuple[int, int]:
    box = draw.textbbox((0, 0), text, font=font)
    return box[2] - box[0], box[3] - box[1]


def load_font_to_fit(draw, text: str, max_width: int, size: int, bold: bool = False, min_size: int = 12):
    font = load_font(size, bold=bold)
    while size > min_size and text_size(draw, text, font)[0] > max_width:
        size -= 2
        font = load_font(size, bold=bold)
    return font


def draw_centered_text(draw, xy: tuple[int, int], text: str, font, fill, spacing: int = 0) -> None:
    x, y = xy
    width, height = text_size(draw, text, font)
    draw.text((x - width / 2, y - height / 2 - spacing), text, font=font, fill=fill)


def make_background(size: tuple[int, int], style: dict[str, object]):
    width, height = size
    bg1 = hex_color(str(style["bg1"]))
    bg2 = hex_color(str(style["bg2"]))
    accent = hex_color(str(style["accent"]))
    image = Image.new("RGBA", size)
    pixels = image.load()

    for y in range(height):
        for x in range(width):
            ratio = (x / max(width - 1, 1) * 0.45) + (y / max(height - 1, 1) * 0.55)
            base = tuple(int(bg1[i] * (1 - ratio) + bg2[i] * ratio) for i in range(3))
            pixels[x, y] = (*base, 255)

    draw = ImageDraw.Draw(image, "RGBA")
    stripe = max(14, width // 80)
    for offset in range(-height, width, stripe * 3):
        draw.line((offset, height, offset + height, 0), fill=(*accent, 26), width=stripe)
    draw.rectangle((0, 0, width, max(8, height // 55)), fill=(*accent, 220))
    return image


def paste_source_logo(image, style: dict[str, object], box: tuple[int, int, int, int], source_key: str = "source") -> bool:
    source = style.get(source_key)
    if not isinstance(source, Path) or not source.exists():
        return False

    logo = Image.open(source).convert("RGBA")
    max_width = box[2] - box[0]
    max_height = box[3] - box[1]
    ratio = min(max_width / logo.width, max_height / logo.height)
    new_size = (max(1, int(logo.width * ratio)), max(1, int(logo.height * ratio)))
    logo = logo.resize(new_size, Image.Resampling.LANCZOS)
    x = box[0] + (max_width - logo.width) // 2
    y = box[1] + (max_height - logo.height) // 2
    image.alpha_composite(logo, (x, y))
    return True


def make_art_image(app_name: str, size: tuple[int, int], variant: str):
    style = art_style(app_name)
    width, height = size
    accent = hex_color(str(style["accent"]))
    label = str(style["label"])
    sub = str(style["sub"])
    footer = str(style.get("footer", "Big Picture shortcut"))

    if variant == "logo":
        image = Image.new("RGBA", size, (0, 0, 0, 0))
    else:
        image = make_background(size, style)

    draw = ImageDraw.Draw(image, "RGBA")
    text_max_width = int(width * (0.86 if variant == "portrait" else 0.48))
    title_font = load_font_to_fit(
        draw,
        label,
        text_max_width,
        max(24, int(height * (0.15 if variant == "portrait" else 0.20))),
        bold=True,
    )
    sub_font = load_font_to_fit(draw, sub, text_max_width, max(16, int(height * 0.055)), bold=True)
    small_font = load_font(max(12, int(height * 0.035)), bold=True)
    sub_fill = (214, 221, 235, 245) if app_name == "RPCS3" else (*accent, 255)

    if variant == "icon":
        image = make_background(size, style)
        draw = ImageDraw.Draw(image, "RGBA")
        draw.rounded_rectangle((36, 36, width - 36, height - 36), radius=70, fill=(*accent, 52), outline=(*accent, 230), width=8)
        if not paste_source_logo(image, style, (86, 86, width - 86, height - 86), "icon_source"):
            draw_centered_text(draw, (width // 2, height // 2), str(style["icon"]), load_font(150, bold=True), (255, 255, 255, 255))
        return image

    if variant == "logo":
        if not paste_source_logo(image, style, (80, 140, width - 80, height - 140)):
            draw_centered_text(draw, (width // 2, height // 2), label, load_font(170, bold=True), (255, 255, 255, 255))
        return image

    if variant == "portrait":
        logo_box = (75, 125, width - 75, 390)
        text_y = int(height * 0.60)
    else:
        logo_box = (int(width * 0.08), int(height * 0.18), int(width * 0.44), int(height * 0.82))
        text_y = height // 2

    used_logo = paste_source_logo(image, style, logo_box)
    if not used_logo:
        badge_size = min(width, height) * (0.26 if variant == "portrait" else 0.34)
        cx = width // 2 if variant == "portrait" else int(width * 0.26)
        cy = int(height * 0.28) if variant == "portrait" else height // 2
        draw.ellipse((cx - badge_size / 2, cy - badge_size / 2, cx + badge_size / 2, cy + badge_size / 2), fill=(*accent, 210))
        draw_centered_text(draw, (cx, cy), str(style["icon"]), load_font(int(badge_size * 0.38), bold=True), (255, 255, 255, 255))

    text_x = width // 2 if variant == "portrait" else int(width * 0.68)
    draw_centered_text(draw, (text_x, text_y - int(height * 0.06)), label, title_font, (255, 255, 255, 255))
    draw_centered_text(draw, (text_x, text_y + int(height * 0.10)), sub, sub_font, sub_fill)

    if variant == "hero":
        draw.text((int(width * 0.06), height - int(height * 0.14)), footer, font=small_font, fill=(255, 255, 255, 160))

    return image


def save_art_if_missing(path: Path, app_name: str, size: tuple[int, int], variant: str, *, overwrite: bool = False) -> bool:
    if (path.exists() and not overwrite) or Image is None:
        return False

    path.parent.mkdir(parents=True, exist_ok=True)
    image = make_art_image(app_name, size, variant)
    image.save(path)
    return True


def ensure_grid_artwork(steam_user_dir: Path, shortcuts: list[dict[str, object]]) -> int:
    if Image is None:
        return 0

    grid_dir = steam_user_dir / "config" / "grid"
    created = 0

    for entry in shortcuts:
        app_name = entry.get("AppName")
        appid = entry.get("appid")
        if not isinstance(app_name, str) or (not app_name.startswith("TV") and app_name != "RPCS3"):
            continue
        if not isinstance(appid, int):
            continue

        overwrite = app_name == "RPCS3"
        artwork_appids = (appid, *LEGACY_ART_APPIDS.get(app_name, ()))
        for artwork_appid in artwork_appids:
            created += save_art_if_missing(grid_dir / f"{artwork_appid}.png", app_name, (920, 430), "landscape", overwrite=overwrite)
            created += save_art_if_missing(grid_dir / f"{artwork_appid}p.png", app_name, (600, 900), "portrait", overwrite=overwrite)
            created += save_art_if_missing(grid_dir / f"{artwork_appid}_hero.png", app_name, (1920, 620), "hero", overwrite=overwrite)
            created += save_art_if_missing(grid_dir / f"{artwork_appid}_logo.png", app_name, (1280, 720), "logo", overwrite=overwrite)
            created += save_art_if_missing(grid_dir / f"{artwork_appid}_icon.png", app_name, (512, 512), "icon", overwrite=overwrite)
        created += save_art_if_missing(art_icon_path(app_name), app_name, (512, 512), "icon", overwrite=overwrite)

    return created


def cleanup_obsolete_artwork(steam_user_dir: Path, existing: list[dict[str, object]]) -> int:
    grid_dir = steam_user_dir / "config" / "grid"
    removed = 0

    for entry in existing:
        app_name = entry.get("AppName")
        appid = entry.get("appid")
        if not isinstance(app_name, str) or app_name not in OBSOLETE_SHORTCUT_NAMES:
            continue
        if not isinstance(appid, int):
            continue

        for path in (
            grid_dir / f"{appid}.png",
            grid_dir / f"{appid}p.png",
            grid_dir / f"{appid}_hero.png",
            grid_dir / f"{appid}_logo.png",
            grid_dir / f"{appid}_icon.png",
            art_icon_path(app_name),
        ):
            if path.exists():
                path.unlink()
                removed += 1

    for path in (APP_DIR / "tv-web.desktop",):
        if path.exists():
            path.unlink()
            removed += 1

    return removed


def backup_file(path: Path) -> None:
    if not path.exists():
        return
    stamp = time.strftime("%Y%m%d-%H%M%S")
    backup = path.with_name(f"{path.name}.bak-{stamp}")
    backup.write_bytes(path.read_bytes())


def main() -> int:
    steam_user_dir = detect_steam_user()
    config_dir = steam_user_dir / "config"
    shortcuts_path = config_dir / "shortcuts.vdf"
    config_dir.mkdir(parents=True, exist_ok=True)

    existing = parse_shortcuts(shortcuts_path)
    updated = merge_shortcuts(existing, desired_shortcuts())

    removed_obsolete = cleanup_obsolete_artwork(steam_user_dir, existing)
    artwork_created = ensure_grid_artwork(steam_user_dir, updated)

    if updated != existing:
        backup_file(shortcuts_path)
        dump_shortcuts(shortcuts_path, updated)
        print(f"Updated Steam shortcuts: {shortcuts_path}")
    else:
        print(f"Steam shortcuts already current: {shortcuts_path}")

    if artwork_created:
        print(f"Created Steam artwork files: {artwork_created}")
    if removed_obsolete:
        print(f"Removed obsolete TV Web files: {removed_obsolete}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
