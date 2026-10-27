# WhiteSur SDDM keyboard compatibility

Plasma 6.8 no longer exports `VirtualKeyboardLoader` from
`org.kde.breeze.components`. The installed WhiteSur-dark theme still uses it,
which prevents the entire theme from loading and triggers SDDM's embedded
fallback theme.

The three QML files in
`system-overrides/usr/share/sddm/themes/WhiteSur-dark/` restore the keyboard
components within the theme itself. They are unchanged copies from the local
Arch `plasma-workspace 6.7.5-1` package, originally maintained in KDE's
[lookandfeel/components](https://invent.kde.org/plasma/plasma-workspace/-/tree/v6.7.5/lookandfeel/components).
Their original copyright and SPDX license notices are retained. The X11 Qt
virtual keyboard and Wayland backend are both included.

Run from the repository root to install the three missing files:

```sh
sudo install -m 0644 system-overrides/usr/share/sddm/themes/WhiteSur-dark/VirtualKeyboardLoader.qml system-overrides/usr/share/sddm/themes/WhiteSur-dark/VirtualKeyboard.qml system-overrides/usr/share/sddm/themes/WhiteSur-dark/VirtualKeyboard_wayland.qml /usr/share/sddm/themes/WhiteSur-dark/
```

SDDM loads the files at the next login. Restarting SDDM would end the current
desktop session, so no service restart is needed for installation.

Test without opening a window on the current desktop or performing login:

```sh
xvfb-run -a python3 scripts/sddm/verify-theme.py /usr/share/sddm/themes/WhiteSur-dark --platform xcb
```

This uses the same X11 Qt backend as the installed SDDM greeter. It verifies
that the requested theme creates a view, stays running, and reports neither
fallback nor QML reference/type errors. Existing theme warnings about deprecated
handlers, layout anchors, and undefined optional appearance strings are printed.
The test does not authenticate or submit a password. An actual logout/login is
still required to check the real greeter on the physical monitors.

The default offscreen mode is useful for reproducing the missing-type error,
but the existing theme also reports keyboard-layout and Caps Lock errors there
because that backend does not provide X11 keyboard state. Use the Xvfb command
above to validate the complete theme.
