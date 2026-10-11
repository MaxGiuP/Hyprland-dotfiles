# Isolated agent desktop

A private 1600x900 X11 display (`:99`) gives agents their own focus, pointer,
keyboard, clipboard, accessibility bus and window manager. It does not switch
Hyprland workspaces or inject input through host `uinput` devices.

This is input/display isolation, NOT a security or filesystem sandbox: programs
still run as the logged-in user and can access that user's files/network.

## Install (Arch Linux)

Run `bash scripts/agent-desktop/install.sh` from the repository root.
Required system packages: tigervnc, xorg-xauth, xorg-xdpyinfo, xdotool,
imagemagick, dbus, python, at-spi2-core, curl, libarchive, gnupg.
Openbox is installed user-locally from a signed Arch package if needed; the
installer verifies its signature using the existing Arch pacman keyring.
No root privilege is used. Downloaded packages/binaries are not stored in Git.

The installer installs a user service and the `agent-desktop` command, and adds
only `mcp_servers.agent-desktop` through `hermes config set` if Hermes is present.
It starts on demand when its MCP server or a launcher command is used, not at boot.
Reload MCP servers or restart Hermes to expose the tools in an existing session.

## Use

    agent-desktop start
    agent-desktop run PROGRAM ARGUMENTS...
    agent-desktop view
    agent-desktop screenshot /absolute/path.png
    agent-desktop status
    agent-desktop stop

`view` is intentionally read-only and does not share either clipboard. It connects
over a mode-0600 Unix socket in a mode-0700 runtime directory; no VNC TCP listener
is opened. Closing the viewer does not stop the agent desktop.

MCP tools: desktop_state, list_windows, click, type_text, press_key,
activate_window, launch_app. Read a screenshot first, act using its desktop
coordinates/window IDs, then read back. No tool may type secrets or verification
codes. Existing host windows are not visible/addressable through these tools.

Use the MCP named `agent-desktop`, not generic host desktop shortcuts,
`ydotool`, a default-display cua-driver daemon or unqualified xdotool.
The installed cua-driver's MPX route can attempt host uinput, so this MCP uses
X-display-local xdotool instead and does not expose cua-driver as its backend.

Single-instance apps can redirect a launch to a process already on the human
desktop. Use a dedicated browser profile and explicit new-instance options,
then verify the new window appears in list_windows. Existing windows cannot
normally be moved between X servers.

## Windows / VMware boundary

The running Windows PLC VM is not automatically moved here or instrumented.
For background guest control, connect to an authorised guest/hypervisor VNC
endpoint from a viewer launched inside the agent display, or establish a guest
automation agent. This requires separate configuration; copying the VMware
console's host window or adding a shared folder does not establish that channel.
Do not restart a running VM, enable an unauthenticated network listener, change
licensing or interact with PLC hardware without separate authorisation.

## Verification

`verify_app.py` is an optional GTK3 test window; run it with the system Python:

    agent-desktop run python ~/.local/share/agent-desktop/verify_app.py

`verify_mcp.py` uses the Hermes virtualenv MCP SDK. It types an exact mixed-case,
punctuation-containing string, clicks Save, reads the resulting file, records
human focus/pointer before/after, captures the private screen and checks that a
host VMware window ID is rejected. Its artifacts live only under
`~/.local/share/agent-desktop/`, never in Git. Human activity during the test can
naturally change the host focus/pointer measurements.

Stop/uninstall: remove only this MCP registration with
`hermes mcp remove agent-desktop`, stop `agent-desktop.service`, unlink its user
unit and `~/.local/bin/agent-desktop`, then remove its own local data directory.
Keep other MCPs, the VMware VM and unrelated user units untouched.
