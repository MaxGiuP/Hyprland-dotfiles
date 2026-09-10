#!/usr/bin/env bash

set -euo pipefail

# Compatibility helper. Combined Sound is created natively by
# ~/.config/pipewire/pipewire.conf.d/50-combined-stereo.conf; this script only
# waits for that node and selects it without restarting the audio stack.
sink_name="CombinedStereo"
attempts="${COMBINED_AUDIO_WAIT_ATTEMPTS:-50}"
delay="${COMBINED_AUDIO_WAIT_DELAY:-0.2}"

for ((attempt = 1; attempt <= attempts; attempt++)); do
    if pactl list short sinks 2>/dev/null | awk -v sink="$sink_name" '$2 == sink { found = 1 } END { exit !found }'; then
        pactl set-default-sink "$sink_name"
        printf 'Combined Sound is ready (%s).\n' "$sink_name"
        exit 0
    fi
    sleep "$delay"
done

printf 'Combined Sound did not appear; restart pipewire.service and inspect its journal.\n' >&2
exit 1
