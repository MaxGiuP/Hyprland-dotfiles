#!/usr/bin/env bash

# Dedicated TV special workspace on the HDMI 2 output.
TV_SPECIAL_WORKSPACE_NAME=tv

# Keep this strict so the TV flow does not accidentally hijack HDMI-A-1.
TV_MONITOR_CANDIDATES=(
    HDMI-A-2
    HDMI-2
    HDMI2
)

TV_CHROME_BIN="/usr/bin/google-chrome-stable"
TV_CHROME_PROFILE_DIR="TV"
TV_YOUTUBE_TV_UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64; Xbox; Xbox One) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/46.0.2486.0 Safari/537.36 Edge/13.10586"

# PipeWire/Pulse sink for the TV output. In Pro Audio mode this sink reports
# node.nick/alsa.name as "HDTV".
TV_AUDIO_SINK_NAME="alsa_output.pci-0000_00_1f.3.pro-output-3"
TV_AUDIO_SINK_NICK="HDTV"

TV_WEB_URL="https://www.google.com/"
TV_YOUTUBE_URL="https://www.youtube.com/"
TV_NETFLIX_URL="https://www.netflix.com/browse"
TV_RUMBLE_URL="https://rumble.com/"
