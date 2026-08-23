#!/usr/bin/env python3
"""Safe status/settings bridge for Logitech G502 X Plus and Solaar."""

from __future__ import annotations

import glob
import json
import os
import re
import subprocess
import sys
import time


DEVICE_NAME = "G502 X PLUS"
SOLAAR = "/usr/bin/solaar"
SOLAAR_ENV = dict(os.environ, LC_ALL="C")
SETTING_CANDIDATES = {
    "dpi": ("dpi",),
    "report_rate": ("report_rate", "report_rate_extended"),
    "high_res_scroll": ("hires-smooth-resolution", "hi-res-scroll"),
    "scroll_invert": ("hires-smooth-invert",),
    "onboard_profile": ("onboard_profiles",),
}


def read_text(path: str, fallback: str = "") -> str:
    try:
        with open(path, encoding="utf-8") as handle:
            return handle.read().strip()
    except OSError:
        return fallback


def find_battery() -> dict:
    for base in glob.glob("/sys/class/power_supply/*"):
        if read_text(os.path.join(base, "manufacturer")).lower() != "logitech":
            continue
        model = read_text(os.path.join(base, "model_name"))
        if DEVICE_NAME.lower() not in model.lower():
            continue
        capacity = read_text(os.path.join(base, "capacity"))
        return {
            "present": True,
            "capacity": int(capacity) if capacity.isdigit() else None,
            "status": read_text(os.path.join(base, "status")),
            "online": read_text(os.path.join(base, "online")) == "1",
            "model": model,
            "serial": read_text(os.path.join(base, "serial_number")),
        }
    return {"present": False, "capacity": None, "status": "", "online": False, "model": "", "serial": ""}


def hid_connected() -> bool:
    for path in glob.glob("/sys/bus/hid/devices/*/uevent"):
        if "HID_NAME=Logitech G502 X PLUS" in read_text(path):
            return True
    return False


def parse_solaar_settings(output: str) -> dict:
    settings = {}
    pending_options = []
    for line in output.splitlines():
        option_match = re.search(r"possible values: one of \[\s*(.*?)\s*\]", line)
        if option_match:
            pending_options = [value.strip() for value in option_match.group(1).split(",") if value.strip()]
            continue
        setting_match = re.match(r"^([a-z][a-z0-9_-]*)\s*=\s*(.*?)\s*$", line.strip())
        if setting_match:
            settings[setting_match.group(1)] = {
                "value": setting_match.group(2),
                "options": pending_options,
            }
            pending_options = []
    return settings


def cached_solaar_settings() -> dict:
    path = os.path.expanduser("~/.config/solaar/config.yaml")
    text = read_text(path)
    if "_NAME: G502 X PLUS" not in text:
        return {}
    result = {}
    known = {
        "dpi": [],
        "report_rate": ["1ms", "2ms", "4ms", "8ms"],
        "onboard_profiles": ["Disabled", "Profile 1", "Profile 2"],
        "hires-smooth-resolution": [],
        "hires-smooth-invert": [],
    }
    for name, options in known.items():
        match = re.search(rf"^\s*{re.escape(name)}:\s*(.*?)\s*$", text, re.MULTILINE)
        if not match:
            continue
        value = match.group(1)
        if name == "report_rate" and value.isdigit():
            value = f"{value}ms"
        elif name == "onboard_profiles" and value.isdigit():
            value = "Disabled" if value == "0" else f"Profile {value}"
        elif value.lower() in ("true", "false"):
            value = "True" if value.lower() == "true" else "False"
        result[name] = {"value": value, "options": options}
    return result


def solaar_status() -> dict:
    if not os.path.isfile(SOLAAR):
        return {"available": False, "supported": False, "settings": {}, "error": ""}
    result = None
    settings = {}
    try:
        for attempt in range(3):
            result = subprocess.run(
                [SOLAAR, "-ddd", "config", DEVICE_NAME],
                capture_output=True,
                text=True,
                timeout=7,
                check=False,
                env=SOLAAR_ENV,
            )
            settings = parse_solaar_settings(result.stdout)
            if result.returncode == 0 and settings:
                break
            if attempt < 2:
                time.sleep(2)
    except (OSError, subprocess.TimeoutExpired) as error:
        return {"available": True, "supported": False, "settings": {}, "error": str(error)}
    assert result is not None
    if not settings:
        cached = cached_solaar_settings()
        if cached:
            return {
                "available": True,
                "supported": True,
                "cached": True,
                "settings": cached,
                "error": "",
            }
    error_lines = [line.strip() for line in result.stderr.splitlines() if line.strip()]
    return {
        "available": True,
        "supported": result.returncode == 0 and bool(settings),
        "cached": False,
        "settings": settings,
        "error": "" if result.returncode == 0 else (error_lines[-1] if error_lines else "Solaar could not access this device"),
    }


def status() -> dict:
    solaar = solaar_status()
    available = {}
    for logical_name, candidates in SETTING_CANDIDATES.items():
        available[logical_name] = next((name for name in candidates if name in solaar["settings"]), "")
    solaar["controls"] = available
    return {
        "schema_version": 1,
        "connected": hid_connected(),
        "device": {"name": "Logitech G502 X Plus", "receiver_id": "046d:c547"},
        "battery": find_battery(),
        "solaar": solaar,
    }


def set_value(logical_name: str, value: str) -> dict:
    current = status()
    setting = current["solaar"]["controls"].get(logical_name, "")
    if not current["solaar"]["supported"] or not setting:
        return {"ok": False, "error": {"code": "unsupported", "message": "This setting is not exposed by Solaar for the connected mouse"}}
    if logical_name == "dpi" and (
        not value.isdigit() or not 100 <= int(value) <= 25600 or int(value) % 50 != 0
    ):
        return {"ok": False, "error": {"code": "invalid_value", "message": "DPI must be between 100 and 25600 in steps of 50"}}
    if logical_name == "report_rate" and value not in ("1ms", "2ms", "4ms", "8ms"):
        return {"ok": False, "error": {"code": "invalid_value", "message": "Report rate must be 1ms, 2ms, 4ms, or 8ms"}}
    if logical_name == "onboard_profile" and value not in ("Disabled", "Profile 1", "Profile 2"):
        return {"ok": False, "error": {"code": "invalid_value", "message": "Unknown onboard profile"}}
    if logical_name in ("high_res_scroll", "scroll_invert") and value.lower() not in ("on", "off", "true", "false", "1", "0"):
        return {"ok": False, "error": {"code": "invalid_value", "message": "Toggle value must be on or off"}}
    try:
        result = subprocess.run(
            [SOLAAR, "-ddd", "config", DEVICE_NAME, setting, value],
            capture_output=True,
            text=True,
            timeout=7,
            check=False,
            env=SOLAAR_ENV,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        return {"ok": False, "error": {"code": "execution_failed", "message": str(error)}}
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines() if line.strip()]
        return {"ok": False, "error": {"code": "solaar_failed", "message": lines[-1] if lines else "Solaar rejected the setting"}}
    return {"ok": True, "setting": logical_name, "value": value}


def main() -> int:
    if len(sys.argv) == 1 or sys.argv[1] == "status":
        print(json.dumps(status(), separators=(",", ":")))
        return 0
    if sys.argv[1] == "set" and len(sys.argv) == 4 and sys.argv[2] in SETTING_CANDIDATES:
        result = set_value(sys.argv[2], sys.argv[3])
        print(json.dumps(result, separators=(",", ":")))
        return 0 if result.get("ok") else 2
    print(json.dumps({"ok": False, "error": {"code": "usage", "message": "usage: logitech_g502.py [status|set SETTING VALUE]"}}, separators=(",", ":")))
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
