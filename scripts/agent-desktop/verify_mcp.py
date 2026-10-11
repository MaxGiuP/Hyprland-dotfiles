import asyncio
import base64
import json
from pathlib import Path
import subprocess
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

BASE = Path.home()/'.local/share/agent-desktop'

def host_state():
    focus = json.loads(subprocess.check_output(['hyprctl', 'activewindow', '-j'], text=True)).get('address')
    pointer = subprocess.check_output(['hyprctl', 'cursorpos'], text=True).strip()
    return {'focus': focus, 'pointer': pointer}

def data(result):
    return json.loads(next(c.text for c in result.content if c.type == 'text'))

async def main():
    params = StdioServerParameters(command=str(Path.home()/'.local/bin/agent-desktop'), args=['mcp'])
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            init = await session.initialize()
            tools = (await session.list_tools()).tools
            windows = data(await session.call_tool('list_windows', {}))
            target = next(w for w in windows if w['title'] == 'Agent Desktop Verification')
            before = host_state()
            expected = 'Background input ABC abc 123 ! @ / \\ test'
            result_path = BASE/'input-result.txt'
            result_path.unlink(missing_ok=True)
            calls = [('activate_window', {'window_id': target['window_id']}), ('click', {'x': target['x']+260, 'y': target['y']+70}), ('press_key', {'key': 'ctrl+a'}), ('type_text', {'text': expected}), ('click', {'x': target['x']+260, 'y': target['y']+118})]
            for name, arguments in calls:
                result = await session.call_tool(name, arguments)
                assert not result.is_error, str(result)
            await asyncio.sleep(.1)
            after = host_state()
            actual = result_path.read_text() if result_path.exists() else None
            shot = await session.call_tool('desktop_state', {})
            for c in shot.content:
                if c.type == 'image':
                    (BASE/'mcp-test.png').write_bytes(base64.b64decode(c.data))
            host_wid = int(subprocess.check_output(['xdotool','search','--name','PLC Programming - VMware Workstation'], text=True).splitlines()[0])
            rejected = await session.call_tool('activate_window', {'window_id': host_wid})
            report = {'server': init.server_info.model_dump(), 'tool_count': len(tools), 'expected': expected, 'actual': actual, 'text_matches': actual == expected, 'host_before': before, 'host_after': after, 'host_focus_unchanged': before['focus'] == after['focus'], 'host_pointer_unchanged': before['pointer'] == after['pointer'], 'host_vm_window_rejected': bool(rejected.is_error), 'visible_windows': windows, 'display': ':99', 'size': [1600,900]}
            (BASE/'verification.json').write_text(json.dumps(report, indent=2))
            print(json.dumps(report, indent=2))
            assert report['text_matches'], 'Agent input did not match'
            assert report['host_vm_window_rejected'], 'Host VM window was not rejected'

asyncio.run(main())
