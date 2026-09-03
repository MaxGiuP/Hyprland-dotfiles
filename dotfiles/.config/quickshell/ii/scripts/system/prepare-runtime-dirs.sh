#!/usr/bin/env bash
set -euo pipefail

umask 077

readonly runtime_root="/tmp/quickshell"
readonly media_root="${runtime_root}/media"
readonly image_dir="${media_root}/images"
readonly cliphist_dir="${media_root}/cliphist"
readonly owner_uid="$(id -u)"
readonly session_runtime_dir="${XDG_RUNTIME_DIR:-/run/user/${owner_uid}}"
readonly quickshell_registry="${session_runtime_dir%/}/quickshell"

die() {
    printf 'prepare-runtime-dirs: %s\n' "$*" >&2
    exit 1
}

assert_allowed_path() {
    case "$1" in
        "$runtime_root"|"$media_root"|"$image_dir"|"$cliphist_dir") ;;
        *) die "refusing unexpected path: $1" ;;
    esac
}

assert_safe_directory() {
    local path="$1"
    local resolved owner

    assert_allowed_path "$path"
    [[ ! -L "$path" ]] || die "refusing symlink: $path"
    [[ -d "$path" ]] || die "not a directory: $path"

    owner="$(stat -c '%u' -- "$path")"
    [[ "$owner" == "$owner_uid" ]] || die "directory is not owned by uid ${owner_uid}: $path"

    resolved="$(realpath -e -- "$path")"
    [[ "$resolved" == "$path" ]] || die "directory resolves outside its exact path: $path -> $resolved"
}

ensure_safe_directory() {
    local path="$1"
    local parent="$2"

    assert_allowed_path "$path"
    if [[ "$parent" == "/tmp" ]]; then
        [[ ! -L /tmp && -d /tmp ]] || die "unsafe /tmp root"
        [[ "$(realpath -e -- /tmp)" == "/tmp" ]] || die "/tmp does not resolve to itself"
    else
        assert_safe_directory "$parent"
    fi

    if [[ -e "$path" || -L "$path" ]]; then
        assert_safe_directory "$path"
    else
        mkdir -- "$path"
        assert_safe_directory "$path"
    fi

    chmod 0700 -- "$path"
}

clear_ephemeral_directory() {
    local path="$1"

    case "$path" in
        "$image_dir"|"$cliphist_dir") ;;
        *) die "refusing to clear non-ephemeral path: $path" ;;
    esac

    assert_safe_directory "$path"
    find -P "$path" -xdev -mindepth 1 -delete
}

clear_stale_quickshell_registry() {
    local resolved owner

    [[ -e "$quickshell_registry" || -L "$quickshell_registry" ]] || return 0
    [[ ! -L "$quickshell_registry" && -d "$quickshell_registry" ]] \
        || die "unsafe Quickshell runtime registry: $quickshell_registry"
    [[ "$(basename -- "$quickshell_registry")" == "quickshell" ]] \
        || die "refusing unexpected runtime registry: $quickshell_registry"

    owner="$(stat -c '%u' -- "$quickshell_registry")"
    [[ "$owner" == "$owner_uid" ]] \
        || die "runtime registry is not owned by uid ${owner_uid}: $quickshell_registry"
    resolved="$(realpath -e -- "$quickshell_registry")"
    [[ "$resolved" == "$quickshell_registry" ]] \
        || die "runtime registry resolves outside its exact path: $quickshell_registry -> $resolved"

    # This service may coexist with a separately launched settings/test shell.
    # Only clear the registry when no Quickshell process for this user exists.
    command -v pgrep >/dev/null 2>&1 || return 0
    if pgrep -u "$owner_uid" -x quickshell >/dev/null 2>&1; then
        return 0
    fi
    find -P "$quickshell_registry" -xdev -mindepth 1 -delete
}

clear_stale_quickshell_registry

ensure_safe_directory "$runtime_root" /tmp
ensure_safe_directory "$media_root" "$runtime_root"
ensure_safe_directory "$image_dir" "$media_root"
ensure_safe_directory "$cliphist_dir" "$media_root"

clear_ephemeral_directory "$image_dir"
clear_ephemeral_directory "$cliphist_dir"
