#!/usr/bin/env bash
# Pinned, non-root Flea installation. Does not claim MIME handlers or portals.
set -euo pipefail
umask 022
readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly source_dir="${HOME:?}/.local/share/flea"
readonly app_root="$HOME/.local/share/omarchy-apps"
readonly destination="$app_root/flea-0.2.0"
readonly commit=b992e76475731041b0c13b50f5cbec3e5c04faa4
readonly toolchain="${FLEA_RUST_TOOLCHAIN:-1.98.0}"
fail() { printf 'Flea installer: %s\n' "$*" >&2; exit 1; }
[[ $# -eq 0 && $EUID -ne 0 ]] || fail 'Run without arguments as your desktop user.'
for command_name in git cargo qs python3 install cp ln diff desktop-file-validate desktop-file-edit update-desktop-database systemctl; do
    command -v "$command_name" >/dev/null || fail "Missing prerequisite: $command_name"
done
[[ -f "$app_root/shell/Commons/qmldir" && -f "$app_root/shell/Ui/qmldir" ]] \
    || fail 'Run install-runtime.sh first.'
[[ -x "$app_root/deps/usr/bin/expect" && -x "$app_root/deps/usr/bin/xdg-terminal-exec" ]] \
    || fail 'Run install-deps.sh first.'
qs_version=$(qs --version 2>/dev/null | sed -nE 's/^[Qq]uickshell ([0-9]+\.[0-9]+\.[0-9]+).*/\1/p')
[[ -n "$qs_version" && "$(printf '%s\n' 0.3.1 "$qs_version" | sort -V | head -1)" == 0.3.1 ]] \
    || fail 'Flea needs a working Quickshell 0.3.1 or newer on PATH.'

if [[ ! -e "$source_dir" && ! -L "$source_dir" ]]; then
    git clone --depth 1 --branch v0.2.0 https://github.com/thisisgm/flea.git "$source_dir"
fi
[[ -d "$source_dir/.git" && ! -L "$source_dir" ]] || fail "Unfamiliar source path: $source_dir"
[[ "$(git -C "$source_dir" rev-parse HEAD)" == "$commit" ]] || fail 'Source revision differs from the reviewed release.'
[[ -z "$(git -C "$source_dir" status --porcelain)" ]] || fail 'Source tree has edits; preserving them, installation stopped.'
# Scoped toolchain selection: never change rustup's global default.
cargo "+$toolchain" build --release --locked --manifest-path "$source_dir/Cargo.toml" --target-dir "$source_dir/target"
[[ "$("$source_dir/target/release/flea" --version)" == 0.2.0 ]] || fail 'Unexpected built version.'

readonly stage="$(mktemp -d "$app_root/.flea-stage.XXXXXXXX")"
cleanup() {
    if [[ "$stage" == "$app_root"/.flea-stage.* && -d "$stage" && ! -L "$stage" ]]; then
        rm -rf -- "$stage"
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$stage/runtime/bin" "$stage/runtime/tools"
install -m755 "$source_dir/target/release/flea" "$stage/runtime/bin/flea"
install -m644 "$source_dir/tools/flea-gio-auth" "$stage/runtime/tools/flea-gio-auth"
install -m644 "$source_dir/LICENSE" "$stage/runtime/LICENSE"
cp -a "$source_dir/ui" "$stage/runtime/ui"
for module in Commons Ui; do
    [[ -L "$stage/runtime/ui/$module" ]] || fail "Expected upstream UI symlink: $module"
    ln -sfn "$app_root/shell/$module" "$stage/runtime/ui/$module"
done
printf 'Flea v0.2.0\nSource: https://github.com/thisisgm/flea\nCommit: %s\n' "$commit" > "$stage/runtime/SOURCE"
if [[ -e "$destination" || -L "$destination" ]]; then
    [[ -d "$destination" && ! -L "$destination" ]] || fail "Unfamiliar runtime path: $destination"
    diff -qr "$stage/runtime" "$destination" >/dev/null || fail 'Existing runtime differs; preserve it before upgrading.'
else
    mv -nT "$stage/runtime" "$destination"
    [[ ! -e "$stage/runtime" ]] || fail 'Runtime destination appeared during installation.'
fi

# Reinstalls are idempotent; an existing differing file is never overwritten.
install_known() {
    local source_file=$1 target_file=$2 mode=$3
    [[ ! -L "$target_file" ]] || fail "Refusing symlink: $target_file"
    if [[ -e "$target_file" ]]; then
        [[ -f "$target_file" ]] && cmp -s "$source_file" "$target_file" \
            || fail "Existing file differs; preserve it before updating: $target_file"
    else
        install -Dm"$mode" "$source_file" "$target_file"
    fi
}
install_known "$script_dir/flea" "$HOME/.local/bin/flea" 755
install_known "$script_dir/flea-gio-auth" "$app_root/bin/flea-gio-auth" 755
install_known "$script_dir/qs-app" "$app_root/bin/qs" 755
install_known "$script_dir/sync-theme.py" "$app_root/bin/sync-theme.py" 755
config_file="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy-apps/theme.toml"
if [[ ! -e "$config_file" && ! -L "$config_file" ]]; then
    install_known "$script_dir/../../dotfiles/.config/omarchy-apps/theme.toml" "$config_file" 644
fi
python3 -B "$app_root/bin/sync-theme.py"

# Absolute Exec works even when an app launcher has not inherited ~/.local/bin.
cp "$source_dir/packaging/com.thisisgm.flea.desktop" "$stage/flea.desktop"
desktop_exec="$HOME/.local/bin/flea"
desktop_exec=${desktop_exec//\\/\\\\}
desktop_exec=${desktop_exec//\"/\\\"}
desktop_exec=${desktop_exec//\`/\\\`}
desktop_exec=${desktop_exec//\$/\\\$}
desktop_exec=${desktop_exec//%/%%}
desktop-file-edit --set-key=Exec --set-value="\"$desktop_exec\" --gui %f" "$stage/flea.desktop"
desktop-file-validate "$stage/flea.desktop"
install_known "$stage/flea.desktop" "$HOME/.local/share/applications/com.thisisgm.flea.desktop" 644
install_known "$source_dir/packaging/com.thisisgm.flea.svg" "$HOME/.local/share/icons/hicolor/scalable/apps/com.thisisgm.flea.svg" 644
update-desktop-database "$HOME/.local/share/applications"
for unit in omarchy-apps-theme-sync.service omarchy-apps-theme-sync.path; do
    install_known "$script_dir/../../dotfiles/.config/systemd/user/$unit" "$HOME/.config/systemd/user/$unit" 644
done
systemctl --user daemon-reload
systemctl --user enable --now omarchy-apps-theme-sync.path
printf 'Installed Flea %s. Open Flea from your launcher, or run flea --gui.\n' "$("$HOME/.local/bin/flea" --version)"
