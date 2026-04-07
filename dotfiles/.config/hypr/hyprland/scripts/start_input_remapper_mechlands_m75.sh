#!/usr/bin/env sh

set -eu

# Delay startup slightly so the session bus and input-remapper daemon are ready.
sleep 3

input-remapper-control \
  --command start \
  --device '       MECHLANDS M75' \
  --preset 'Right Control' >/dev/null 2>&1 &
