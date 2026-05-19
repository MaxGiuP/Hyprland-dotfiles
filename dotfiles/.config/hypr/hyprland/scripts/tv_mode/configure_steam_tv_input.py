#!/usr/bin/env python3
"""Keep RPCS3 shortcuts out of Steam Input when Steam is not running."""

from __future__ import annotations

from pathlib import Path

APP_IDS = (
    "3749863798",  # Current RPCS3 shortcut id.
    "4092870270",  # Legacy FIFA/RPCS3 shortcut id.
)
LOCALCONFIG = Path.home() / ".local/share/Steam/userdata/165276910/config/localconfig.vdf"

def app_block(app_id: str) -> list[str]:
    return [
        f'\t\t"{app_id}"\n',
        "\t\t{\n",
        '\t\t\t"UseSteamControllerConfig"\t\t"0"\n',
        '\t\t\t"SteamControllerRumble"\t\t"-1"\n',
        '\t\t\t"SteamControllerRumbleIntensity"\t\t"320"\n',
        "\t\t}\n",
    ]


def root_apps_bounds(lines: list[str]) -> tuple[int, int] | None:
    for index, line in enumerate(lines):
        if line == '\t"apps"\n' and index + 1 < len(lines) and lines[index + 1] == "\t{\n":
            depth = 0
            for end in range(index + 1, len(lines)):
                stripped = lines[end].strip()
                if stripped == "{":
                    depth += 1
                elif stripped == "}":
                    depth -= 1
                    if depth == 0:
                        return index + 1, end
    return None


def configure_root_app(lines: list[str], app_id: str) -> None:
    bounds = root_apps_bounds(lines)
    if bounds is None:
        return

    start, end = bounds
    app_key = f'\t\t"{app_id}"\n'
    index = start + 1
    while index < end:
        if lines[index] != app_key:
            index += 1
            continue

        block_end = index + 1
        depth = 0
        while block_end < end:
            stripped = lines[block_end].strip()
            if stripped == "{":
                depth += 1
            elif stripped == "}":
                depth -= 1
                if depth == 0:
                    break
            block_end += 1

        for line_index in range(index, block_end + 1):
            if '"UseSteamControllerConfig"' in lines[line_index]:
                lines[line_index] = '\t\t\t"UseSteamControllerConfig"\t\t"0"\n'
                return

        lines.insert(block_end, '\t\t\t"UseSteamControllerConfig"\t\t"0"\n')
        return

    lines[end:end] = app_block(app_id)


def configure_root_apps(lines: list[str]) -> None:
    for app_id in APP_IDS:
        configure_root_app(lines, app_id)


def main() -> None:
    try:
        original_lines = LOCALCONFIG.read_text().splitlines(keepends=True)
    except OSError:
        return

    lines = original_lines[:]
    configure_root_apps(lines)

    if lines != original_lines:
        LOCALCONFIG.write_text("".join(lines))


if __name__ == "__main__":
    main()
