#!/usr/bin/env python3
"""Small MCP server for a private X display. Never uses uinput or the host display."""
import base64
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

EXPECTED_DISPLAY = ':99'
if os.environ.get('DISPLAY') != EXPECTED_DISPLAY or os.environ.get('WAYLAND_DISPLAY'):
    raise SystemExit('Refusing to run without the isolated :99 display')


def cmd(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.PIPE, timeout=15).strip()


def window_ids():
    try:
        return [int(x) for x in cmd('xdotool', 'search', '--onlyvisible', '--name', '.').splitlines()]
    except subprocess.CalledProcessError:
        return []


def exact_window(wid):
    wid = int(wid)
    if wid not in window_ids():
        raise ValueError('Window is not visible on the isolated agent display')
    return str(wid)


def snapshot():
    with tempfile.NamedTemporaryFile(suffix='.png') as f:
        subprocess.run(['import', '-window', 'root', f.name], check=True, stderr=subprocess.PIPE, timeout=15)
        image = base64.b64encode(Path(f.name).read_bytes()).decode()
    return [{'type': 'text', 'text': json.dumps({'display': ':99', 'width': 1600, 'height': 900, 'coordinate_frame': 'desktop', 'windows': windows()})}, {'type': 'image', 'data': image, 'mimeType': 'image/png'}]


def windows():
    result = []
    for wid in window_ids():
        try:
            title = cmd('xdotool', 'getwindowname', str(wid))
            geometry = dict(line.split('=', 1) for line in cmd('xdotool', 'getwindowgeometry', '--shell', str(wid)).splitlines() if '=' in line)
            try:
                pid = int(cmd('xdotool', 'getwindowpid', str(wid)))
            except (subprocess.CalledProcessError, ValueError):
                pid = None
            result.append({'window_id': wid, 'title': title, 'pid': pid, **{k.lower(): int(geometry[k]) for k in ('X', 'Y', 'WIDTH', 'HEIGHT')}})
        except subprocess.CalledProcessError:
            pass
    return result


def activate(wid):
    cmd('xdotool', 'windowactivate', '--sync', exact_window(wid))


def text_result(data):
    return [{'type': 'text', 'text': json.dumps(data)}]


def call(name, args):
    if name == 'desktop_state':
        return snapshot()
    if name == 'list_windows':
        return text_result(windows())
    if name == 'click':
        x, y = args['x'], args['y']
        if not (0 <= x < 1600 and 0 <= y < 900):
            raise ValueError('Point outside isolated desktop')
        button = {'left': '1', 'middle': '2', 'right': '3'}[args.get('button', 'left')]
        count = args.get('count', 1)
        if count not in (1, 2):
            raise ValueError('count must be 1 or 2')
        cmd('xdotool', 'mousemove', '--sync', str(int(x)), str(int(y)), 'click', '--repeat', str(count), '--delay', '100', button)
        return text_result({'delivered_to': ':99', 'point': [x, y], 'verify': 'Capture desktop_state to read back the result'})
    if name == 'type_text':
        text = args['text']
        if len(text) > 20000:
            raise ValueError('Text exceeds 20000 characters')
        if args.get('window_id') is not None:
            activate(args['window_id'])
        subprocess.run(['xdotool', 'type', '--clearmodifiers', '--delay', '10', '--', text], check=True, stderr=subprocess.PIPE, timeout=240)
        return text_result({'delivered_to': ':99', 'characters': len(text), 'verify': 'Capture desktop_state to read back the text'})
    if name == 'press_key':
        key = args['key']
        if not re.fullmatch(r'[A-Za-z0-9_+]{1,100}', key):
            raise ValueError('Use an X11 key combination such as ctrl+a, Return, or Alt_L+F4')
        if args.get('window_id') is not None:
            activate(args['window_id'])
        cmd('xdotool', 'key', '--clearmodifiers', key)
        return text_result({'delivered_to': ':99', 'key': key})
    if name == 'activate_window':
        activate(args['window_id'])
        return text_result({'activated_on': ':99', 'window_id': args['window_id']})
    if name == 'launch_app':
        executable = args['executable']
        argv = [executable] + args.get('args', [])
        env = os.environ.copy()
        # An existing single-instance app may route to its host-display process.
        # Callers must use a separate browser profile or explicit new-instance flags.
        with (Path.home()/'.local/share/agent-desktop/apps.log').open('ab') as log:
            p = subprocess.Popen(argv, env=env, stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True)
        return text_result({'pid': p.pid, 'requested_display': ':99', 'verify': 'Confirm the new window with list_windows; single-instance apps can reuse a host process'})
    raise ValueError('Unknown tool')


def schema(properties=None, required=None):
    return {'type': 'object', 'properties': properties or {}, 'required': required or [], 'additionalProperties': False}

TOOLS = [
    {'name': 'desktop_state', 'description': 'Capture ONLY the isolated agent desktop as an image with visible window IDs. Coordinates are desktop pixels, 1600x900. This cannot capture the human desktop.', 'inputSchema': schema()},
    {'name': 'list_windows', 'description': 'List visible windows belonging to the isolated agent display only.', 'inputSchema': schema()},
    {'name': 'click', 'description': 'Click in isolated desktop pixels. Moves only the private X display pointer. Verify using desktop_state after acting.', 'inputSchema': schema({'x': {'type': 'integer', 'minimum': 0, 'maximum': 1599}, 'y': {'type': 'integer', 'minimum': 0, 'maximum': 899}, 'button': {'type': 'string', 'enum': ['left', 'middle', 'right']}, 'count': {'type': 'integer', 'enum': [1, 2]}}, ['x', 'y'])},
    {'name': 'type_text', 'description': 'Type into the isolated desktop focus, optionally activating a private window first. Never use for passwords or verification codes. Read back with desktop_state.', 'inputSchema': schema({'text': {'type': 'string'}, 'window_id': {'type': 'integer'}}, ['text'])},
    {'name': 'press_key', 'description': 'Send an X11 key combination to the isolated desktop, e.g. ctrl+a or Return. Cannot target the host desktop.', 'inputSchema': schema({'key': {'type': 'string'}, 'window_id': {'type': 'integer'}}, ['key'])},
    {'name': 'activate_window', 'description': 'Change focus ONLY within the private agent desktop. Refuses windows not present there.', 'inputSchema': schema({'window_id': {'type': 'integer'}}, ['window_id'])},
    {'name': 'launch_app', 'description': 'Launch an app with the private display environment. Use separate browser user-data directories/new-instance flags: existing single-instance apps may reuse a host process. Verify appearance using list_windows. This is input isolation, not a filesystem sandbox.', 'inputSchema': schema({'executable': {'type': 'string'}, 'args': {'type': 'array', 'items': {'type': 'string'}}}, ['executable'])},
]

for line in sys.stdin:
    request = None
    try:
        request = json.loads(line)
        if 'id' not in request:
            continue
        method = request['method']
        if method == 'initialize':
            result = {'protocolVersion': '2024-11-05', 'capabilities': {'tools': {}}, 'serverInfo': {'name': 'agent-desktop', 'version': '1.0.0'}}
        elif method == 'ping':
            result = {}
        elif method == 'tools/list':
            result = {'tools': TOOLS}
        elif method == 'tools/call':
            params = request['params']
            try:
                result = {'content': call(params['name'], params.get('arguments', {})), 'isError': False}
            except Exception as exc:
                result = {'content': [{'type': 'text', 'text': str(exc)}], 'isError': True}
        else:
            print(json.dumps({'jsonrpc': '2.0', 'id': request['id'], 'error': {'code': -32601, 'message': 'Method not found'}}), flush=True)
            continue
        print(json.dumps({'jsonrpc': '2.0', 'id': request['id'], 'result': result}), flush=True)
    except Exception as exc:
        if request is not None and 'id' in request:
            print(json.dumps({'jsonrpc': '2.0', 'id': request['id'], 'error': {'code': -32603, 'message': str(exc)}}), flush=True)
