#!/usr/bin/env python3
"""Route Steam Big Picture and TV apps onto separate special workspaces."""

from __future__ import annotations

import os
import json
import errno
import re
import select
import socket
import subprocess
import sys
import time
from pathlib import Path
import pty
from typing import Any

TV_MONITOR = "HDMI-A-2"
TV_MONITOR_CANDIDATES = ("HDMI-A-2", "HDMI-2", "HDMI2")
FALLBACK_WORKSPACE = os.environ.get("TV_MODE_FALLBACK_WORKSPACE", "1")
TV_WORKSPACE = "special:tv"
APP_WORKSPACE = "special:tv-app"
STATE_PATH = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local" / "state")) / "tv-mode" / "state.json"
ACTIVE_STATUSES = {"starting", "active", "loading"}

STEAM_CLASSES = {"steam", "Steam", "steamwebhelper"}
BIG_PICTURE_TITLES = {"Steam Big Picture Mode", "Modalità Big Picture di Steam"}
TV_APP_CLASS_RE = re.compile(r"^(steam_app_.*|chrome-.*-TV)$", re.IGNORECASE)
STEAM_GAME_CMDLINE_MARKERS = (
    "SteamLaunch AppId=",
    "/steamapps/common/",
    "/steamapps/compatdata/",
)

app_windows: set[str] = set()
big_picture_windows: set[str] = set()


def tv_mode_enabled() -> bool:
    try:
        state = json.loads(STATE_PATH.read_text())
    except (OSError, json.JSONDecodeError):
        return False

    if str(state.get("status") or "") not in ACTIVE_STATUSES:
        return False

    # If the configured TV output is gone, do not let stale TV mode keep
    # routing ordinary windows onto a special workspace on the desktop monitor.
    if not resolve_tv_monitor():
        stop_tv_workspaces_without_monitor()
        return False

    return True


def clear_tv_mode_state() -> None:
    try:
        STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
        STATE_PATH.write_text(
            json.dumps(
                {
                    "status": "stopped",
                    "message": "",
                    "mode": "",
                    "app": "",
                    "monitor": "",
                    "updated_at": int(time.time()),
                },
                separators=(",", ":"),
            )
            + "\n"
        )
    except OSError:
        pass


def instance_socket_path(socket_name: str) -> Path | None:
    signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    hypr_dir = Path(runtime_dir) / "hypr"

    if signature:
        path = hypr_dir / signature / socket_name
        if path.exists():
            return path

    sockets = sorted(hypr_dir.glob(f"*/{socket_name}"), key=lambda p: p.stat().st_mtime, reverse=True)
    return sockets[0] if sockets else None


def event_socket_path() -> Path | None:
    return instance_socket_path(".socket2.sock")


def control_socket_path() -> Path | None:
    return instance_socket_path(".socket.sock")


def ipc_command(command: str, *, timeout: float = 1.5) -> str:
    path = control_socket_path()
    if path is None:
        raise OSError("Hyprland control socket not found")

    chunks: list[bytes] = []
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.settimeout(timeout)
        sock.connect(str(path))
        sock.sendall(command.encode("utf-8"))
        try:
            sock.shutdown(socket.SHUT_WR)
        except OSError:
            pass

        while True:
            chunk = sock.recv(65536)
            if not chunk:
                break
            chunks.append(chunk)

    return b"".join(chunks).decode("utf-8", errors="replace")


def hyprctl_command(*args: str, timeout: float = 1.5) -> str:
    if args and args[0] == "-j":
        return ipc_command(f"j/{' '.join(args[1:])}", timeout=timeout)
    return ipc_command(" ".join(args), timeout=timeout)


def dispatch(*args: str) -> None:
    try:
        hyprctl_command("dispatch", *args)
    except OSError:
        pass


def keyword(name: str, value: str) -> None:
    try:
        hyprctl_command("keyword", name, value)
    except OSError:
        pass


def clients() -> list[dict[str, Any]]:
    last_error = ""
    last_output = ""

    for _attempt in range(3):
        for runner in (hyprctl_command, hyprctl_pty, hyprctl_pipe):
            try:
                last_output = runner("-j", "clients")
                data = json.loads(last_output)
                return data if isinstance(data, list) else []
            except (json.JSONDecodeError, OSError, subprocess.SubprocessError) as exc:
                last_error = f"{type(exc).__name__}: {str(exc)[:120]}"

        time.sleep(0.05)

    print(
        f"tv-stack-listener: client scan failed: {last_error} output={last_output[:120]!r}",
        file=sys.stderr,
        flush=True,
    )
    return []


def monitors() -> list[dict[str, Any]]:
    try:
        data = json.loads(hyprctl_command("-j", "monitors"))
        return data if isinstance(data, list) else []
    except (json.JSONDecodeError, OSError, subprocess.SubprocessError):
        return []


def resolve_tv_monitor() -> str:
    available = {str(monitor.get("name") or "") for monitor in monitors()}
    for candidate in TV_MONITOR_CANDIDATES:
        if candidate in available:
            return candidate
    return ""


def hyprctl_pipe(*args: str, timeout: float = 1.5) -> str:
    proc = subprocess.run(
        ["hyprctl", *args],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
        check=False,
    )
    if proc.returncode != 0:
        raise subprocess.SubprocessError((proc.stderr or proc.stdout).strip())
    return proc.stdout


def hyprctl_pty(*args: str, timeout: float = 1.5) -> str:
    # hyprctl JSON can fail when stdout is a pipe on this setup. A PTY matches
    # the known-good terminal path while still letting us parse its output.
    master_fd, slave_fd = pty.openpty()
    chunks: list[bytes] = []

    try:
        proc = subprocess.Popen(
            ["hyprctl", *args],
            stdin=subprocess.DEVNULL,
            stdout=slave_fd,
            stderr=subprocess.DEVNULL,
            close_fds=True,
        )
        os.close(slave_fd)
        slave_fd = -1

        deadline = time.monotonic() + timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                proc.kill()
                break

            readable, _, _ = select.select([master_fd], [], [], remaining)
            if not readable:
                continue

            try:
                chunk = os.read(master_fd, 65536)
            except OSError as exc:
                if exc.errno == errno.EIO:
                    break
                raise

            if not chunk:
                break
            chunks.append(chunk)

        try:
            proc.wait(timeout=0.2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=0.2)
    finally:
        if slave_fd != -1:
            os.close(slave_fd)
        os.close(master_fd)

    return b"".join(chunks).decode("utf-8", errors="replace")


def find_client(address: str) -> dict[str, Any] | None:
    selector_address = normalize_address(address)
    for client in clients():
        if normalize_address(str(client.get("address", ""))) == selector_address:
            return client
    return None


def normalize_address(address: str) -> str:
    cleaned = address.strip()
    return cleaned if cleaned.startswith("0x") else f"0x{cleaned}"


def address_selector(address: str) -> str:
    return f"address:{normalize_address(address)}"


def is_big_picture(window_class: str, title: str) -> bool:
    return window_class in STEAM_CLASSES and title in BIG_PICTURE_TITLES


def is_steam_ui(window_class: str, title: str) -> bool:
    if window_class not in STEAM_CLASSES:
        return False

    return title == "Steam" or title in BIG_PICTURE_TITLES or "Big Picture" in title or "Modalità Big Picture" in title


def is_tv_app(window_class: str) -> bool:
    return TV_APP_CLASS_RE.match(window_class) is not None


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


def process_tree_has_steam_launch(pid: int) -> bool:
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


def is_tv_app_client(client: dict[str, Any]) -> bool:
    window_class = str(client.get("class") or client.get("initialClass") or "")
    title = str(client.get("title") or client.get("initialTitle") or "")

    if is_steam_ui(window_class, title):
        return False

    if is_tv_app(window_class):
        return True

    try:
        pid = int(client.get("pid") or 0)
    except (TypeError, ValueError):
        return False

    return process_tree_has_steam_launch(pid)


def client_workspace_name(client: dict[str, Any]) -> str:
    workspace = client.get("workspace")
    if isinstance(workspace, dict):
        return str(workspace.get("name") or "")
    return ""


def fallback_workspace() -> str:
    for monitor in monitors():
        if str(monitor.get("name") or "") in TV_MONITOR_CANDIDATES:
            continue

        active = monitor.get("activeWorkspace")
        if isinstance(active, dict):
            name = str(active.get("name") or "")
            if name and not name.startswith("special:"):
                return name

    return FALLBACK_WORKSPACE


def is_live_client(client: dict[str, Any]) -> bool:
    return bool(client.get("mapped", True)) and not bool(client.get("hidden", False))


def refresh_tracked_windows(scanned_clients: list[dict[str, Any]]) -> None:
    app_windows.clear()
    big_picture_windows.clear()

    for client in scanned_clients:
        if not is_live_client(client):
            continue

        window_class = str(client.get("class") or client.get("initialClass") or "")
        title = str(client.get("title") or client.get("initialTitle") or "")
        address = normalize_address(str(client.get("address", "")))

        if is_tv_app_client(client):
            app_windows.add(address)
        elif is_steam_ui(window_class, title):
            big_picture_windows.add(address)


def app_workspace_is_empty(scanned_clients: list[dict[str, Any]]) -> bool:
    return not any(
        is_live_client(client) and client_workspace_name(client) == APP_WORKSPACE
        for client in scanned_clients
    )


def live_tv_app_addresses(scanned_clients: list[dict[str, Any]]) -> list[str]:
    addresses: list[str] = []
    for client in scanned_clients:
        if not is_live_client(client):
            continue

        if is_tv_app_client(client):
            addresses.append(normalize_address(str(client.get("address", ""))))

    return [address for address in addresses if address != "0x"]


def live_steam_ui_addresses(scanned_clients: list[dict[str, Any]]) -> list[str]:
    addresses: list[str] = []
    for client in scanned_clients:
        if not is_live_client(client):
            continue

        window_class = str(client.get("class") or client.get("initialClass") or "")
        title = str(client.get("title") or client.get("initialTitle") or "")
        if is_steam_ui(window_class, title):
            addresses.append(normalize_address(str(client.get("address", ""))))

    return [address for address in addresses if address != "0x"]


def any_live_tv_app(scanned_clients: list[dict[str, Any]]) -> bool:
    return bool(live_tv_app_addresses(scanned_clients))


def special_short_name(workspace: str) -> str:
    return workspace.removeprefix("special:")


def special_visible_on_monitor(monitor_name: str) -> str:
    for monitor in monitors():
        if str(monitor.get("name") or "") != monitor_name:
            continue

        special = monitor.get("specialWorkspace")
        if isinstance(special, dict):
            return str(special.get("name") or "")
    return ""


def option_int(name: str, default: int) -> int:
    try:
        output = hyprctl_command("getoption", name)
    except OSError:
        return default

    match = re.search(r"^int:\s*([0-9]+)", output, re.MULTILINE)
    return int(match.group(1)) if match else default


def visible_monitor_for_special(workspace: str) -> str:
    for monitor in monitors():
        special = monitor.get("specialWorkspace")
        if isinstance(special, dict) and str(special.get("name") or "") == workspace:
            return str(monitor.get("name") or "")
    return ""


def hide_workspace_everywhere(workspace: str) -> None:
    for _ in range(6):
        visible = visible_monitor_for_special(workspace)
        if not visible:
            return

        dispatch("focusmonitor", visible)
        dispatch("togglespecialworkspace", special_short_name(workspace))
        time.sleep(0.05)


def close_windows_on_workspace(workspace: str) -> None:
    for client in clients():
        if not is_live_client(client) or client_workspace_name(client) != workspace:
            continue

        address = normalize_address(str(client.get("address", "")))
        if address != "0x":
            dispatch("closewindow", address_selector(address))


def workspace_has_live_windows(workspace: str) -> bool:
    return any(
        is_live_client(client) and client_workspace_name(client) == workspace
        for client in clients()
    )


def stop_tv_workspaces_without_monitor() -> None:
    close_windows_on_workspace(TV_WORKSPACE)
    close_windows_on_workspace(APP_WORKSPACE)

    for _ in range(20):
        if not workspace_has_live_windows(TV_WORKSPACE) and not workspace_has_live_windows(APP_WORKSPACE):
            break
        time.sleep(0.10)

    clear_tv_mode_state()
    hide_workspace_everywhere(TV_WORKSPACE)
    hide_workspace_everywhere(APP_WORKSPACE)


def toggle_workspace_on_monitor(workspace: str, monitor: str) -> None:
    follow_mouse = option_int("input:follow_mouse", 1)
    keyword("input:follow_mouse", "0")
    try:
        dispatch("moveworkspacetomonitor", workspace, monitor)
        dispatch("focusmonitor", monitor)
        dispatch("togglespecialworkspace", special_short_name(workspace))
        dispatch("moveworkspacetomonitor", workspace, monitor)
    finally:
        keyword("input:follow_mouse", str(follow_mouse))


def show_workspace(workspace: str) -> None:
    monitor = resolve_tv_monitor()
    if not monitor:
        stop_tv_workspaces_without_monitor()
        return

    workspace_opts = "persistent:true, monitor:HDMI-A-2, gapsin:0, gapsout:0, border:false, rounding:false, decorate:false"
    workspace_opts = workspace_opts.replace("monitor:HDMI-A-2", f"monitor:{monitor}")
    keyword("workspace", f"{TV_WORKSPACE}, {workspace_opts}")
    keyword("workspace", f"{APP_WORKSPACE}, {workspace_opts}")
    dispatch("moveworkspacetomonitor", TV_WORKSPACE, monitor)
    dispatch("moveworkspacetomonitor", APP_WORKSPACE, monitor)
    dispatch("moveworkspacetomonitor", workspace, monitor)

    if visible_monitor_for_special(workspace) == monitor:
        return

    visible_on_tv = special_visible_on_monitor(monitor)
    if visible_on_tv and visible_on_tv != workspace:
        toggle_workspace_on_monitor(visible_on_tv, monitor)
        time.sleep(0.05)

    wrong_monitor = visible_monitor_for_special(workspace)
    if wrong_monitor and wrong_monitor != monitor:
        hide_workspace_everywhere(workspace)

    if visible_monitor_for_special(workspace) != monitor:
        toggle_workspace_on_monitor(workspace, monitor)


def fullscreen_window(address: str) -> None:
    return


def place_big_picture(address: str, *, show: bool = True) -> None:
    monitor = resolve_tv_monitor()
    if not monitor:
        stop_tv_workspaces_without_monitor()
        return

    address = normalize_address(address)
    selector = address_selector(address)
    big_picture_windows.add(address)
    dispatch("movetoworkspacesilent", f"{TV_WORKSPACE},{selector}")
    dispatch("moveworkspacetomonitor", TV_WORKSPACE, monitor)
    if show:
        show_workspace(TV_WORKSPACE)
        fullscreen_window(address)


def place_tv_app(address: str, *, show: bool = True) -> None:
    monitor = resolve_tv_monitor()
    if not monitor:
        stop_tv_workspaces_without_monitor()
        return

    address = normalize_address(address)
    selector = address_selector(address)
    app_windows.add(address)
    dispatch("movetoworkspacesilent", f"{APP_WORKSPACE},{selector}")
    dispatch("moveworkspacetomonitor", APP_WORKSPACE, monitor)
    if show:
        show_workspace(APP_WORKSPACE)
        fullscreen_window(address)


def return_to_big_picture_if_empty() -> None:
    if not tv_mode_enabled():
        return

    # Query Hyprland after the close event instead of trusting our cached set.
    # Chrome and some Steam shortcuts can produce windows we did not classify
    # when they opened, but an empty special:tv-app workspace is definitive.
    time.sleep(0.05)
    scanned_clients = clients()
    refresh_tracked_windows(scanned_clients)

    if any_live_tv_app(scanned_clients):
        return

    if not big_picture_windows:
        refresh_tracked_windows(clients())

    show_workspace(TV_WORKSPACE)
    if big_picture_windows:
        fullscreen_window(next(iter(big_picture_windows)))


def route_client(client: dict[str, Any], *, show: bool = True) -> None:
    address = normalize_address(str(client.get("address", "")))
    if address == "0x":
        return

    window_class = str(client.get("class") or client.get("initialClass") or "")
    title = str(client.get("title") or client.get("initialTitle") or "")

    if is_tv_app_client(client):
        if show:
            place_tv_app(address)
        else:
            place_tv_app(address, show=False)
    elif is_steam_ui(window_class, title):
        if show:
            scanned_clients = clients()
            refresh_tracked_windows(scanned_clients)
            place_big_picture(address, show=not any_live_tv_app(scanned_clients))
        else:
            place_big_picture(address, show=False)
    elif client_workspace_name(client) in {TV_WORKSPACE, APP_WORKSPACE}:
        dispatch("movetoworkspacesilent", f"{fallback_workspace()},{address_selector(address)}")


def route_address(address: str, *, show: bool = True) -> None:
    # Steam frequently opens as a generic window and changes title shortly after.
    # Query the exact address instead of trusting the first event payload.
    time.sleep(0.10)
    client = find_client(address)
    if client is not None:
        route_client(client, show=show)


def route_event_window(address: str, window_class: str, title: str) -> None:
    time.sleep(0.12)
    if is_tv_app(window_class):
        place_tv_app(address)
    elif is_steam_ui(window_class, title):
        scanned_clients = clients()
        refresh_tracked_windows(scanned_clients)
        place_big_picture(address, show=not any_live_tv_app(scanned_clients))
    else:
        route_address(address, show=True)


def handle_active_window(address: str) -> None:
    # Active-window events are emitted for normal focus changes, including
    # focus-following-mouse. Never reveal TV special workspaces from here.
    time.sleep(0.05)
    client = find_client(address)
    if client is None:
        return

    window_class = str(client.get("class") or client.get("initialClass") or "")
    title = str(client.get("title") or client.get("initialTitle") or "")

    if is_tv_app_client(client):
        place_tv_app(address, show=False)
    elif is_steam_ui(window_class, title):
        scanned_clients = clients()
        refresh_tracked_windows(scanned_clients)
        place_big_picture(address, show=False)
    else:
        route_client(client, show=False)


def rescan_existing_windows(*, show: bool = True) -> None:
    if show and not tv_mode_enabled():
        return

    scanned_clients = clients()
    if not scanned_clients:
        print("tv-stack-listener: client scan returned no windows", file=sys.stderr, flush=True)

    refresh_tracked_windows(scanned_clients)
    app_addresses = live_tv_app_addresses(scanned_clients)
    big_picture_addresses = live_steam_ui_addresses(scanned_clients)

    if show:
        for address in big_picture_addresses:
            place_big_picture(address, show=False)

        if app_addresses:
            for address in app_addresses:
                place_tv_app(address, show=False)
            show_workspace(APP_WORKSPACE)
            fullscreen_window(app_addresses[-1])
        elif big_picture_addresses:
            place_big_picture(big_picture_addresses[-1])


def handle_openwindow(payload: str) -> None:
    parts = payload.split(",", 3)
    if len(parts) != 4:
        return
    address, _workspace, window_class, title = parts
    route_event_window(address, window_class, title)


def handle_closewindow(payload: str) -> None:
    address = normalize_address(payload)
    was_big_picture = address in big_picture_windows

    if address in app_windows:
        app_windows.discard(address)
    elif address in big_picture_windows:
        big_picture_windows.discard(address)
    else:
        rescan_existing_windows(show=False)

    refresh_tracked_windows(clients())
    if was_big_picture and not big_picture_windows:
        clear_tv_mode_state()
        return

    return_to_big_picture_if_empty()


def handle_event(line: str) -> None:
    if not tv_mode_enabled():
        return

    if line.startswith("openwindow>>"):
        handle_openwindow(line.removeprefix("openwindow>>"))
    elif line.startswith("closewindow>>"):
        handle_closewindow(line.removeprefix("closewindow>>"))
    elif line.startswith("windowtitle>>"):
        route_address(line.removeprefix("windowtitle>>"), show=False)
    elif line.startswith("movewindow>>"):
        address = line.removeprefix("movewindow>>").split(",", 1)[0]
        route_address(address, show=False)
    elif line.startswith("activewindowv2>>"):
        handle_active_window(line.removeprefix("activewindowv2>>"))


def ensure_workspace_rules() -> None:
    monitor = resolve_tv_monitor()
    if not monitor:
        stop_tv_workspaces_without_monitor()
        return

    workspace_opts = "persistent:true, monitor:HDMI-A-2, gapsin:0, gapsout:0, border:false, rounding:false, decorate:false"
    workspace_opts = workspace_opts.replace("monitor:HDMI-A-2", f"monitor:{monitor}")
    keyword("workspace", f"{TV_WORKSPACE}, {workspace_opts}")
    keyword("workspace", f"{APP_WORKSPACE}, {workspace_opts}")
    dispatch("moveworkspacetomonitor", TV_WORKSPACE, monitor)
    dispatch("moveworkspacetomonitor", APP_WORKSPACE, monitor)


def rescan_for(seconds: float) -> None:
    ensure_workspace_rules()
    rescan_existing_windows(show=True)
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        rescan_existing_windows(show=False)
        time.sleep(0.35)


def main() -> None:
    if len(sys.argv) > 1:
        if sys.argv[1] == "--rescan-once":
            ensure_workspace_rules()
            rescan_existing_windows()
            return
        if sys.argv[1] == "--rescan-for":
            try:
                seconds = float(sys.argv[2])
            except (IndexError, ValueError):
                seconds = 10.0
            rescan_for(seconds)
            return

    ensure_workspace_rules()
    rescan_existing_windows(show=False)
    while True:
        path = event_socket_path()
        if path is None or not path.exists():
            time.sleep(2)
            continue

        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
                sock.connect(str(path))
                with sock.makefile("r", encoding="utf-8", errors="replace") as events:
                    for line in events:
                        handle_event(line.rstrip("\n"))
        except OSError:
            time.sleep(1)


if __name__ == "__main__":
    main()
