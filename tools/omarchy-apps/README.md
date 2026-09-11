# Isolated Omarchy QML compatibility

This installs Omarchy's shared `qs.Commons` and `qs.Ui` QML components for
applications such as [Flea](https://github.com/thisisgm/flea), without installing
the Omarchy desktop. It does not replace Hyprland, Quickshell, themes, keybinds,
services, package repositories, file-manager defaults, or file-picker portals.

## Flea installation on this desktop

From the repository root, run these as the desktop user (no sudo):

```sh
bash tools/omarchy-apps/install-runtime.sh
bash tools/omarchy-apps/install-deps.sh
bash tools/omarchy-apps/install-flea.sh
```

The final command builds [Flea v0.2.0](https://github.com/thisisgm/flea/tree/v0.2.0)
at commit `b992e76475731041b0c13b50f5cbec3e5c04faa4`. Its source remains in
`~/.local/share/flea`; the installed binary, UI, and license are separate in
`~/.local/share/omarchy-apps/flea-0.2.0`. The source tree must match the pinned
commit and have no edits. Compilation uses installed Rust toolchain `1.98.0`
without changing the user's default; `FLEA_RUST_TOOLCHAIN` can select a different
installed compatible toolchain. The release's declared Rust minimum is too old
for the filesystem-lock APIs it uses. Python 3.11+, Git, Cargo/rustup,
desktop-file-utils, systemd user services, and compatible Quickshell/Qt are
required. See [dependency details](DEPENDENCIES.md) for the Arch packages.

Open **Flea** in the application launcher, or run `flea --gui` (`flea --tui`
selects its terminal interface). Registration includes its icon but does not
make it the default file manager or file picker. Automatic `--default`,
`--picker`, and the upstream integration-reset alias are deliberately blocked:
those routines alter Omarchy-specific bindings and global handler preferences.
The app's corresponding setup buttons will report the same refusal.

Only Flea's process gets the additional `PATH`, `QT_PLUGIN_PATH`, and
`XDG_DATA_DIRS` entries. Its private `qs` shim selects an ABI-compatible
Quickshell >=0.3.1 and supports multiple windows; the desktop's existing
single-instance Quickshell wrapper remains unchanged. Authenticated network
mounts use the signed Expect runtime through a dedicated interpreter wrapper.
No network account or cloud service is configured by installation.

Installed files are verified on rerun; differing files are preserved and
reported, rather than overwritten. For a future upgrade, preserve the old
installation first and review the new source/runtime pins. There is no
background update or package-manager entry for this source installation.

## Follow the current desktop theme

`sync-theme.py` translates Quickshell's generated palette into Omarchy's theme
format. Colours refresh on launch, and the enabled
`omarchy-apps-theme-sync.path` user unit watches palette/config changes while
Flea is open. Its short-lived service does not replace or restart Quickshell.
The curated units live in `dotfiles/.config/systemd/user/` and the installer
copies and enables only these two units.

Edit `~/.config/omarchy-apps/theme.toml` to change the base text size or fallback
green. The default size is 14; the font family follows `fc-match monospace`.
Palette inputs come from
`~/.local/state/quickshell/user/generated/colors.json`. Outputs live under
`~/.local/state/omarchy/current/`, outside Git. The bridge validates all inputs,
refuses themes owned by another manager, atomically replaces the TOML files,
then notifies Flea through `theme.name`. Unchanged colours cause no writes.

```sh
python3 -B tools/omarchy-apps/sync-theme.py --check
systemctl --user status omarchy-apps-theme-sync.path
python3 -B -m unittest discover -s tools/omarchy-apps -p 'test_*.py'
```

To stop live palette synchronization, use
`systemctl --user disable --now omarchy-apps-theme-sync.path`. Launch-time
refresh still works. If removing Flea later, preserve any personal Flea
settings; the downloaded source, runtime, and generated theme are separate
from this repository's configuration files.

Verification on installation: 602 Rust tests, 2,999 JavaScript checks, upstream
keymap checks, and 15 theme/unit tests passed. The installed GUI loaded with
the generated palette and no reported QML errors; Expect and HEIC decoding
passed runtime checks. Live remote-server authentication and the optional
cloud integrations were not exercised.

## Install the shared runtime

Run as your regular desktop user:

```sh
bash tools/omarchy-apps/install-runtime.sh
```

The destination is `~/.local/share/omarchy-apps/shell`. The installer fetches
[official Omarchy sources at commit 31bd80daa4613ffdee995ac27467fce5a2990806](https://github.com/omacom/omarchy/tree/31bd80daa4613ffdee995ac27467fce5a2990806/shell),
verifies the pinned SHA-256 before extraction, and retains the upstream license
and source provenance. The digest pins the reviewed archive; it is not an
upstream signature. No downloaded installer or setup script is executed.

Only `Commons`, `Ui`, the upstream license, and provenance are installed. Files
are staged beside the destination, then renamed into place. Rerunning verifies
that the existing tree exactly matches; a changed or unfamiliar destination is
left intact and reported. Preserve it elsewhere yourself before an intentional
upgrade. Cleanup removes only this invocation's temporary staging directory.

Prerequisites are Bash, curl, GNU tar/coreutils, diffutils, and findutils. The
runtime itself needs a compatible Quickshell/Qt installation; Flea v0.2.0 is
intended for Quickshell 0.3.1. This installer does not alter packages or select
which Quickshell executable other applications use.

## Connecting a QML application

Flea v0.2.0's `ui/Commons` and `ui/Ui` symlinks normally point into
`/usr/share/omarchy/shell`. In a separate, user-local Flea installation, point
those two links at this runtime's corresponding directories, then launch with
`FLEA_UI` set to that installation's `ui` directory. Do not replace shared
system files or export another application's QML imports globally.

The shared components use ordinary Qt/Quickshell imports plus `hyprctl` and
`fc-match`; they do not require the Omarchy shell process. They read palette and
style inputs from `~/.local/state/omarchy/current/theme/{colors,shell}.toml`,
and optional user style overrides from `~/.config/omarchy/shell.toml`. Flea
watches `~/.local/state/omarchy/current/theme.name` to reload its theme. A
separate bridge generates those inputs from the existing desktop palette;
the shared-runtime installer itself deliberately does not modify the theme.

## Boundaries and optional features

This is compatibility for selected QML applications, **not a guarantee that
every Omarchy program will work**. Other apps may need additional shared
modules, distribution-specific commands, services, or a different runtime
revision. Review and test each application independently.

Flea's ordinary local browsing does not need Omarchy's package manager. Keep
its `--default` and `--picker` setup commands unused unless their global
integration is separately reviewed: upstream also edits Omarchy-specific
Hyprland bindings and portal configuration. Likewise, Flea's optional Dropbox
installation button calls Omarchy-only commands and is unsupported here. Do
not create a fake `omarchy` CLI or install cloud services just to satisfy it.

The user-local dependency installer supplies these feature-specific runtimes:

- `xdg-terminal-exec`: the standard terminal-launch helper used by Flea's
  terminal button; its official shell implementation can be installed locally.
- `expect`: needed by Flea's password-authenticated network mount helper, not
  ordinary local browsing. The helper location can be supplied with
  `FLEA_GIO_AUTH`; its default interpreter is `/usr/bin/expect`.
- `kimageformats`: adds HEIC and other Qt image previews, together with
  `libheif`; missing decoders do not prevent file browsing.

Install system packages through the normal Arch package workflow when needed.
Do not add the Omarchy package repository or run its full desktop installer.
The separate Flea launcher/integration and generated-theme bridge should stay
reproducible in this dotfiles repository; generated state and fetched upstream
source trees should not be committed.
