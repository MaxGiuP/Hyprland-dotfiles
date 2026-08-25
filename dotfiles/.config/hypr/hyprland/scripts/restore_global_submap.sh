#!/usr/bin/env bash

set -euo pipefail

sleep 0.05
hyprctl dispatch 'hl.dsp.submap("global")' >/dev/null
