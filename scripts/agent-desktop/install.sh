#!/usr/bin/env bash
set -euo pipefail
SOURCE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/.local/share/agent-desktop"
for program in Xvnc xauth xdpyinfo xdotool import dbus-run-session gdbus python vncviewer curl bsdtar gpgv; do
    command -v "$program" >/dev/null || { printf 'Missing prerequisite: %s\n' "$program" >&2; exit 1; }
done
mkdir -p "$DEST" "$HOME/.local/bin" "$HOME/.config/systemd/user"
for filename in agent_desktop.py desktop_mcp.py agent-desktop.service README.md verify_app.py verify_mcp.py; do
    if [[ "$SOURCE/$filename" != "$DEST/$filename" ]]; then
        cp -- "$SOURCE/$filename" "$DEST/$filename"
    fi
done
if [[ ! -x "$DEST/root/usr/bin/openbox" ]]; then
    command -v pacman >/dev/null || { printf 'User-local Openbox installation requires Arch pacman metadata.\n' >&2; exit 1; }
    URL="$(pacman -Sp --print-format '%n %l' openbox | python -c 'import sys; print(next(line.split()[1] for line in sys.stdin if line.startswith("openbox ")))')"
    mkdir -p "$DEST/packages" "$DEST/root"
    curl -fL --retry 2 -o "$DEST/packages/openbox.pkg.tar.zst" "$URL"
    curl -fL --retry 2 -o "$DEST/packages/openbox.pkg.tar.zst.sig" "$URL.sig"
    gpgv --keyring /etc/pacman.d/gnupg/pubring.gpg "$DEST/packages/openbox.pkg.tar.zst.sig" "$DEST/packages/openbox.pkg.tar.zst"
    bsdtar -xf "$DEST/packages/openbox.pkg.tar.zst" -C "$DEST/root"
fi
chmod +x "$DEST/agent_desktop.py"
LINK="$HOME/.local/bin/agent-desktop"
if [[ -e "$LINK" || -L "$LINK" ]]; then
    [[ "$(readlink -f -- "$LINK")" == "$DEST/agent_desktop.py" ]] || { printf 'Refusing to replace unrelated launcher: %s\n' "$LINK" >&2; exit 1; }
else
    ln -s -- "$DEST/agent_desktop.py" "$LINK"
fi
UNIT="$HOME/.config/systemd/user/agent-desktop.service"
if [[ -e "$UNIT" || -L "$UNIT" ]]; then
    if [[ -L "$UNIT" ]]; then
        [[ "$(readlink -f -- "$UNIT")" == "$DEST/agent-desktop.service" ]] || { printf 'Refusing to replace unrelated unit: %s\n' "$UNIT" >&2; exit 1; }
    else
        cmp -s "$UNIT" "$DEST/agent-desktop.service" || { printf 'Review existing unit before replacing: %s\n' "$UNIT" >&2; exit 1; }
    fi
else
    ln -s -- "$DEST/agent-desktop.service" "$UNIT"
fi
systemctl --user daemon-reload
"$LINK" start
if command -v hermes >/dev/null; then
    hermes config set mcp_servers.agent-desktop "{\"command\":\"$LINK\",\"args\":[\"mcp\"],\"enabled\":true,\"connect_timeout\":30}"
    hermes mcp test agent-desktop
fi
printf 'Installed. Watch with: agent-desktop view\n'
