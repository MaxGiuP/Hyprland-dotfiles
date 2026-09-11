#!/usr/bin/env bash
set -euo pipefail

# The installed copy named expect is a launcher for the unmodified, signed binary.
# Use the loader's private search path instead of changing LD_LIBRARY_PATH.
if [[ ${0##*/} == expect ]]; then
    deps_dir="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
    exec /lib64/ld-linux-x86-64.so.2 \
        --library-path "$deps_dir/usr/lib/expect5.45.4" \
        "$deps_dir/usr/libexec/expect" "$@"
fi

[[ $EUID -ne 0 ]] || { echo 'Run as your desktop user, without sudo.' >&2; exit 1; }
[[ $(uname -m) == x86_64 ]] || { echo 'These dependency packages require x86_64.' >&2; exit 1; }
for dependency in curl gpg gpgv bsdtar sha256sum awk ldd flock install; do
    command -v "$dependency" >/dev/null || { echo "Missing installer tool: $dependency" >&2; exit 1; }
done
[[ -x /lib64/ld-linux-x86-64.so.2 ]] || { echo 'The glibc x86_64 loader is required.' >&2; exit 1; }

# Match the Flea launcher/runtime's fixed compatibility prefix.
apps_dir="${HOME:?}/.local/share/omarchy-apps"
deps_dir="$apps_dir/deps"
installer="$(readlink -f -- "${BASH_SOURCE[0]}")"
mkdir -p -- "$apps_dir"
exec 9>"$apps_dir/.deps-install.lock"
flock -n 9 || { echo 'Another dependency installation is running.' >&2; exit 1; }
if [[ -e "$deps_dir" || -L "$deps_dir" ]]; then
    [[ ! -L "$deps_dir" && -f "$deps_dir/.omarchy-apps-deps-v1" ]] || {
        echo "Refusing to replace an unmanaged dependency directory: $deps_dir" >&2
        exit 1
    }
fi

# Keep audit records and any previous installation recoverable here.
work_dir="$(mktemp -d "$apps_dir/.deps-install.XXXXXXXX")"
payload="$work_dir/runtime"
mkdir -m 700 -- "$work_dir/gnupg"
mkdir -p -- "$payload/usr/libexec" "$payload/usr/lib/qt6/plugins-disabled/imageformats"
trap 'echo "Dependency audit directory: $work_dir" >&2' EXIT

for keyring in archlinux chaotic; do
    [[ -r /usr/share/pacman/keyrings/$keyring.gpg ]] || {
        echo "Missing installed public keyring: $keyring" >&2; exit 1;
    }
    # Arch's distributed .gpg files are ASCII armored, so gpgv needs dearmored copies.
    gpg --batch --no-options --homedir "$work_dir/gnupg" \
        --output "$work_dir/$keyring.gpg" --dearmor "/usr/share/pacman/keyrings/$keyring.gpg"
done

fetch_verified() {
    local package=$1 url=$2 checksum=$3 keyring=$4 signer=$5
    local archive="$work_dir/$package"
    curl --fail --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
        --retry 2 --connect-timeout 15 --max-time 120 --silent --show-error \
        --output "$archive" "$url/$package"
    curl --fail --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
        --retry 2 --connect-timeout 15 --max-time 120 --silent --show-error \
        --output "$archive.sig" "$url/$package.sig"
    printf '%s  %s\n' "$checksum" "$archive" | sha256sum --check --status
    gpgv --homedir "$work_dir/gnupg" --keyring "$work_dir/$keyring.gpg" \
        --status-fd 3 "$archive.sig" "$archive" 3>"$archive.verification"
    awk -v signer="$signer" '$1 == "[GNUPG:]" && $2 == "VALIDSIG" && $3 == signer { valid=1 } END { exit !valid }' \
        "$archive.verification"
    printf '%s  %s\n' "$checksum" "$package" >>"$payload/.omarchy-apps-deps-v1"
}

expect_package=expect-5.45.4-5-x86_64.pkg.tar.zst
images_package=kimageformats-6.29.0-1-x86_64.pkg.tar.zst
terminal_package=xdg-terminal-exec-git-0.14.3.r0.g065925d-1-any.pkg.tar.zst
fetch_verified "$expect_package" https://archive.archlinux.org/packages/e/expect \
    466f6dd635c3ae515f3b0dfb15f6486aa79308da11da1872bb4ac761b40c886b \
    archlinux E499C79F53C96A54E572FEE1C06086337C50773E
fetch_verified "$images_package" https://archive.archlinux.org/packages/k/kimageformats \
    a1b8c82f8ce7707c7b9a485984bf7d64fa748a22e87d9718b8f42f1dc17f66a9 \
    archlinux 1519D5ABA65BF6FC2B73C7567A4E76095D8A52E4
fetch_verified "$terminal_package" https://geo-mirror.chaotic.cx/chaotic-aur/x86_64 \
    ce3abc3edfe5bd3df259d8d4f4600581057cb3d3597a395a711d974c6734e0ae \
    chaotic 42FE8BA5A050BED98873B256349BC7808577C592

# Extract only reviewed runtime paths. Never run package installation scripts.
bsdtar -xf "$work_dir/$expect_package" -C "$payload" --no-same-owner \
    usr/bin/expect usr/lib/expect5.45.4 usr/share/licenses/expect
bsdtar -xf "$work_dir/$images_package" -C "$payload" --no-same-owner \
    usr/lib/qt6/plugins/imageformats
bsdtar -xf "$work_dir/$terminal_package" -C "$payload" --no-same-owner \
    usr/bin/xdg-terminal-exec usr/share/xdg-terminal-exec

mv -- "$payload/usr/bin/expect" "$payload/usr/libexec/expect"
install -m 755 -- "$installer" "$payload/usr/bin/expect"
"$payload/usr/bin/expect" -c 'spawn /usr/bin/printf dependency-ok; expect dependency-ok; expect eof; puts "\nExpect runtime passed"'
"$payload/usr/bin/xdg-terminal-exec" --help >/dev/null

# Qt discovers all plugins in this folder. Keep optional formats with missing
# system libraries outside its search path rather than producing loader errors.
for plugin in "$payload"/usr/lib/qt6/plugins/imageformats/*.so; do
    missing="$(ldd "$plugin" | awk '/not found/')"
    if [[ -n "$missing" ]]; then
        [[ ${plugin##*/} != kimg_heif.so ]] || {
            printf 'HEIF decoder has missing dependencies:\n%s\n' "$missing" >&2; exit 1;
        }
        printf 'Optional decoder disabled: %s\n%s\n' "${plugin##*/}" "$missing"
        mv -- "$plugin" "$payload/usr/lib/qt6/plugins-disabled/imageformats/"
    fi
done

if [[ -d "$deps_dir" ]]; then
    mv -- "$deps_dir" "$work_dir/previous"
fi
if ! mv -- "$payload" "$deps_dir"; then
    [[ ! -d "$work_dir/previous" ]] || mv -- "$work_dir/previous" "$deps_dir"
    exit 1
fi
printf 'Installed verified runtime dependencies in %s\n' "$deps_dir"
printf 'Use PATH=%s/usr/bin:$PATH and QT_PLUGIN_PATH=%s/usr/lib/qt6/plugins in the Flea launcher.\n' "$deps_dir" "$deps_dir"
printf 'Append %s/usr/share to XDG_DATA_DIRS for the terminal launcher fallback list.\n' "$deps_dir"
