# Desktop bridge

Three small native helpers replace the recurring Python processes used by this
Hyprland setup:

- `kdeconnect-bridge` publishes KDE Connect state to
  `$XDG_RUNTIME_DIR/linmax-desktop-bridge/kdeconnect.json` for Quickshell.
- `kdeconnect-cursor-sync` maps the KDE Connect Xwayland pointer directly onto
  Hyprland without spawning `xdotool` and `hyprctl` every 25 ms.
- `tv-mode-daemon` combines TV window routing and Xbox controller shortcuts in
  one process.

Build and install:

```sh
cargo build --release --locked
install -Dm755 target/release/kdeconnect-bridge "$HOME/.local/bin/kdeconnect-bridge"
install -Dm755 target/release/kdeconnect-cursor-sync "$HOME/.local/bin/kdeconnect-cursor-sync"
install -Dm755 target/release/tv-mode-daemon "$HOME/.local/bin/tv-mode-daemon"
systemctl --user daemon-reload
systemctl --user disable --now tv-controller-toggle.service tv-stack-listener.service
systemctl --user enable --now kdeconnect-bridge.service tv-mode-daemon.service
systemctl --user try-restart kdeconnect-cursor-sync.service
```

Useful checks:

```sh
kdeconnect-bridge --once
kdeconnect-cursor-sync --once
tv-mode-daemon --check
```
