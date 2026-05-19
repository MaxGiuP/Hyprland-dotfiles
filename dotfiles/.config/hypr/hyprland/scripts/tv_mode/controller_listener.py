#!/usr/bin/env python3
"""Listen for Xbox-pattern gamepad chords used by TV mode."""

from __future__ import annotations

import asyncio
import json
import re
import subprocess
import sys
import time
from pathlib import Path

import evdev
from evdev import ecodes

DIGITAL_CHORD = frozenset({ecodes.BTN_SELECT, ecodes.BTN_START})
CLOSE_APP_CHORD = frozenset({ecodes.BTN_SELECT, ecodes.BTN_THUMBL, ecodes.BTN_THUMBR})  # Back + L3 + R3
BUMPER_CHORD = frozenset({ecodes.BTN_TL, ecodes.BTN_TR})
TRIGGER_AXES = (ecodes.ABS_Z, ecodes.ABS_RZ)
TRIGGER_THRESHOLD = 100  # out of 255; ~40% pull
FOCUS_STICK_AXES = (ecodes.ABS_X, ecodes.ABS_Y)
SCROLL_STICK_AXES = (ecodes.ABS_RX, ecodes.ABS_RY)
STICK_DEADZONE = 0.35
STICK_REPEAT_SECONDS = 0.12
NAME_RE = re.compile(r"x-?box", re.IGNORECASE)
FOCUS_TV_TARGET = Path(__file__).resolve().parent / "focus_tv_target.sh"
CLEAN_STALE_STEAM = Path(__file__).resolve().parent / "clean_stale_steam.sh"
CLOSE_TV_APP = Path(__file__).resolve().parent / "close_tv_app.sh"
RESCAN_DELAY = 2.0
APP_WORKSPACE = "special:tv-app"
TV_MONITOR_CANDIDATES = ("HDMI-A-2", "HDMI-2", "HDMI2")
COMMAND_COOLDOWN_SECONDS = 1.75
DIRECT_CONTROLLER_CLASSES = {"gamescope", "rpcs3"}
STEAM_GAME_CMDLINE_MARKERS = (
    "SteamLaunch AppId=",
    "/steamapps/common/",
    "/steamapps/compatdata/",
    "lanoire-stable-launch",
)
last_command_fired_at: dict[str, float] = {}

KEY_ESC = 1
KEY_TAB = 15
KEY_ENTER = 28
KEY_LEFTCTRL = 29
KEY_LEFTSHIFT = 42
KEY_SPACE = 57
KEY_LEFTALT = 56
KEY_PAGEUP = 104
KEY_LEFT = 105
KEY_RIGHT = 106
KEY_END = 107
KEY_DOWN = 108
KEY_PAGEDOWN = 109
KEY_HOME = 102
KEY_UP = 103

BUTTON_KEYS = {
    ecodes.BTN_SOUTH: KEY_ENTER,  # A
    ecodes.BTN_EAST: KEY_ESC,     # B
    ecodes.BTN_NORTH: KEY_SPACE,  # Y
    ecodes.BTN_WEST: KEY_TAB,     # X
}

DPAD_KEYS = {
    ecodes.BTN_DPAD_UP: KEY_UP,
    ecodes.BTN_DPAD_DOWN: KEY_DOWN,
    ecodes.BTN_DPAD_LEFT: KEY_LEFT,
    ecodes.BTN_DPAD_RIGHT: KEY_RIGHT,
}

HAT_TO_KEY = {
    ecodes.ABS_HAT0X: {-1: KEY_LEFT, 1: KEY_RIGHT},
    ecodes.ABS_HAT0Y: {-1: KEY_UP, 1: KEY_DOWN},
}


def find_devices() -> list[evdev.InputDevice]:
    devices: list[evdev.InputDevice] = []
    for path in evdev.list_devices():
        try:
            dev = evdev.InputDevice(path)
        except OSError:
            continue
        if not NAME_RE.search(dev.name):
            dev.close()
            continue
        caps = dev.capabilities()
        keys = set(caps.get(ecodes.EV_KEY, []))
        axes = {code for code, _ in caps.get(ecodes.EV_ABS, [])}
        if DIGITAL_CHORD <= keys and all(a in axes for a in TRIGGER_AXES):
            devices.append(dev)
        else:
            dev.close()
    return devices


def tv_app_client() -> dict | None:
    try:
        proc = subprocess.run(
            ["hyprctl", "-j", "clients"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=1.0,
            check=False,
        )
        clients = json.loads(proc.stdout)
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError):
        return None

    candidates = [
        client
        for client in clients
        if client.get("mapped", True)
        and not client.get("hidden", False)
        and isinstance(client.get("workspace"), dict)
        and client["workspace"].get("name") == APP_WORKSPACE
    ]
    if not candidates:
        return None

    candidates.sort(key=lambda client: client.get("focusHistoryID", 999999))
    return candidates[0]


def tv_app_address() -> str | None:
    client = tv_app_client()
    if not client:
        return None
    return client.get("address")


def proc_cmdline(pid: int) -> str:
    try:
        raw = Path(f"/proc/{pid}/cmdline").read_bytes()
    except OSError:
        return ""
    return raw.replace(b"\0", b" ").decode("utf-8", errors="replace").strip()


def proc_parent_pid(pid: int) -> int:
    try:
        status = Path(f"/proc/{pid}/status").read_text(errors="replace")
    except OSError:
        return 0

    match = re.search(r"^PPid:\s+([0-9]+)", status, re.MULTILINE)
    return int(match.group(1)) if match else 0


def process_tree_has_steam_game(pid: int) -> bool:
    seen: set[int] = set()
    current = pid

    for _ in range(32):
        if current <= 1 or current in seen:
            return False
        seen.add(current)

        cmdline = proc_cmdline(current)
        if any(marker in cmdline for marker in STEAM_GAME_CMDLINE_MARKERS):
            return True

        current = proc_parent_pid(current)

    return False


def tv_app_wants_direct_controller() -> bool:
    client = tv_app_client()
    if not client:
        return False

    window_class = str(client.get("class") or client.get("initialClass") or "")
    if window_class.lower() in DIRECT_CONTROLLER_CLASSES:
        return True

    try:
        pid = int(client.get("pid") or 0)
    except (TypeError, ValueError):
        return False

    return process_tree_has_steam_game(pid)


def should_inject_controller_key() -> bool:
    return bool(tv_app_address()) and not tv_app_wants_direct_controller()


def ydotool_key(*keycodes: int) -> None:
    if not keycodes or not should_inject_controller_key():
        return

    args = ["ydotool", "key"]
    for keycode in keycodes:
        args.extend([f"{keycode}:1", f"{keycode}:0"])

    subprocess.Popen(
        args,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def ydotool_combo(*keycodes: int) -> None:
    if not keycodes or not should_inject_controller_key():
        return

    args = ["ydotool", "key"]
    args.extend(f"{keycode}:1" for keycode in keycodes)
    args.extend(f"{keycode}:0" for keycode in reversed(keycodes))
    subprocess.Popen(
        args,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def normalise_axis(dev: evdev.InputDevice, code: int, value: int) -> float:
    try:
        info = dev.absinfo(code)
    except OSError:
        return 0.0

    minimum = info.min
    maximum = info.max
    centre = (minimum + maximum) / 2
    span = max(1, (maximum - minimum) / 2)
    normalised = (value - centre) / span
    return max(-1.0, min(1.0, normalised))


def key_for_axis(axis: int, value: float) -> int | None:
    if abs(value) < STICK_DEADZONE:
        return None

    vertical = axis in (ecodes.ABS_Y, ecodes.ABS_RY)
    positive = value > 0
    if vertical:
        return KEY_DOWN if positive else KEY_UP
    return KEY_RIGHT if positive else KEY_LEFT


def dominant_axis_key(axes: dict[int, float]) -> int | None:
    axis, value = max(axes.items(), key=lambda item: abs(item[1]))
    return key_for_axis(axis, value)


def scroll_key_for_axis(axis: int, value: float, held_for: float) -> int | None:
    if abs(value) < STICK_DEADZONE:
        return None

    vertical = axis == ecodes.ABS_RY
    positive = value > 0
    if vertical and held_for > 1.2:
        return KEY_PAGEDOWN if positive else KEY_PAGEUP
    if vertical:
        return KEY_DOWN if positive else KEY_UP
    return KEY_RIGHT if positive else KEY_LEFT


def notify_command(summary: str, body: str) -> None:
    subprocess.Popen(
        ["notify-send", summary, body],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def log(message: str) -> None:
    print(f"[tv-controller] {message}", file=sys.stderr, flush=True)


def command_on_cooldown(command_name: str) -> bool:
    now = time.monotonic()
    last = last_command_fired_at.get(command_name, 0.0)
    if now - last < COMMAND_COOLDOWN_SECONDS:
        return True

    last_command_fired_at[command_name] = now
    return False


def resolve_tv_monitor() -> dict | None:
    try:
        proc = subprocess.run(
            ["hyprctl", "-j", "monitors", "all"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=1.0,
            check=False,
        )
        monitors = json.loads(proc.stdout)
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError):
        return None

    by_name = {str(monitor.get("name") or ""): monitor for monitor in monitors}
    for candidate in TV_MONITOR_CANDIDATES:
        monitor = by_name.get(candidate)
        if monitor:
            return monitor
    return None


def move_cursor_to_tv() -> None:
    monitor = resolve_tv_monitor()
    if not monitor:
        log("could not move cursor to TV: no configured TV monitor is connected")
        return

    x = int(monitor.get("x", 0)) + int(monitor.get("width", 0)) // 2
    y = int(monitor.get("y", 0)) + int(monitor.get("height", 0)) // 2
    try:
        subprocess.run(
            ["hyprctl", "dispatch", "movecursor", str(x), str(y)],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=1.0,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        pass


def fire_focus_tv_target() -> None:
    if command_on_cooldown("focus-tv-target"):
        return

    log("registered Back + Start + LB + RB -> focus current TV target")
    move_cursor_to_tv()
    notify_command(
        "TV mode command registered",
        "Back + Start + LB + RB: focusing the TV app if one is open, otherwise Steam Big Picture.",
    )
    fire_script("tv-focus-target", FOCUS_TV_TARGET)


def fire_clean_stale_steam() -> None:
    if command_on_cooldown("clean-stale-steam"):
        return

    log("registered Back + Start + LT + RT -> clean stale Steam")
    move_cursor_to_tv()
    notify_command(
        "TV mode command registered",
        "Back + Start + LT + RT: cleaning stale Steam TV state and stale Steam processes.",
    )
    fire_script("tv-steam-clean-stale", CLEAN_STALE_STEAM)


def fire_close_tv_app() -> None:
    if command_on_cooldown("close-tv-app"):
        return

    log("registered Back + L3 + R3 -> close TV app")
    fire_script("tv-close-app", CLOSE_TV_APP)


def fire_script(unit_prefix: str, script_path: Path) -> None:
    unit_name = unit_prefix
    command = [
        "systemd-run",
        "--user",
        "--collect",
        "--quiet",
        "--property=StandardOutput=journal",
        "--property=StandardError=journal",
        f"--unit={unit_name}",
        str(script_path),
    ]

    try:
        proc = subprocess.run(
            command,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
            timeout=1.5,
            check=False,
        )
        if proc.returncode == 0:
            log(f"started {script_path.name} as transient unit {unit_name}")
            return
        stderr = proc.stderr.strip()
        if "already exists" in stderr or "Unit " in stderr and "already" in stderr:
            log(f"{script_path.name} is already running as {unit_name}")
            return
        log(f"systemd-run failed for {script_path.name}: {stderr}")
    except (OSError, subprocess.SubprocessError):
        log(f"systemd-run raised while starting {script_path.name}")

    if unit_prefix.startswith("tv-steam"):
        notify_command(
            "TV mode command failed",
            f"Could not start {script_path.name} from the controller listener. Check tv-controller-toggle.service logs.",
        )
        return

    subprocess.Popen(
        [str(script_path)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    log(f"started {script_path.name} directly")


async def watch(dev: evdev.InputDevice) -> None:
    pressed: set[int] = set()
    triggers = {axis: False for axis in TRIGGER_AXES}
    focus_axes = {axis: 0.0 for axis in FOCUS_STICK_AXES}
    scroll_axes = {axis: 0.0 for axis in SCROLL_STICK_AXES}
    scroll_axis_started_at = {axis: 0.0 for axis in SCROLL_STICK_AXES}
    active_back_start_command: str | None = None
    close_chord_was_active = False

    async def stick_loop() -> None:
        while True:
            now = time.monotonic()
            focus_key = dominant_axis_key(focus_axes)
            if focus_key is not None:
                ydotool_combo(KEY_LEFTCTRL, KEY_LEFTALT, focus_key)

            for axis, value in scroll_axes.items():
                if abs(value) < STICK_DEADZONE:
                    scroll_axis_started_at[axis] = 0.0
                    continue

                if scroll_axis_started_at[axis] == 0.0:
                    scroll_axis_started_at[axis] = now

                keycode = scroll_key_for_axis(axis, value, now - scroll_axis_started_at[axis])
                if keycode is not None:
                    ydotool_combo(KEY_LEFTCTRL, KEY_LEFTALT, KEY_LEFTSHIFT, keycode)

            await asyncio.sleep(STICK_REPEAT_SECONDS)

    stick_task = asyncio.create_task(stick_loop())
    try:
        async for event in dev.async_read_loop():
            if event.type == ecodes.EV_KEY:
                if event.value == 1:
                    pressed.add(event.code)
                elif event.value == 0:
                    pressed.discard(event.code)

                close_chord_active_now = CLOSE_APP_CHORD <= pressed
                suppress_button_key = event.code == ecodes.BTN_EAST and close_chord_active_now
                if event.code in BUTTON_KEYS and event.value in (1, 2) and not suppress_button_key:
                    ydotool_key(BUTTON_KEYS[event.code])
                elif event.code in DPAD_KEYS and event.value in (1, 2):
                    ydotool_combo(KEY_LEFTCTRL, KEY_LEFTALT, DPAD_KEYS[event.code])
            elif event.type == ecodes.EV_ABS and event.code in TRIGGER_AXES:
                triggers[event.code] = event.value >= TRIGGER_THRESHOLD
            elif event.type == ecodes.EV_ABS and event.code in FOCUS_STICK_AXES:
                focus_axes[event.code] = normalise_axis(dev, event.code, event.value)
            elif event.type == ecodes.EV_ABS and event.code in SCROLL_STICK_AXES:
                scroll_axes[event.code] = normalise_axis(dev, event.code, event.value)
            elif event.type == ecodes.EV_ABS and event.code in HAT_TO_KEY:
                keycode = HAT_TO_KEY[event.code].get(event.value)
                if keycode is not None:
                    ydotool_combo(KEY_LEFTCTRL, KEY_LEFTALT, keycode)
            else:
                continue

            if DIGITAL_CHORD <= pressed:
                if active_back_start_command is None:
                    if BUMPER_CHORD <= pressed:
                        fire_focus_tv_target()
                        active_back_start_command = "focus-tv-target"
                    elif all(triggers.values()):
                        fire_clean_stale_steam()
                        active_back_start_command = "clean-stale-steam"
            else:
                active_back_start_command = None

            close_chord_active = CLOSE_APP_CHORD <= pressed
            if close_chord_active and not close_chord_was_active:
                fire_close_tv_app()
            close_chord_was_active = close_chord_active
    except OSError:
        return
    finally:
        stick_task.cancel()
        try:
            dev.close()
        except Exception:
            pass


async def main() -> None:
    last_device_paths: tuple[str, ...] | None = None
    while True:
        devices = find_devices()
        device_paths = tuple(dev.path for dev in devices)
        if device_paths != last_device_paths:
            if device_paths:
                names = ", ".join(f"{dev.path} ({dev.name})" for dev in devices)
                log(f"watching controller devices: {names}")
            else:
                log("no matching Xbox-style controller devices found")
            last_device_paths = device_paths

        if not devices:
            await asyncio.sleep(RESCAN_DELAY)
            continue
        await asyncio.gather(*(watch(dev) for dev in devices))
        await asyncio.sleep(RESCAN_DELAY)


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
