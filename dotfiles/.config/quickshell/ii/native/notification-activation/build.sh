#!/usr/bin/env bash
set -euo pipefail

readonly source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly cache_root="${XDG_CACHE_HOME:-${HOME}/.cache}/quickshell/native/notification-activation"
readonly build_dir="${cache_root}/build"
readonly install_prefix="${HOME}/.local"
readonly plugin_file="${install_prefix}/lib/qt6/qml/Linmax/NotificationActivation/libnotificationactivationplugin.so"
readonly stamp_file="${cache_root}/fingerprint"
readonly lock_file="${cache_root}/build.lock"
readonly qt_lib_dir="$(pkg-config --variable=libdir Qt6Core)"
readonly wayland_lib_dir="$(pkg-config --variable=libdir wayland-client)"
readonly wayland_protocols_dir="$(pkg-config --variable=pkgdatadir wayland-protocols)"
readonly xdg_activation_xml="${wayland_protocols_dir}/staging/xdg-activation/xdg-activation-v1.xml"

mkdir -p -- "$cache_root"
exec 9>"$lock_file"
flock 9

fingerprint="$({
    sha256sum \
        "$source_dir/CMakeLists.txt" \
        "$source_dir/notificationactivation.cpp" \
        "$source_dir/notificationactivation.hpp" \
        "$source_dir/plugin.cpp" \
        "$source_dir/qmldir"
    pkg-config --modversion Qt6Core Qt6Gui Qt6Qml Qt6Quick Qt6DBus wayland-client wayland-protocols
    stat -Lc '%d:%i:%s:%Y %n' \
        "$qt_lib_dir/libQt6Core.so.6" \
        "$qt_lib_dir/libQt6Gui.so.6" \
        "$qt_lib_dir/libQt6Qml.so.6" \
        "$qt_lib_dir/libQt6Quick.so.6" \
        "$qt_lib_dir/libQt6DBus.so.6" \
        "$wayland_lib_dir/libwayland-client.so.0" \
        "$xdg_activation_xml"
} | sha256sum | awk '{print $1}')"

installed_fingerprint=""
if [[ -r "$stamp_file" ]]; then
    IFS= read -r installed_fingerprint < "$stamp_file" || true
fi

if [[ -f "$plugin_file" && "$installed_fingerprint" == "$fingerprint" ]]; then
    exit 0
fi

cmake -S "$source_dir" -B "$build_dir" -GNinja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$install_prefix"
cmake --build "$build_dir"
cmake --install "$build_dir"

temporary_stamp="${stamp_file}.${BASHPID}"
printf '%s\n' "$fingerprint" > "$temporary_stamp"
mv -f -- "$temporary_stamp" "$stamp_file"
