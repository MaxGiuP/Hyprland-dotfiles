#!/usr/bin/env bash
# Restore the additional wallpapers without replacing existing files.
set -euo pipefail

download() {
    local period="$1" name="$2" id="$3" expected="$4"
    local destination="$HOME/Pictures/Wallpapers/dynamic-system/$period/$name"
    local temporary
    if [[ -e "$destination" ]]; then
        echo "Keeping existing: $destination"
        return
    fi
    mkdir -p "$(dirname "$destination")"
    temporary=$(mktemp "${destination}.download.XXXXXX")
    if ! curl --fail --location --silent --show-error --max-time 120 \
        "https://w.wallhaven.cc/full/${id:0:2}/wallhaven-$id.${name##*.}" -o "$temporary"; then
        echo "Download failed; partial file: $temporary" >&2
        return 1
    fi
    if [[ "$(sha256sum "$temporary" | cut -d ' ' -f 1)" != "$expected" ]]; then
        echo "Checksum mismatch; inspect: $temporary" >&2
        return 1
    fi
    chmod 644 "$temporary"
    mv -n "$temporary" "$destination"
    echo "Added: $destination"
}

download morning morning-layered-mist-21ooly.jpg 21ooly 6fded3fde9a9b46af1e0521ead2b1b9558d2fb55aa578cd9dbe5b6da03514a29
download morning morning-ocean-sunrise-mdekp9.jpg mdekp9 bd0e207eca9f1baad124cf53d5cc19b3bde8497856215dfa0738ff3f0f7bf597
download day day-clouds-sailboat-gwqqp3.jpg gwqqp3 405f50c772b08ab70ee77ecd04ea25a9021dcc35aaf3aecebcd43db2916d751d
download day day-cloud-tower-d8w8og.png d8w8og 9d80e0fe2c1ed9b47b8b2fef881d33402408d6c9353a987024bafd4861137bb6
download evening evening-twilight-worlds-og1eql.png og1eql 218a297137caa47688858b89e1f6e6f6cfc1673f19e706699aa5b74ef86e04a0
download evening evening-ember-sun-xe61ql.jpg xe61ql f743ec3d3ebbb3ddd38812728947ef25f59caf61c64dba4f299e840ee12b5e7b
download night night-lit-windows-6ldqp7.jpg 6ldqp7 11f6318f271b25bcf377d49f66c40ff10e450adae0f0550aab5d1176ccff53ab
download night night-blue-solitude-jedwzp.jpg jedwzp cd17c3491f8050274f4f15bc569e5e2d1396e4cae18a537cc827089dbc1d7b73
