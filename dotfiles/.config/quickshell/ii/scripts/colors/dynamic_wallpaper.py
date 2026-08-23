#!/usr/bin/env python3
"""Sunrise/sunset-aware dynamic wallpaper rotation for Max's Quickshell background.

Directory layout:
    dynamic-system/
        morning/
        day/
        evening/
        night/

Each rotation chooses a random image from the period folder selected from the
local sunrise/sunset times, then calls switchwall.sh so the visible wallpaper and
Material/GTK/Qt/Hyprland colours stay synced.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import random
import shutil
import signal
import subprocess
import sys
import time
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

HOME = Path.home()
CONFIG = HOME / ".config" / "illogical-impulse" / "config.json"
SCRIPT = HOME / ".config" / "quickshell" / "ii" / "scripts" / "colors" / "switchwall.sh"
QS = shutil.which("qs") or str(HOME / ".local/bin" / "qs")
STATE = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local/state")) / "quickshell" / "dynamic-wallpaper"
DEFAULT_DIR = HOME / "Pictures" / "Wallpapers" / "dynamic-system"
PID_FILE = STATE / "dynamic-wallpaper.pid"
LOG_FILE = STATE / "dynamic-wallpaper.log"
ROTATION_STATE_FILE = STATE / "last-rotation.json"
EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".avif", ".bmp"}
PERIODS = ("morning", "day", "evening", "night")
DEFAULT_LATITUDE = 51.6714842
DEFAULT_LONGITUDE = -1.2779715
DEFAULT_SCHEDULE_MODE = "sun"  # "sun" or "manual"
DEFAULT_MANUAL_TIMES = {
    "morning": "06:00",
    "day": "10:30",
    "evening": "17:30",
    "night": "21:30",
}


def log(message: str) -> None:
    STATE.mkdir(parents=True, exist_ok=True)
    line = f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {message}\n"
    LOG_FILE.open("a", encoding="utf-8").write(line)
    print(line, end="")


def read_config() -> dict:
    try:
        return json.loads(CONFIG.read_text(encoding="utf-8"))
    except Exception:
        return {}


def dynamic_config() -> dict:
    return read_config().get("background", {}).get("dynamic", {}) or {}


def configured_mode() -> str:
    try:
        out = subprocess.check_output(
            ["gsettings", "get", "org.gnome.desktop.interface", "color-scheme"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip("'\n ")
        return "dark" if out == "prefer-dark" else "light"
    except Exception:
        hour = time.localtime().tm_hour
        return "light" if 7 <= hour < 18 else "dark"


def current_wallpaper() -> str:
    return str(read_config().get("background", {}).get("wallpaperPath", ""))


def canonical_path(value: str | Path) -> str:
    try:
        return str(Path(value).expanduser().resolve())
    except Exception:
        return str(Path(value).expanduser())


def read_rotation_state() -> dict | None:
    try:
        state = json.loads(ROTATION_STATE_FILE.read_text(encoding="utf-8"))
        if (
            not isinstance(state, dict)
            or not isinstance(state.get("path"), str)
            or state.get("period") not in PERIODS
            or not isinstance(state.get("applied_at"), (int, float))
        ):
            return None
        return state
    except Exception:
        return None


def write_rotation_state(path: str | Path, period: str, applied_at: float | None = None) -> dict:
    STATE.mkdir(parents=True, exist_ok=True)
    state = {
        "path": canonical_path(path),
        "period": period,
        "applied_at": float(time.time() if applied_at is None else applied_at),
    }
    temporary = ROTATION_STATE_FILE.with_suffix(".tmp")
    temporary.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")
    temporary.replace(ROTATION_STATE_FILE)
    return state


def same_wallpaper(first: str | Path, second: str | Path) -> bool:
    return bool(first) and bool(second) and canonical_path(first) == canonical_path(second)


def normalize_base_directory(directory: Path) -> Path:
    """Accept either dynamic-system/ or an old dynamic-system/current path."""
    directory = directory.expanduser()
    if directory.name == "current" and directory.parent.exists():
        parent = directory.parent
        if any((parent / period).is_dir() for period in PERIODS):
            return parent
    return directory


def period_directory(base: Path, period: str) -> Path:
    candidate = base / period
    return candidate if candidate.is_dir() else base


def wallpaper_is_usable(path: str) -> bool:
    if not path:
        return False
    candidate = Path(path).expanduser()
    return candidate.is_file() and candidate.suffix.lower() in EXTENSIONS


def wallpaper_matches_period(path: str, base: Path, period: str, prefer_time: bool) -> bool:
    if not wallpaper_is_usable(path):
        return False
    candidate = Path(path).expanduser()
    expected_directory = period_directory(base, period) if prefer_time else base
    try:
        candidate.resolve().relative_to(expected_directory.resolve())
        return True
    except (OSError, ValueError):
        return False


def wallpapers(directory: Path, recursive: bool = False) -> list[Path]:
    if not directory.exists():
        raise SystemExit(f"Wallpaper directory does not exist: {directory}")
    iterator = directory.rglob("*") if recursive else directory.iterdir()
    return sorted(
        p for p in iterator
        if p.is_file() and p.suffix.lower() in EXTENSIONS and not p.name.startswith(".")
    )


def sunrise_sunset(day: date, latitude: float, longitude: float) -> tuple[datetime, datetime]:
    """Return local sunrise/sunset using the NOAA approximation.

    Good enough for wallpaper scheduling and has no network/dependency failure
    mode. Falls back to 07:00/19:00 if polar/math edge cases occur.
    """
    zenith = 90.833
    n = day.timetuple().tm_yday
    lng_hour = longitude / 15.0

    def calc(is_sunrise: bool) -> datetime:
        t = n + (((6 if is_sunrise else 18) - lng_hour) / 24.0)
        mean_anomaly = (0.9856 * t) - 3.289
        true_long = mean_anomaly + (1.916 * math.sin(math.radians(mean_anomaly))) + (0.020 * math.sin(math.radians(2 * mean_anomaly))) + 282.634
        true_long %= 360
        right_asc = math.degrees(math.atan(0.91764 * math.tan(math.radians(true_long)))) % 360
        l_quadrant = math.floor(true_long / 90) * 90
        ra_quadrant = math.floor(right_asc / 90) * 90
        right_asc = (right_asc + (l_quadrant - ra_quadrant)) / 15.0
        sin_dec = 0.39782 * math.sin(math.radians(true_long))
        cos_dec = math.cos(math.asin(sin_dec))
        cos_h = (math.cos(math.radians(zenith)) - (sin_dec * math.sin(math.radians(latitude)))) / (cos_dec * math.cos(math.radians(latitude)))
        if cos_h < -1 or cos_h > 1:
            raise ValueError("sun never rises/sets on this date at this latitude")
        hour_angle = 360 - math.degrees(math.acos(cos_h)) if is_sunrise else math.degrees(math.acos(cos_h))
        hour_angle /= 15.0
        local_mean_time = hour_angle + right_asc - (0.06571 * t) - 6.622
        utc_hour = (local_mean_time - lng_hour) % 24
        utc_dt = datetime(day.year, day.month, day.day, tzinfo=timezone.utc) + timedelta(hours=utc_hour)
        # Convert through system local timezone, preserving DST.
        return utc_dt.astimezone().replace(tzinfo=None)

    try:
        sunrise = calc(True)
        sunset = calc(False)
    except Exception:
        sunrise = datetime(day.year, day.month, day.day, 7, 0)
        sunset = datetime(day.year, day.month, day.day, 19, 0)
    return sunrise, sunset


def schedule_for(now: datetime, latitude: float, longitude: float) -> dict[str, datetime]:
    sunrise, sunset = sunrise_sunset(now.date(), latitude, longitude)
    daylight = max(timedelta(hours=2), sunset - sunrise)
    morning_end = sunrise + min(timedelta(hours=4), daylight * 0.35)
    evening_start = sunset - min(timedelta(hours=2), daylight * 0.22)
    return {
        "sunrise": sunrise,
        "sunset": sunset,
        "morning_start": sunrise - timedelta(minutes=30),
        "morning_end": morning_end,
        "evening_start": evening_start,
        "evening_end": sunset + timedelta(minutes=90),
    }


def parse_hhmm(value: str, fallback: str) -> tuple[int, int]:
    raw = str(value or fallback).strip()
    try:
        hour_s, minute_s = raw.split(":", 1)
        hour = int(hour_s)
        minute = int(minute_s)
        if 0 <= hour <= 23 and 0 <= minute <= 59:
            return hour, minute
    except Exception:
        pass
    hour_s, minute_s = fallback.split(":", 1)
    return int(hour_s), int(minute_s)


def manual_times_from_args(args: argparse.Namespace) -> dict[str, str]:
    return {
        "morning": args.morning_time,
        "day": args.day_time,
        "evening": args.evening_time,
        "night": args.night_time,
    }


def manual_schedule_points(anchor: date, times: dict[str, str]) -> list[tuple[str, datetime]]:
    points: list[tuple[str, datetime]] = []
    for period in PERIODS:
        hour, minute = parse_hhmm(times.get(period, ""), DEFAULT_MANUAL_TIMES[period])
        points.append((period, datetime(anchor.year, anchor.month, anchor.day, hour, minute)))
    return sorted(points, key=lambda item: item[1])


def manual_period_for(now: datetime, times: dict[str, str]) -> str:
    points = manual_schedule_points(now.date(), times)
    current = points[-1][0]
    for period, starts_at in points:
        if now >= starts_at:
            current = period
        else:
            break
    return current


def manual_next_transition_after(now: datetime, times: dict[str, str]) -> datetime:
    points: list[datetime] = []
    for delta_days in (0, 1):
        points.extend(starts_at for _, starts_at in manual_schedule_points((now + timedelta(days=delta_days)).date(), times))
    future = [p for p in points if p > now + timedelta(seconds=1)]
    return min(future) if future else now + timedelta(hours=1)


def schedule_mode_value(value: str) -> str:
    return "manual" if str(value).lower() == "manual" else "sun"


def period_for_args(now: datetime, args: argparse.Namespace) -> str:
    if schedule_mode_value(args.schedule_mode) == "manual":
        return manual_period_for(now, manual_times_from_args(args))
    return period_for(now, args.latitude, args.longitude)


def next_transition_after_args(now: datetime, args: argparse.Namespace) -> datetime:
    if schedule_mode_value(args.schedule_mode) == "manual":
        return manual_next_transition_after(now, manual_times_from_args(args))
    return next_transition_after(now, args.latitude, args.longitude)


def schedule_status_lines(now: datetime, args: argparse.Namespace) -> list[str]:
    if schedule_mode_value(args.schedule_mode) == "manual":
        times = manual_times_from_args(args)
        return [
            "schedule=manual",
            f"morning={parse_hhmm(times['morning'], DEFAULT_MANUAL_TIMES['morning'])[0]:02d}:{parse_hhmm(times['morning'], DEFAULT_MANUAL_TIMES['morning'])[1]:02d}",
            f"day={parse_hhmm(times['day'], DEFAULT_MANUAL_TIMES['day'])[0]:02d}:{parse_hhmm(times['day'], DEFAULT_MANUAL_TIMES['day'])[1]:02d}",
            f"evening={parse_hhmm(times['evening'], DEFAULT_MANUAL_TIMES['evening'])[0]:02d}:{parse_hhmm(times['evening'], DEFAULT_MANUAL_TIMES['evening'])[1]:02d}",
            f"night={parse_hhmm(times['night'], DEFAULT_MANUAL_TIMES['night'])[0]:02d}:{parse_hhmm(times['night'], DEFAULT_MANUAL_TIMES['night'])[1]:02d}",
        ]
    s = schedule_for(now, args.latitude, args.longitude)
    return [
        "schedule=sunrise-sunset",
        f"sunrise={s['sunrise'].strftime('%H:%M')}",
        f"sunset={s['sunset'].strftime('%H:%M')}",
        f"morning={s['morning_start'].strftime('%H:%M')}",
        f"day={s['morning_end'].strftime('%H:%M')}",
        f"evening={s['evening_start'].strftime('%H:%M')}",
        f"night={s['evening_end'].strftime('%H:%M')}",
    ]


def period_for(now: datetime, latitude: float, longitude: float) -> str:
    s = schedule_for(now, latitude, longitude)
    if s["morning_start"] <= now < s["morning_end"]:
        return "morning"
    if s["morning_end"] <= now < s["evening_start"]:
        return "day"
    if s["evening_start"] <= now < s["evening_end"]:
        return "evening"
    return "night"


def next_transition_after(now: datetime, latitude: float, longitude: float) -> datetime:
    points: list[datetime] = []
    for delta_days in (0, 1):
        s = schedule_for(now + timedelta(days=delta_days), latitude, longitude)
        points.extend([s["morning_start"], s["morning_end"], s["evening_start"], s["evening_end"]])
    future = [p for p in points if p > now + timedelta(seconds=1)]
    return min(future) if future else now + timedelta(hours=1)


def desired_mode(period: str, auto_mode: bool) -> str:
    if not auto_mode:
        return configured_mode()
    return "light" if period in {"morning", "day"} else "dark"


def choose_wallpaper(base: Path, previous: str, period: str, prefer_time: bool = True) -> Path:
    search_dir = period_directory(base, period) if prefer_time else base
    pool = wallpapers(search_dir, recursive=not prefer_time)
    if not pool and prefer_time:
        pool = wallpapers(base, recursive=True)
    if not pool:
        raise SystemExit(f"No wallpapers found in {search_dir}")
    if len(pool) > 1:
        pool = [p for p in pool if str(p) != previous] or pool
    return random.choice(pool)


def apply(path: Path, mode: str, period: str) -> int:
    log(f"apply period={period} {path.name} mode={mode}")
    try:
        result = subprocess.run(
            [QS, "-c", "ii", "ipc", "call", "wallpapers", "applyDynamic", str(path), "true" if mode == "dark" else "false"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=2,
            check=False,
        )
        if result.returncode == 0:
            return 0
    except Exception:
        pass

    cmd = [str(SCRIPT), "--image", str(path), "--mode", mode]
    return subprocess.call(cmd)


def apply_and_record(path: Path, mode: str, period: str) -> int:
    result = apply(path, mode, period)
    if result == 0:
        write_rotation_state(path, period)
    return result


def rotation_threshold_reached(
    rotation_state: dict | None,
    period: str,
    interval: int,
    now_timestamp: float | None = None,
) -> bool:
    """Only schedule boundaries and elapsed intervals may advance wallpaper."""
    if rotation_state is None:
        return True
    current_timestamp = time.time() if now_timestamp is None else now_timestamp
    return (
        rotation_state["period"] != period
        or current_timestamp >= float(rotation_state["applied_at"]) + max(1, interval)
    )


def read_pid() -> int | None:
    try:
        return int(PID_FILE.read_text().strip())
    except Exception:
        return None


def is_running(pid: int | None) -> bool:
    if not pid:
        return False
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def stop_existing() -> None:
    pids: set[int] = set()
    pid = read_pid()
    if pid is not None:
        pids.add(pid)
    try:
        out = subprocess.check_output(
            ["pgrep", "-f", f"{Path(__file__).resolve()} run"],
            text=True,
            stderr=subprocess.DEVNULL,
        )
        pids.update(int(line.strip()) for line in out.splitlines() if line.strip().isdigit())
    except Exception:
        pass
    for old_pid in sorted(pids):
        if old_pid != os.getpid() and is_running(old_pid):
            os.kill(old_pid, signal.SIGTERM)
            log(f"stopped pid {old_pid}")
    for _ in range(20):
        live_pids = [old_pid for old_pid in pids if old_pid != os.getpid() and is_running(old_pid)]
        if not live_pids:
            break
        time.sleep(0.1)
    PID_FILE.unlink(missing_ok=True)


def daemon(args: argparse.Namespace) -> None:
    if is_running(read_pid()):
        raise SystemExit(f"Already running with pid {read_pid()} — use stop/status/next")
    STATE.mkdir(parents=True, exist_ok=True)
    PID_FILE.write_text(str(os.getpid()), encoding="utf-8")
    running = True
    def handle_stop(signum, frame):  # noqa: ANN001
        nonlocal running
        running = False

    signal.signal(signal.SIGTERM, handle_stop)
    signal.signal(signal.SIGINT, handle_stop)

    base = normalize_base_directory(args.directory)
    log(f"started base={base} interval={args.interval}s schedule={schedule_mode_value(args.schedule_mode)} lat={args.latitude} lon={args.longitude}")
    first_iteration = True
    try:
        while running:
            now = datetime.now()
            period = period_for_args(now, args)
            configured_wallpaper = current_wallpaper()
            configured_is_usable = wallpaper_is_usable(configured_wallpaper)
            configured_is_valid = wallpaper_matches_period(
                configured_wallpaper, base, period, args.prefer_time
            )
            rotation_state = read_rotation_state()

            # Starting the daemon is recovery, not a rotation event. If the
            # configured image still belongs to the current time period, keep
            # it and begin a fresh interval from recovery time. A period change
            # is still handled below so morning/day/evening/night stay correct.
            if first_iteration and configured_is_valid:
                rotation_state = write_rotation_state(configured_wallpaper, period)
                log(f"restore period={period} {Path(configured_wallpaper).name} (restarted rotation timer)")
            # Migrate an already-valid dynamic wallpaper into persistent state
            # if the state file is removed while the daemon is running.
            elif rotation_state is None and configured_is_valid:
                rotation_state = write_rotation_state(configured_wallpaper, period)
                log(f"preserve period={period} {Path(configured_wallpaper).name} (initialized rotation timer)")
            elif (
                rotation_state is not None
                and not same_wallpaper(rotation_state["path"], configured_wallpaper)
                and configured_is_valid
            ):
                # A wallpaper selected outside this daemon becomes the new timer
                # baseline instead of being overwritten on daemon recovery.
                rotation_state = write_rotation_state(configured_wallpaper, period)
                log(f"preserve period={period} {Path(configured_wallpaper).name} (adopted current wallpaper)")

            interval_due_at = (
                float(rotation_state["applied_at"]) + max(1, args.interval)
                if rotation_state is not None else 0.0
            )
            rotation_due = rotation_threshold_reached(rotation_state, period, args.interval)

            if rotation_state is None and not configured_is_usable:
                # Config hydration can briefly expose an empty path during a
                # Quickshell restart. Wait for the saved wallpaper instead of
                # treating that transient state as a request to pick a new one.
                if first_iteration:
                    log("preserve: waiting for configured wallpaper before initializing rotation timer")
            elif rotation_due:
                previous_wallpaper = configured_wallpaper if configured_is_usable else rotation_state["path"]
                selected = choose_wallpaper(base, previous_wallpaper, period, args.prefer_time)
                result = apply_and_record(selected, desired_mode(period, args.auto_mode), period)
                rotation_state = read_rotation_state()
                if result != 0:
                    log(f"apply failed status={result}; retrying shortly")
            elif first_iteration:
                remaining = max(0, math.ceil(interval_due_at - time.time()))
                log(f"resume period={period} {Path(configured_wallpaper).name} next rotation in {remaining}s")

            first_iteration = False
            transition = next_transition_after_args(datetime.now(), args)
            seconds_to_transition = math.ceil((transition - datetime.now()).total_seconds())
            if rotation_state is not None:
                seconds_to_interval = math.ceil(
                    float(rotation_state["applied_at"]) + max(1, args.interval) - time.time()
                )
            else:
                seconds_to_interval = 30
            sleep_seconds = max(1, min(max(1, seconds_to_interval), seconds_to_transition))
            for _ in range(sleep_seconds):
                if not running:
                    break
                time.sleep(1)
    finally:
        if read_pid() == os.getpid():
            PID_FILE.unlink(missing_ok=True)
        log("stopped")


def add_config_defaults(parser: argparse.ArgumentParser) -> argparse.ArgumentParser:
    cfg = dynamic_config()
    parser.set_defaults(
        directory=Path(cfg.get("directory") or DEFAULT_DIR),
        interval=int(cfg.get("intervalSeconds") or 20 * 60),
        auto_mode=bool(cfg.get("autoMode", True)),
        prefer_time=bool(cfg.get("preferTime", True)),
        latitude=float(cfg.get("latitude", DEFAULT_LATITUDE)),
        longitude=float(cfg.get("longitude", DEFAULT_LONGITUDE)),
        schedule_mode=schedule_mode_value(cfg.get("scheduleMode", DEFAULT_SCHEDULE_MODE)),
        morning_time=str(cfg.get("morningTime", DEFAULT_MANUAL_TIMES["morning"])),
        day_time=str(cfg.get("dayTime", DEFAULT_MANUAL_TIMES["day"])),
        evening_time=str(cfg.get("eveningTime", DEFAULT_MANUAL_TIMES["evening"])),
        night_time=str(cfg.get("nightTime", DEFAULT_MANUAL_TIMES["night"])),
    )
    return parser


def main() -> int:
    parser = argparse.ArgumentParser(description="Sunrise/sunset-aware dynamic wallpaper rotator")
    parser.add_argument("command", choices=["start", "stop", "status", "next", "run", "period"], nargs="?", default="next")
    parser.add_argument("--directory", "-d", type=Path, help="dynamic-system base dir containing morning/day/evening/night")
    parser.add_argument("--interval", "-i", type=int, help="max seconds between rotations")
    parser.add_argument("--latitude", type=float, help="latitude for sunrise/sunset schedule")
    parser.add_argument("--longitude", type=float, help="longitude for sunrise/sunset schedule")
    parser.add_argument("--schedule-mode", choices=["sun", "manual"], help="use sunrise/sunset or manually configured start times")
    parser.add_argument("--morning-time", help="manual morning start, HH:MM")
    parser.add_argument("--day-time", help="manual day start, HH:MM")
    parser.add_argument("--evening-time", help="manual evening start, HH:MM")
    parser.add_argument("--night-time", help="manual night start, HH:MM")
    parser.add_argument("--auto-mode", action="store_true", dest="auto_mode", help="light in morning/day, dark in evening/night")
    parser.add_argument("--no-auto-mode", dest="auto_mode", action="store_false", help="keep current light/dark preference")
    parser.add_argument("--prefer-time", action="store_true", dest="prefer_time", help="choose from morning/day/evening/night folders")
    parser.add_argument("--no-prefer-time", dest="prefer_time", action="store_false")
    add_config_defaults(parser)
    args = parser.parse_args()
    args.directory = normalize_base_directory(args.directory)

    if args.command == "stop":
        stop_existing(); return 0
    if args.command == "status":
        pid = read_pid()
        now = datetime.now()
        period = period_for_args(now, args)
        print("running" if is_running(pid) else "stopped", pid or "")
        print(f"directory={args.directory}")
        print(f"period={period}")
        for line in schedule_status_lines(now, args):
            print(line)
        print(f"next_transition={next_transition_after_args(now, args).strftime('%H:%M')}")
        rotation_state = read_rotation_state()
        if rotation_state is not None:
            applied_at = datetime.fromtimestamp(float(rotation_state["applied_at"]))
            interval_due = applied_at + timedelta(seconds=max(1, args.interval))
            print(f"last_rotation={applied_at.strftime('%Y-%m-%d %H:%M:%S')}")
            print(f"last_wallpaper={rotation_state['path']}")
            print(f"next_rotation={min(interval_due, next_transition_after_args(now, args)).strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"log={LOG_FILE}")
        return 0
    if args.command == "period":
        now = datetime.now()
        print(period_for_args(now, args))
        for line in schedule_status_lines(now, args):
            print(line)
        print(f"next={next_transition_after_args(now, args).strftime('%H:%M')}")
        return 0
    if args.command == "next":
        now = datetime.now()
        period = period_for_args(now, args)
        selected = choose_wallpaper(args.directory, current_wallpaper(), period, args.prefer_time)
        return apply_and_record(selected, desired_mode(period, args.auto_mode), period)
    if args.command == "run":
        return daemon(args) or 0
    if args.command == "start":
        stop_existing()
        STATE.mkdir(parents=True, exist_ok=True)
        cmd = [
            sys.executable, __file__, "run",
            "--directory", str(args.directory),
            "--interval", str(args.interval),
            "--latitude", str(args.latitude),
            "--longitude", str(args.longitude),
            "--schedule-mode", schedule_mode_value(args.schedule_mode),
            "--morning-time", f"{parse_hhmm(args.morning_time, DEFAULT_MANUAL_TIMES['morning'])[0]:02d}:{parse_hhmm(args.morning_time, DEFAULT_MANUAL_TIMES['morning'])[1]:02d}",
            "--day-time", f"{parse_hhmm(args.day_time, DEFAULT_MANUAL_TIMES['day'])[0]:02d}:{parse_hhmm(args.day_time, DEFAULT_MANUAL_TIMES['day'])[1]:02d}",
            "--evening-time", f"{parse_hhmm(args.evening_time, DEFAULT_MANUAL_TIMES['evening'])[0]:02d}:{parse_hhmm(args.evening_time, DEFAULT_MANUAL_TIMES['evening'])[1]:02d}",
            "--night-time", f"{parse_hhmm(args.night_time, DEFAULT_MANUAL_TIMES['night'])[0]:02d}:{parse_hhmm(args.night_time, DEFAULT_MANUAL_TIMES['night'])[1]:02d}",
            "--auto-mode" if args.auto_mode else "--no-auto-mode",
            "--prefer-time" if args.prefer_time else "--no-prefer-time",
        ]
        subprocess.Popen(
            cmd,
            stdout=(STATE / "launcher.out").open("a"),
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        time.sleep(0.3)
        pid = read_pid()
        print(f"started pid={pid}" if pid else "starting; pid not written yet")
        return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
