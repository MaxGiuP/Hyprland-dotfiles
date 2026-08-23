#!/usr/bin/env sh

set -eu

loaded_version=""
installed_version=""

if [ -r /proc/driver/nvidia/version ]; then
  loaded_version=$(awk '
    /^NVRM version:/ {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^[0-9]+[.][0-9]+[.][0-9]+$/) {
          print $i
          exit
        }
      }
    }
  ' /proc/driver/nvidia/version)
fi

if command -v pacman >/dev/null 2>&1; then
  installed_version=$(pacman -Q nvidia-utils 2>/dev/null | awk '{ print $2 }' | sed 's/-.*//' || true)
fi

if [ -n "$loaded_version" ] && [ -n "$installed_version" ] && [ "$loaded_version" != "$installed_version" ]; then
  printf 'The loaded NVIDIA driver is %s, but the installed libraries are %s. Reboot once to load the updated driver, then Steam will launch normally.\n' \
    "$loaded_version" "$installed_version" >&2
  exit 1
fi

exit 0
