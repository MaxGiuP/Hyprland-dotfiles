#!/usr/bin/env bash
# lock.sh — animated session lock
#
# Lock:   active workspace slides UP off the top of the monitor,
#         then hyprlock opens (padlock rises as usual).
# Unlock: original workspace descends from above (windows from the top),
#         matching the existing unlock feel.

# Guard: bail if hyprlock is already running
pidof -x hyprlock &>/dev/null && exit 0

# ── Record state ────────────────────────────────────────────────────────
CURRENT=$(hyprctl activeworkspace -j | jq -r '.id')
TEMP=9999   # scratch workspace — well outside the normal 1-10 range

# ── Pre-lock: slide workspace off the TOP of the screen ─────────────────
# "slide bottom" = new workspace rises from below, current exits upward.
# Duration 0.35 s; we sleep 0.40 s to let it fully clear the monitor.
hyprctl keyword animation "workspaces,1,0.35,emphasizedAccel,slide bottom"
hyprctl dispatch workspace "$TEMP"
sleep 0.40

# ── Lock ────────────────────────────────────────────────────────────────
# Notify quickshell overlay (if present), then start hyprlock.
hyprctl dispatch global quickshell:lock 2>/dev/null || true
hyprlock

# ── Post-unlock: bring workspace back down from above ───────────────────
# "slide top" = original workspace descends from the top of the screen.
# This mirrors the pre-lock motion and preserves the existing unlock feel.
hyprctl keyword animation "workspaces,1,0.45,emphasizedDecel,slide top"
hyprctl dispatch workspace "$CURRENT"

# Restore the original workspace animation once the transition finishes.
sleep 0.50
hyprctl keyword animation "workspaces,1,7,menu_decel,slide"
