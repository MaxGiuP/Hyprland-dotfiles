#!/usr/bin/env python3
"""Independent X11 input/display session; not a filesystem/security sandbox."""
import argparse
import ast
import json
import os
from pathlib import Path
import secrets
import signal
import subprocess
import sys
import time

BASE = Path.home() / '.local/share/agent-desktop'
RUNTIME = Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}')) / 'agent-desktop'
UNIT = 'agent-desktop.service'
DISPLAY = ':99'


def isolated_env():
    data = json.loads((RUNTIME / 'environment.json').read_text())
    env = os.environ.copy()
    for name in ('WAYLAND_DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE', 'SWAYSOCK', 'AT_SPI_BUS_ADDRESS', 'SESSION_MANAGER'):
        env.pop(name, None)
    env.update(data)
    return env


def control_env():
    env = os.environ.copy()
    env['XDG_RUNTIME_DIR'] = str(RUNTIME.parent)
    env['DBUS_SESSION_BUS_ADDRESS'] = 'unix:path=' + str(RUNTIME.parent / 'bus')
    return env


def ensure_started():
    subprocess.run(['systemctl', '--user', 'start', UNIT], env=control_env(), check=True)
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        try:
            env = isolated_env()
            if subprocess.run(['xdpyinfo'], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
                return env
        except (FileNotFoundError, json.JSONDecodeError):
            pass
        time.sleep(.15)
    raise RuntimeError('Agent display did not become ready; inspect journalctl --user -u agent-desktop.service')


def serve_session():
    os.umask(0o077)
    RUNTIME.mkdir(mode=0o700, parents=True, exist_ok=True)
    auth = RUNTIME / 'Xauthority'
    auth.touch(mode=0o600)
    subprocess.run(['xauth', '-f', str(auth), 'add', DISPLAY, '.', secrets.token_hex(16)], check=True)
    env = os.environ.copy()
    for name in ('WAYLAND_DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE', 'SWAYSOCK', 'AT_SPI_BUS_ADDRESS', 'SESSION_MANAGER'):
        env.pop(name, None)
    env.update(DISPLAY=DISPLAY, XAUTHORITY=str(auth), XDG_SESSION_TYPE='x11', XDG_CURRENT_DESKTOP='Openbox', GTK_MODULES='gail:atk-bridge')
    children = []
    def stop(*_):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        children.append(subprocess.Popen(['Xvnc', DISPLAY, '-geometry', '1600x900', '-depth', '24', '-auth', str(auth), '-nolisten', 'tcp', '-rfbport', '-1', '-rfbunixpath', str(RUNTIME / 'vnc.sock'), '-rfbunixmode', '0600', '-SecurityTypes', 'None', '-AlwaysShared', '-desktop', 'Agent Desktop', '-AcceptCutText=0', '-SendCutText=0', '-noreset'], env=env))
        deadline = time.monotonic() + 10
        while subprocess.run(['xdpyinfo'], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
            if children[0].poll() is not None or time.monotonic() > deadline:
                raise RuntimeError('Xvnc startup failed')
            time.sleep(.1)
        # Explicitly own the private accessibility registry; D-Bus systemd
        # activation would otherwise target the user's existing host registry.
        address = subprocess.check_output(['gdbus', 'call', '--session', '--dest', 'org.a11y.Bus', '--object-path', '/org/a11y/bus', '--method', 'org.a11y.Bus.GetAddress'], env=env, text=True)
        env['AT_SPI_BUS_ADDRESS'] = ast.literal_eval(address.strip())[0]
        children.append(subprocess.Popen(['/usr/lib/at-spi2-registryd'], env=env))
        env['LD_LIBRARY_PATH'] = str(BASE / 'root/usr/lib')
        env['XDG_DATA_DIRS'] = str(BASE / 'root/usr/share') + ':/usr/local/share:/usr/share'
        children.append(subprocess.Popen([str(BASE / 'root/usr/bin/openbox'), '--config-file', str(BASE / 'root/etc/xdg/openbox/rc.xml')], env=env))
        keys = ('DISPLAY', 'XAUTHORITY', 'DBUS_SESSION_BUS_ADDRESS', 'AT_SPI_BUS_ADDRESS', 'XDG_SESSION_TYPE', 'XDG_CURRENT_DESKTOP', 'GTK_MODULES', 'LD_LIBRARY_PATH', 'XDG_DATA_DIRS')
        tmp = RUNTIME / 'environment.tmp'
        tmp.write_text(json.dumps({k: env[k] for k in keys if k in env}))
        tmp.replace(RUNTIME / 'environment.json')
        print('Agent desktop ready on :99; VNC uses a private Unix socket only.', flush=True)
        while True:
            if any(p.poll() is not None for p in children):
                raise RuntimeError('Display or window manager exited')
            time.sleep(.5)
    except KeyboardInterrupt:
        pass
    finally:
        (RUNTIME / 'environment.json').unlink(missing_ok=True)
        for p in reversed(children):
            if p.poll() is None:
                p.terminate()
        for p in children:
            try:
                p.wait(timeout=3)
            except subprocess.TimeoutExpired:
                p.kill()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['start', 'stop', 'status', 'view', 'run', 'mcp', 'screenshot', 'serve-session'])
    parser.add_argument('args', nargs=argparse.REMAINDER)
    ns = parser.parse_args()
    if ns.action == 'serve-session':
        serve_session(); return
    if ns.action in ('status', 'stop'):
        os.execvpe('systemctl', ['systemctl', '--user', 'status' if ns.action == 'status' else 'stop', UNIT], control_env())
    env = ensure_started()
    if ns.action == 'start':
        print('Agent desktop ready: DISPLAY=:99'); return
    if ns.action == 'view':
        # Viewer stays on the human display. It cannot inject keys or share clipboard.
        os.execvp('vncviewer', ['vncviewer', '-ViewOnly', '-AcceptClipboard=0', '-SendClipboard=0', '-Shared', str(RUNTIME / 'vnc.sock')])
    if ns.action == 'mcp':
        # Use X-display-local input only. No uinput/MPX device can touch the host.
        os.execvpe('/usr/bin/python', ['python', str(BASE / 'desktop_mcp.py')], env)
    if ns.action == 'screenshot':
        path = ns.args[0] if ns.args else str(BASE / 'screenshot.png')
        subprocess.run(['import', '-window', 'root', path], env=env, check=True)
        print(path); return
    if ns.action == 'run':
        if not ns.args:
            parser.error('run needs a program and arguments')
        with (BASE / 'apps.log').open('ab') as log:
            p = subprocess.Popen(ns.args, env=env, stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True)
        print(f'Launched on agent desktop, pid={p.pid}')

if __name__ == '__main__':
    main()
