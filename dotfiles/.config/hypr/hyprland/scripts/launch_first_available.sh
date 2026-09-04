#!/usr/bin/env bash
for cmd in "$@"; do
    [[ -z "$cmd" ]] && continue
    executable=${cmd%%[[:space:]]*}
    command -v -- "$executable" >/dev/null 2>&1 || continue
    exec bash -c "$cmd"
done
exit 127
