#!/usr/bin/env -S\_/bin/sh\_-c\_"source\_\$(eval\_echo\_\$ILLOGICAL_IMPULSE_VIRTUAL_ENV)/bin/activate&&exec\_python\_-E\_"\$0"\_"\$@""
import argparse
import re
import os
from os.path import expandvars as os_expandvars
from typing import Dict, List

TITLE_REGEX = "#+!"
HIDE_COMMENT = "[hidden]"
MOD_SEPARATORS = ['+', ' ']
COMMENT_BIND_PATTERN = "#/#"

parser = argparse.ArgumentParser(description='Hyprland keybind reader')
parser.add_argument('--path', type=str, default="$HOME/.config/hypr/hyprland/keybinds.lua", help='path to keybind file (sourcing isn\'t supported)')
args = parser.parse_args()
content_lines = []
reading_line = 0

# Little Parser made for hyprland keybindings conf file
Variables: Dict[str, str] = {}


class KeyBinding(dict):
    def __init__(self, mods, key, dispatcher, params, comment) -> None:
        self["mods"] = mods
        self["key"] = key
        self["dispatcher"] = dispatcher
        self["params"] = params
        self["comment"] = comment

class Section(dict):
    def __init__(self, children, keybinds, name) -> None:
        self["children"] = children
        self["keybinds"] = keybinds
        self["name"] = name


def read_content(path: str) -> str:
    if (not os.access(os.path.expanduser(os.path.expandvars(path)), os.R_OK)):
        return ("error")
    with open(os.path.expanduser(os.path.expandvars(path)), "r") as file:
        return file.read()


def logical_comment_line(line: str) -> str:
    stripped = line.strip()
    if stripped.startswith("--"):
        return stripped[2:].lstrip()
    return line


def lua_long_bracket_end(text: str, index: int) -> str | None:
    if index >= len(text) or text[index] != "[":
        return None
    pos = index + 1
    while pos < len(text) and text[pos] == "=":
        pos += 1
    if pos < len(text) and text[pos] == "[":
        return "]" + text[index + 1:pos] + "]"
    return None


def find_lua_call_end(text: str, open_paren: int) -> int:
    depth = 0
    quote = None
    escape = False
    long_end = None
    i = open_paren
    while i < len(text):
        if long_end:
            if text.startswith(long_end, i):
                i += len(long_end)
                long_end = None
                continue
            i += 1
            continue
        ch = text[i]
        if quote:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == quote:
                quote = None
            i += 1
            continue
        candidate = lua_long_bracket_end(text, i)
        if candidate:
            long_end = candidate
            i += len(candidate) - 1
            continue
        if ch in ("'", '"'):
            quote = ch
        elif ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def split_lua_args(text: str) -> List[str]:
    args = []
    start = 0
    depth = 0
    quote = None
    escape = False
    long_end = None
    i = 0
    while i < len(text):
        if long_end:
            if text.startswith(long_end, i):
                i += len(long_end)
                long_end = None
                continue
            i += 1
            continue
        ch = text[i]
        if quote:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == quote:
                quote = None
            i += 1
            continue
        candidate = lua_long_bracket_end(text, i)
        if candidate:
            long_end = candidate
            i += len(candidate) - 1
            continue
        if ch in ("'", '"'):
            quote = ch
        elif ch in "({[":
            depth += 1
        elif ch in ")}]":
            depth -= 1
        elif ch == "," and depth == 0:
            args.append(text[start:i].strip())
            start = i + 1
        i += 1
    args.append(text[start:].strip())
    return args


def decode_lua_string(value: str) -> str:
    value = value.strip()
    long_match = re.match(r'^\[(=*)\[(.*)\]\1\]$', value)
    if long_match:
        return long_match.group(2)
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
        return bytes(value[1:-1], "utf-8").decode("unicode_escape")
    if value == "nil":
        return ""
    return value


def get_lua_option_description(options: str) -> str:
    match = re.search(r'description\s*=\s*(\[(=*)\[.*?\]\2\]|"([^"\\]|\\.)*"|\'([^\'\\]|\\.)*\')', options)
    if not match:
        return ""
    return decode_lua_string(match.group(1))


def parse_mods(modstring: str) -> List[str]:
    if not modstring:
        return []
    modstring = modstring.replace("+", " ")
    display_names = {
        "SUPER": "Super",
        "CTRL": "Ctrl",
        "CONTROL": "Ctrl",
        "ALT": "Alt",
        "SHIFT": "Shift",
    }
    return [display_names.get(part.upper(), part) for part in modstring.split() if part]


def autogenerate_comment(dispatcher: str, params: str = "") -> str:
    match dispatcher:

        case "resizewindow":
            return "Resize window"

        case "movewindow":
            if(params == ""):
                return "Move window"
            else:
                return "Window: move in {} direction".format({
                    "l": "left",
                    "r": "right",
                    "u": "up",
                    "d": "down",
                }.get(params, "null"))

        case "pin":
            return "Window: pin (show on all workspaces)"

        case "splitratio":
            return "Window split ratio {}".format(params)

        case "togglefloating":
            return "Float/unfloat window"

        case "resizeactive":
            return "Resize window by {}".format(params)

        case "killactive":
            return "Close window"

        case "fullscreen":
            return "Toggle {}".format(
                {
                    "0": "fullscreen",
                    "1": "maximization",
                    "2": "fullscreen on Hyprland's side",
                }.get(params, "null")
            )

        case "fakefullscreen":
            return "Toggle fake fullscreen"

        case "workspace":
            if params == "+1":
                return "Workspace: focus right"
            elif params == "-1":
                return "Workspace: focus left"
            return "Focus workspace {}".format(params)

        case "movefocus":
            return "Window: move focus {}".format(
                {
                    "l": "left",
                    "r": "right",
                    "u": "up",
                    "d": "down",
                }.get(params, "null")
            )

        case "swapwindow":
            return "Window: swap in {} direction".format(
                {
                    "l": "left",
                    "r": "right",
                    "u": "up",
                    "d": "down",
                }.get(params, "null")
            )

        case "movetoworkspace":
            if params == "+1":
                return "Window: move to right workspace (non-silent)"
            elif params == "-1":
                return "Window: move to left workspace (non-silent)"
            return "Window: move to workspace {} (non-silent)".format(params)

        case "movetoworkspacesilent":
            if params == "+1":
                return "Window: move to right workspace"
            elif params == "-1":
                return "Window: move to right workspace"
            return "Window: move to workspace {}".format(params)

        case "togglespecialworkspace":
            return "Workspace: toggle special"

        case "exec":
            return "Execute: {}".format(params)

        case _:
            return ""

def get_keybind_at_line(line_number, line_start = 0, line_override = None):
    global content_lines
    line = logical_comment_line(line_override if line_override is not None else content_lines[line_number])
    _, keys = line.split("=", 1)
    keys, *comment = keys.split("#", 1)

    mods, key, dispatcher, *params = list(map(str.strip, keys.split(",", 4)))
    params = "".join(map(str.strip, params))

    # Remove empty spaces
    comment = list(map(str.strip, comment))
    # Add comment if it exists, else generate it
    if comment:
        comment = comment[0]
        if comment.startswith("[hidden]"):
            return None
    else:
        comment = autogenerate_comment(dispatcher, params)

    mods = parse_mods(mods)

    return KeyBinding(mods, key, dispatcher, params, comment)


def get_lua_keybind(line: str):
    stripped = line.strip()
    if not stripped.startswith("bind("):
        return None
    open_paren = stripped.find("(")
    close_paren = find_lua_call_end(stripped, open_paren)
    if close_paren < 0:
        return None
    call = stripped[open_paren + 1:close_paren]
    trailing = stripped[close_paren + 1:].strip()
    comment = ""
    if trailing.startswith("--"):
        comment = trailing[2:].strip()
    if comment.startswith(HIDE_COMMENT):
        return None

    args = split_lua_args(call)
    while len(args) < 5:
        args.append("")
    mods = decode_lua_string(args[0])
    key = decode_lua_string(args[1])
    dispatcher = decode_lua_string(args[2])
    params = decode_lua_string(args[3])
    options = args[4]

    if not comment:
        comment = get_lua_option_description(options)
    if not comment:
        comment = autogenerate_comment(dispatcher, params)

    return KeyBinding(parse_mods(mods), key, dispatcher, params, comment)

def get_binds_recursive(current_content, scope):
    global content_lines
    global reading_line
    # print("get_binds_recursive({0}, {1}) [@L{2}]".format(current_content, scope, reading_line + 1))
    while reading_line < len(content_lines): # TODO: Adjust condition
        line = content_lines[reading_line]
        logical_line = logical_comment_line(line)
        heading_search_result = re.search(TITLE_REGEX, logical_line)
        # print("Read line {0}: {1}\tisHeading: {2}".format(reading_line + 1, content_lines[reading_line], "[{0}, {1}, {2}]".format(heading_search_result.start(), heading_search_result.start() == 0, ((heading_search_result != None) and (heading_search_result.start() == 0))) if heading_search_result != None else "No"))
        if ((heading_search_result != None) and (heading_search_result.start() == 0)): # Found title
            # Determine scope
            heading_scope = logical_line.find('!')
            # Lower? Return
            if(heading_scope <= scope):
                reading_line -= 1
                return current_content

            section_name = logical_line[(heading_scope+1):].strip()
            # print("[[ Found h{0} at line {1} ]] {2}".format(heading_scope, reading_line+1, content_lines[reading_line]))
            reading_line += 1
            current_content["children"].append(get_binds_recursive(Section([], [], section_name), heading_scope))

        elif logical_line.startswith(COMMENT_BIND_PATTERN):
            keybind = get_keybind_at_line(reading_line, line_start=len(COMMENT_BIND_PATTERN), line_override=logical_line)
            if(keybind != None):
                current_content["keybinds"].append(keybind)

        elif line.strip().startswith("bind("):
            keybind = get_lua_keybind(line)
            if(keybind != None):
                current_content["keybinds"].append(keybind)

        elif line == "" or not line.lstrip().startswith("bind"): # Comment, ignore
            pass

        else: # Normal keybind
            keybind = get_keybind_at_line(reading_line)
            if(keybind != None):
                current_content["keybinds"].append(keybind)

        reading_line += 1

    return current_content;

def parse_keys(path: str) -> Dict[str, List[KeyBinding]]:
    global content_lines
    content_lines = read_content(path).splitlines()
    if not content_lines or content_lines[0] == "error":
        return "error"
    return get_binds_recursive(Section([], [], ""), 0)


if __name__ == "__main__":
    import json

    ParsedKeys = parse_keys(args.path)
    print(json.dumps(ParsedKeys))
