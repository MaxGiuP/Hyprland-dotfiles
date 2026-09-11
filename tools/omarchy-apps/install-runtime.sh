#!/usr/bin/env bash
# Install only the shared QML runtime; never run the Omarchy desktop installer.
set -euo pipefail
umask 022

readonly commit=31bd80daa4613ffdee995ac27467fce5a2990806
readonly digest=3947abe35f877dddeb88b7189954fc7102bb3f46aae0de91a5e952f852b667c6
readonly source_url="https://codeload.github.com/omacom/omarchy/tar.gz/$commit"
readonly install_root="${HOME:?HOME must be set}/.local/share/omarchy-apps"
readonly destination="$install_root/shell"

fail() { printf 'Omarchy QML runtime: %s\n' "$*" >&2; exit 1; }
[[ $# -eq 0 ]] || fail 'This installer takes no arguments.'
[[ $EUID -ne 0 ]] || fail 'Run as your desktop user, without sudo.'
for tool in curl tar sha256sum mktemp diff find cp mv; do
    command -v "$tool" >/dev/null || fail "Missing prerequisite: $tool"
done
[[ ! -L "$install_root" ]] || fail "Refusing symlink installation root: $install_root"
[[ ! -e "$install_root" || -d "$install_root" ]] || fail "Not a directory: $install_root"
mkdir -p -- "$install_root"
readonly stage="$(mktemp -d "$install_root/.runtime-stage.XXXXXXXX")"
cleanup() {
    # Only this invocation's newly created staging directory is disposable.
    if [[ "$stage" == "$install_root"/.runtime-stage.* && -d "$stage" && ! -L "$stage" ]]; then
        rm -rf -- "$stage"
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

printf 'Fetching pinned Omarchy QML sources (%s)…\n' "$commit"
curl --fail --location --proto '=https' --proto-redir '=https' \
    --retry 2 --connect-timeout 15 --max-time 180 \
    --output "$stage/source.tar.gz" "$source_url"
printf '%s  %s\n' "$digest" "$stage/source.tar.gz" | sha256sum --check --status \
    || fail 'Archive digest mismatch; nothing was installed.'

mkdir -- "$stage/extract" "$stage/shell"
tar --extract --gzip --file "$stage/source.tar.gz" --directory "$stage/extract" \
    --no-same-owner --no-same-permissions \
    "omarchy-$commit/shell/Commons" "omarchy-$commit/shell/Ui" "omarchy-$commit/LICENSE"
readonly extracted="$stage/extract/omarchy-$commit"
[[ -z "$(find "$extracted" -type l -print -quit)" ]] \
    || fail 'Unexpected source symlink; nothing was installed.'
cp -R -- "$extracted/shell/Commons" "$extracted/shell/Ui" "$stage/shell/"
cp -- "$extracted/LICENSE" "$stage/shell/LICENSE.omarchy"
printf 'Source: %s\nCommit: %s\nArchive-SHA256: %s\n' \
    "$source_url" "$commit" "$digest" > "$stage/shell/SOURCE"
[[ -s "$stage/shell/Commons/qmldir" && -s "$stage/shell/Ui/qmldir" ]] \
    || fail 'Required QML module metadata is missing.'

if [[ -e "$destination" || -L "$destination" ]]; then
    [[ -d "$destination" && ! -L "$destination" ]] \
        || fail "Refusing to replace existing path: $destination"
    [[ -z "$(find "$destination" -type l -print -quit)" ]] \
        || fail "Existing runtime contains symlinks; preserve and inspect it first: $destination"
    diff --brief --recursive "$stage/shell" "$destination" >/dev/null \
        || fail "Existing runtime differs; preserve it elsewhere before reinstalling: $destination"
    printf 'Pinned QML runtime already installed and unchanged: %s\n' "$destination"
    exit 0
fi

# Same-filesystem staging gives an atomic rename; never clobber a raced-in path.
mv --no-clobber --no-target-directory -- "$stage/shell" "$destination"
[[ ! -e "$stage/shell" ]] || fail "Destination appeared during installation: $destination"
printf 'Installed Commons and Ui at %s\n' "$destination"
printf 'No desktop settings, services, package repositories, or application defaults changed.\n'
