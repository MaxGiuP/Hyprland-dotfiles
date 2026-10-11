#!/usr/bin/env python3
"""Sync the default Hermes profile with Quickshell's wallpaper Material palette.

Generated skin only: never change model, permissions, or the selected skin.
Activate once with: hermes config set display.skin wallpaper-material
"""
import argparse
import json
import os
from pathlib import Path
import re
import tempfile
import time


def make_skin(palette):
    required = ('background', 'primary', 'secondary', 'tertiary', 'on_surface',
                'on_surface_variant', 'outline', 'outline_variant', 'error',
                'surface_container', 'surface_container_high', 'primary_container')
    for key in required:
        if not re.fullmatch(r'#[0-9a-fA-F]{6}', palette.get(key, '')):
            raise ValueError(f'Missing or invalid Material colour: {key}')
    p = palette
    dark = p.get('darkmode', True)
    ok = '#a5d6a7' if dark else '#256b32'
    warn = '#e8c28b' if dark else '#795519'
    c = {}
    for keys, value in (
        ('background', p['background']),
        ('ui_accent banner_accent banner_title ui_primary ui_tool input_rule response_border status_bar_strong session_label shell_dollar syntax_keyword', p['primary']),
        ('ui_text banner_text ui_label prompt status_bar_text', p['on_surface']),
        ('banner_dim ui_thinking status_bar_dim syntax_comment', p['on_surface_variant']),
        ('banner_border ui_border session_border', p['outline']),
        ('status_bar_bg completion_menu_bg completion_menu_meta_bg voice_status_bg', p['surface_container']),
        ('completion_menu_current_bg completion_menu_meta_current_bg selection_bg', p['primary_container']),
        ('ui_ok status_bar_good diff_added diff_added_word', ok),
        ('ui_warn status_bar_warn', warn),
        ('ui_error status_bar_bad status_bar_critical diff_removed diff_removed_word', p['error']),
        ('syntax_string', p['secondary']),
        ('syntax_number', p['tertiary']),
    ):
        c.update(dict.fromkeys(keys.split(), value))
    # Override the built-in gold light overlay too, not just its dark colours.
    return {'name': 'wallpaper-material',
            'description': 'Automatically follows the desktop wallpaper Material palette',
            'colors': c, 'light_colors': c.copy()}


def sync(source, destination):
    # Theme generation may briefly leave a partial JSON file. Preserve the last
    # good skin while retrying rather than replacing it with defaults.
    skin = None
    for attempt in range(6):
        try:
            skin = make_skin(json.loads(source.read_text()))
            break
        except (OSError, ValueError):
            if attempt == 5:
                raise
            time.sleep(0.2)
    if skin is None:
        raise RuntimeError('Material palette could not be loaded')
    content = json.dumps(skin, indent=2) + '\n'  # JSON is valid YAML.
    if destination.exists() and destination.read_text() == content:
        return False
    destination.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.wallpaper-', dir=destination.parent)
    try:
        with os.fdopen(fd, 'w') as output:
            output.write(content)
        os.replace(temporary, destination)
    finally:
        Path(temporary).unlink(missing_ok=True)
    print(f'Updated {destination}: accent {skin["colors"]["ui_accent"]}', flush=True)
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    state = Path(os.environ.get('XDG_STATE_HOME', Path.home() / '.local/state'))
    home = Path(os.environ.get('HERMES_HOME', Path.home() / '.hermes'))
    parser.add_argument('--source', type=Path, default=state / 'quickshell/user/generated/colors.json')
    parser.add_argument('--destination', type=Path, default=home / 'skins/wallpaper-material.yaml')
    args = parser.parse_args()
    sync(args.source, args.destination)


if __name__ == '__main__':
    main()
