# User-local Flea dependencies

Run `./tools/omarchy-apps/install-deps.sh` on Arch x86_64 with the installed Arch and Chaotic public keyrings. It installs pinned Expect 5.45.4-5, KImageFormats 6.29.0-1, and xdg-terminal-exec 0.14.3 under `~/.local/share/omarchy-apps/deps`, matching the launcher's fixed prefix. SHA-256 checks, package signatures, and signer fingerprints are required before extraction. It does not run package hooks, use sudo, or change default applications.

The Flea launcher should add `deps/usr/bin` to `PATH`, `deps/usr/lib/qt6/plugins` to `QT_PLUGIN_PATH`, and `deps/usr/share` to `XDG_DATA_DIRS`. The Expect launcher uses the glibc loader with a private library path, so no `LD_LIBRARY_PATH` export is necessary. Existing user terminal preferences take priority over the shipped fallback terminal list.

On this machine, Expect successfully spawned and matched a subprocess using Tcl 8.6.16. Qt 6.11.2 loaded the HEIC decoder and completed a HEIC encode/decode round trip using libheif 1.23.2. The optional JPEG-XR plugin is kept outside Qt's search path because the system does not have `libjxrglue.so.0`; the remaining plugin dependencies resolved. xdg-terminal-exec's print-only check selected the existing GNOME Terminal entry without launching it or changing defaults.

Each installation leaves verified archives and signature records in a printed `.deps-install.*` audit directory next to `deps`. A replacement retains the old managed installation there as `previous`. Only directories bearing the installer's marker are replaced; unrelated directories are refused.
