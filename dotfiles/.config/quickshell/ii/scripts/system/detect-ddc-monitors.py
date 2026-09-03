#!/usr/bin/env python3
"""Discover DDC displays once per stable monitor topology and emit JSON."""

from __future__ import annotations

from contextlib import contextmanager
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
from typing import Iterator
import uuid


OUTPUT_SCHEMA = "quickshell.ddc-monitors.v1"
CACHE_SCHEMA = 2
DEFAULT_CACHE_MAX_AGE_SECONDS = 3600.0
DEFAULT_LOCK_TIMEOUT_SECONDS = 2.0
DEFAULT_DDCUTIL_TIMEOUT_SECONDS = 20.0
DRM_CLASS_ROOT = Path("/sys/class/drm")
I2C_DEV_CLASS_ROOT = Path("/sys/class/i2c-dev")


class LockTimeoutError(TimeoutError):
    """Raised when another discovery process holds the cache lock too long."""


class DdcParseError(ValueError):
    """Raised when ddcutil reports a display block without required fields."""


def configured_seconds(
    name: str, default: float, minimum: float, maximum: float
) -> float:
    """Read a finite, bounded duration from the environment."""
    try:
        value = float(os.environ.get(name, default))
    except (TypeError, ValueError):
        return default
    if not math.isfinite(value) or not minimum <= value <= maximum:
        return default
    return value


def boot_id() -> str | None:
    """Return a canonical Linux boot ID, or disable caching if it is invalid."""
    try:
        raw = Path("/proc/sys/kernel/random/boot_id").read_text(
            encoding="ascii"
        ).strip()
        return str(uuid.UUID(raw))
    except (OSError, UnicodeError, ValueError, AttributeError):
        return None


def normalized_connector_name(sysfs_name: str) -> str:
    """Turn e.g. card1-DP-2 into the connector name exposed by Quickshell."""
    basename = sysfs_name.rsplit("/", 1)[-1]
    match = re.fullmatch(r"card\d+-(.+)", basename)
    return match.group(1) if match else basename


def read_text(path: Path, fallback: str = "unknown") -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace").strip() or fallback
    except OSError:
        return fallback


def topology_snapshot(root: Path = DRM_CLASS_ROOT) -> list[dict[str, object]]:
    """Capture connector state and EDID identity for cache invalidation."""
    records: list[dict[str, object]] = []
    try:
        entries = sorted(root.iterdir(), key=lambda path: path.name)
    except OSError:
        return records

    for entry in entries:
        status_path = entry / "status"
        if not status_path.exists():
            continue

        try:
            edid = (entry / "edid").read_bytes()
        except OSError:
            edid = b""

        records.append(
            {
                "connector": normalized_connector_name(entry.name),
                "drmConnector": entry.name,
                "status": read_text(status_path),
                "enabled": read_text(entry / "enabled"),
                "edidSha256": hashlib.sha256(edid).hexdigest() if edid else None,
            }
        )

    return records


def i2c_adapter_inventory(
    root: Path = I2C_DEV_CLASS_ROOT,
) -> list[dict[str, object]]:
    """Capture bus numbering and adapter identity across driver rebinds."""
    records: list[dict[str, object]] = []
    try:
        entries = list(root.iterdir())
    except OSError:
        return records

    for entry in entries:
        match = re.fullmatch(r"i2c-(\d+)", entry.name)
        if not match:
            continue
        try:
            device_path = str((entry / "device").resolve(strict=True))
        except (OSError, RuntimeError):
            device_path = "unknown"
        records.append(
            {
                "bus": int(match.group(1)),
                "adapterName": read_text(entry / "name"),
                "devicePath": device_path,
            }
        )

    return sorted(
        records,
        key=lambda record: (
            int(record["bus"]),
            str(record["adapterName"]),
            str(record["devicePath"]),
        ),
    )


def topology_fingerprint(
    connector_records: list[dict[str, object]],
    i2c_records: list[dict[str, object]] | None = None,
) -> str:
    if i2c_records is None:
        i2c_records = i2c_adapter_inventory()
    encoded = json.dumps(
        {"connectors": connector_records, "i2cAdapters": i2c_records},
        ensure_ascii=True,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def requested_connectors(
    arguments: list[str], topology: list[dict[str, object]]
) -> list[str]:
    requested = {
        normalized_connector_name(value.strip())
        for value in arguments
        if value.strip()
    }
    if not requested:
        requested = {
            str(record["connector"])
            for record in topology
            if record.get("status") == "connected"
        }
    return sorted(requested)


def discovery_identity(
    arguments: list[str], current_boot_id: str | None
) -> tuple[str, list[str], dict[str, object] | None]:
    """Snapshot all state that makes a cached bus mapping safe to reuse."""
    topology = topology_snapshot()
    topology_hash = topology_fingerprint(topology)
    connectors = requested_connectors(arguments, topology)
    key: dict[str, object] | None = None
    if current_boot_id is not None:
        key = {
            "bootId": current_boot_id,
            "connectors": connectors,
            "topologyFingerprint": topology_hash,
        }
    return topology_hash, connectors, key


def valid_monitors(value: object) -> list[dict[str, object]] | None:
    """Validate cached monitor records before exposing them to QML."""
    if not isinstance(value, list):
        return None

    monitors: list[dict[str, object]] = []
    for item in value:
        if not isinstance(item, dict):
            return None
        connector = item.get("connector")
        drm_connector = item.get("drmConnector")
        bus = item.get("bus")
        display = item.get("display")
        if (
            not isinstance(connector, str)
            or not connector
            or not isinstance(drm_connector, str)
            or not drm_connector
            or not isinstance(bus, str)
            or not bus.isdecimal()
            or (
                display is not None
                and (not isinstance(display, int) or isinstance(display, bool))
            )
        ):
            return None
        monitors.append(
            {
                "connector": connector,
                "drmConnector": drm_connector,
                "bus": bus,
                "display": display,
            }
        )
    return monitors


def load_cache(
    path: Path, key: dict[str, object], max_age: float, now: float
) -> list[dict[str, object]] | None:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, ValueError):
        return None

    if not isinstance(payload, dict):
        return None
    if payload.get("cacheSchema") != CACHE_SCHEMA or payload.get("key") != key:
        return None

    created_at = payload.get("createdAt")
    if (
        not isinstance(created_at, (int, float))
        or isinstance(created_at, bool)
        or not math.isfinite(created_at)
    ):
        return None
    age = now - float(created_at)
    if age < 0 or age > max_age:
        return None

    return valid_monitors(payload.get("monitors"))


def write_cache(
    path: Path,
    key: dict[str, object],
    monitors: list[dict[str, object]],
    created_at: float,
) -> None:
    fd, temporary_name = tempfile.mkstemp(prefix=".ddc-detect-", dir=path.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as temporary:
            json.dump(
                {
                    "cacheSchema": CACHE_SCHEMA,
                    "createdAt": created_at,
                    "key": key,
                    "monitors": monitors,
                },
                temporary,
                ensure_ascii=True,
                separators=(",", ":"),
                sort_keys=True,
            )
            temporary.flush()
            os.fsync(temporary.fileno())
        os.replace(temporary_name, path)
    finally:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass


@contextmanager
def exclusive_lock(path: Path, timeout: float) -> Iterator[None]:
    flags = os.O_RDWR | os.O_CREAT | getattr(os, "O_CLOEXEC", 0)
    descriptor = os.open(path, flags, 0o600)
    try:
        os.fchmod(descriptor, 0o600)
        deadline = time.monotonic() + timeout
        while True:
            try:
                fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise LockTimeoutError from None
                time.sleep(min(0.05, remaining))
            except InterruptedError:
                continue

        try:
            yield
        finally:
            fcntl.flock(descriptor, fcntl.LOCK_UN)
    finally:
        os.close(descriptor)


def parse_ddcutil_output(output: str) -> list[dict[str, object]]:
    """Normalize ddcutil's human-readable blocks into stable JSON records."""
    monitors: list[dict[str, object]] = []
    current: dict[str, object] | None = None
    incomplete_block = False

    def finish() -> None:
        nonlocal current, incomplete_block
        if current is None:
            return
        if isinstance(current.get("drmConnector"), str) and isinstance(
            current.get("bus"), str
        ):
            current["connector"] = normalized_connector_name(
                str(current["drmConnector"])
            )
            monitors.append(current)
        elif current.get("display") is not None:
            # An invalid display may legitimately lack a usable connector or
            # bus. A numbered Display block may not: accepting it would cache
            # a silently partial discovery result.
            incomplete_block = True
        current = None

    for raw_line in output.splitlines():
        line = raw_line.strip()
        display_match = re.fullmatch(r"Display\s+(\d+)", line)
        if display_match:
            finish()
            current = {"display": int(display_match.group(1))}
            continue
        if line.startswith("Invalid display"):
            finish()
            current = {"display": None}
            continue
        if current is None:
            continue

        bus_match = re.fullmatch(r"I2C bus:\s*/dev/i2c-(\d+)", line)
        if bus_match:
            current["bus"] = bus_match.group(1)
            continue
        connector_match = re.fullmatch(r"DRM connector:\s*(\S+)", line)
        if connector_match:
            current["drmConnector"] = connector_match.group(1)

    finish()

    if incomplete_block:
        raise DdcParseError("ddcutil returned an incomplete display record")

    unique: dict[tuple[str, str], dict[str, object]] = {}
    for monitor in monitors:
        unique[(str(monitor["connector"]), str(monitor["bus"]))] = monitor
    return sorted(
        unique.values(),
        key=lambda monitor: (
            str(monitor["connector"]),
            int(str(monitor["bus"])),
        ),
    )


def concise_detail(value: str, limit: int = 240) -> str:
    detail = " ".join(value.split())
    return detail if len(detail) <= limit else f"{detail[:limit]}..."


def probe_ddcutil(
    executable: str, timeout: float
) -> tuple[list[dict[str, object]] | None, dict[str, str] | None, int]:
    try:
        result = subprocess.run(
            [executable, "detect", "--brief"],
            check=False,
            capture_output=True,
            env={**os.environ, "LC_ALL": "C"},
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
        )
    except FileNotFoundError:
        return None, {
            "code": "ddcutil_not_found",
            "message": f"DDC discovery executable not found: {executable}",
        }, 127
    except subprocess.TimeoutExpired:
        return None, {
            "code": "ddcutil_timeout",
            "message": f"DDC discovery exceeded {timeout:g} seconds",
        }, 124
    except OSError as error:
        return None, {
            "code": "ddcutil_exec_error",
            "message": concise_detail(str(error)) or "Unable to execute DDC discovery",
        }, 126

    if result.returncode != 0:
        detail = concise_detail(result.stderr)
        message = f"ddcutil exited with status {result.returncode}"
        if detail:
            message = f"{message}: {detail}"
        exit_code = result.returncode if 1 <= result.returncode <= 125 else 1
        return None, {"code": "ddcutil_failed", "message": message}, exit_code

    try:
        monitors = parse_ddcutil_output(result.stdout)
    except DdcParseError as error:
        return None, {
            "code": "ddcutil_parse_error",
            "message": str(error),
        }, 65
    return monitors, None, 0


def response(
    *,
    ok: bool,
    cached: bool,
    cacheable: bool,
    topology_hash: str,
    monitors: list[dict[str, object]] | None = None,
    error: dict[str, str] | None = None,
) -> dict[str, object]:
    payload: dict[str, object] = {
        "schema": OUTPUT_SCHEMA,
        "ok": ok,
        "cached": cached,
        "cacheable": cacheable,
        "topologyFingerprint": topology_hash,
        "monitors": monitors or [],
    }
    if error is not None:
        payload["error"] = error
    return payload


def emit(payload: dict[str, object]) -> None:
    print(
        json.dumps(
            payload, ensure_ascii=True, separators=(",", ":"), sort_keys=True
        ),
        flush=True,
    )


def main() -> int:
    current_boot_id = boot_id()
    cacheable = current_boot_id is not None
    topology_hash, connectors, key = discovery_identity(
        sys.argv[1:], current_boot_id
    )

    cache_max_age = configured_seconds(
        "DDC_DETECT_CACHE_MAX_AGE",
        DEFAULT_CACHE_MAX_AGE_SECONDS,
        0.0,
        86400.0,
    )
    lock_timeout = configured_seconds(
        "DDC_DETECT_LOCK_TIMEOUT", DEFAULT_LOCK_TIMEOUT_SECONDS, 0.0, 30.0
    )
    probe_timeout = configured_seconds(
        "DDC_DETECT_TIMEOUT", DEFAULT_DDCUTIL_TIMEOUT_SECONDS, 1.0, 120.0
    )

    cache_base = os.environ.get("XDG_CACHE_HOME") or str(Path.home() / ".cache")
    cache_root = Path(cache_base) / "quickshell"
    try:
        cache_root.mkdir(mode=0o700, parents=True, exist_ok=True)
        cache_root.chmod(0o700)
    except OSError as error:
        emit(
            response(
                ok=False,
                cached=False,
                cacheable=False,
                topology_hash=topology_hash,
                error={
                    "code": "cache_unavailable",
                    "message": concise_detail(str(error))
                    or "DDC cache directory is unavailable",
                },
            )
        )
        return 73

    cache_path = cache_root / "ddc-detect-v2.json"
    lock_path = cache_root / "ddc-detect-v2.lock"

    try:
        with exclusive_lock(lock_path, lock_timeout):
            # The topology may have changed while this process waited for the
            # single-flight lock, so never reuse the pre-lock cache identity.
            topology_hash, connectors, key = discovery_identity(
                sys.argv[1:], current_boot_id
            )
            now = time.time()
            if key is not None:
                cached_monitors = load_cache(cache_path, key, cache_max_age, now)
                if cached_monitors is not None:
                    verified_hash, verified_connectors, verified_key = (
                        discovery_identity(sys.argv[1:], current_boot_id)
                    )
                    if (
                        verified_hash == topology_hash
                        and verified_connectors == connectors
                        and verified_key == key
                    ):
                        emit(
                            response(
                                ok=True,
                                cached=True,
                                cacheable=True,
                                topology_hash=topology_hash,
                                monitors=cached_monitors,
                            )
                        )
                        return 0
                    topology_hash = verified_hash
                    connectors = verified_connectors
                    key = verified_key

            monitors, error, exit_code = probe_ddcutil(
                os.environ.get("DDCUTIL_BIN") or "ddcutil", probe_timeout
            )
            if monitors is None:
                emit(
                    response(
                        ok=False,
                        cached=False,
                        cacheable=cacheable,
                        topology_hash=topology_hash,
                        error=error,
                    )
                )
                return exit_code

            verified_hash, verified_connectors, verified_key = discovery_identity(
                sys.argv[1:], current_boot_id
            )
            if (
                verified_hash != topology_hash
                or verified_connectors != connectors
                or verified_key != key
            ):
                emit(
                    response(
                        ok=False,
                        cached=False,
                        cacheable=cacheable,
                        topology_hash=verified_hash,
                        error={
                            "code": "topology_changed",
                            "message": "Monitor topology changed during DDC discovery",
                        },
                    )
                )
                return 75

            if key is not None:
                try:
                    write_cache(cache_path, key, monitors, time.time())
                except OSError:
                    # Discovery remains useful even when an atomic cache write fails.
                    cacheable = False

            emit(
                response(
                    ok=True,
                    cached=False,
                    cacheable=cacheable,
                    topology_hash=topology_hash,
                    monitors=monitors,
                )
            )
            return 0
    except LockTimeoutError:
        emit(
            response(
                ok=False,
                cached=False,
                cacheable=cacheable,
                topology_hash=topology_hash,
                error={
                    "code": "lock_timeout",
                    "message": (
                        "Another DDC discovery held the lock longer than "
                        f"{lock_timeout:g} seconds"
                    ),
                },
            )
        )
        return 75
    except OSError as error:
        emit(
            response(
                ok=False,
                cached=False,
                cacheable=cacheable,
                topology_hash=topology_hash,
                error={
                    "code": "lock_error",
                    "message": concise_detail(str(error))
                    or "Unable to lock DDC discovery",
                },
            )
        )
        return 73


if __name__ == "__main__":
    raise SystemExit(main())
