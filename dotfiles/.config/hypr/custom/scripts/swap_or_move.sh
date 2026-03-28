#!/usr/bin/env bash
# Usage: swap_or_move.sh <l|r|u|d>
#
# 1 window on workspace:            send to target monitor's active workspace
# 2 windows, window in direction:   swapwindow (swap, preserve split)
# 2 windows, perpendicular window:  movewindow (reorient split)
# 2 windows, same-axis at edge:     send to target monitor's active workspace
# 3+ windows, window in direction:  swapwindow (swap)
# 3+ windows, at any edge:          send to target monitor's active workspace,
#                                   else movewindow (become full-height edge window)

dir="${1:-}"
case "$dir" in l|r|u|d) ;; *) exit 1 ;; esac
command -v jq >/dev/null || { echo "Please install jq"; exit 1; }

find_target_monitor() {
    local monitors="$1"
    local mcx="$2"
    local mcy="$3"

    echo "$monitors" | jq -r \
      --arg d "$dir" --argjson cx "$mcx" --argjson cy "$mcy" \
      '[.[] | select(.focused == false) |
        . + {mcx: (.x + (.width/2|floor)), mcy: (.y + (.height/2|floor))} |
        select(
          ($d == "l" and .mcx < $cx) or ($d == "r" and .mcx > $cx) or
          ($d == "u" and .mcy < $cy) or ($d == "d" and .mcy > $cy)
        ) |
        . + {dist: ((.mcx - $cx) * (.mcx - $cx) + (.mcy - $cy) * (.mcy - $cy))}
      ] | sort_by(.dist) | .[0].name // ""'
}

cross_monitor_move() {
    local active_json="$1"
    local aaddr_local
    local monitors
    local mcx
    local mcy
    local target_mon
    local target_ws
    local floating
    local fullscreen
    local xwayland
    local moved_window
    local target_cx
    local target_cy

    aaddr_local=$(echo "$active_json" | jq -r '.address')
    monitors=$(hyprctl -j monitors 2>/dev/null) || return 1
    mcx=$(echo "$monitors" | jq 'map(select(.focused)) | .[0] | .x + (.width / 2 | floor)')
    mcy=$(echo "$monitors" | jq 'map(select(.focused)) | .[0] | .y + (.height / 2 | floor)')
    target_mon=$(find_target_monitor "$monitors" "$mcx" "$mcy")
    [ -n "$target_mon" ] || return 1

    floating=$(echo "$active_json" | jq -r '.floating')
    fullscreen=$(echo "$active_json" | jq -r '.fullscreen')
    xwayland=$(echo "$active_json" | jq -r '.xwayland')

    if [ "$floating" = "true" ]; then
        hyprctl dispatch movewindow "mon:$target_mon"
        return 0
    fi

    # Cross-monitor tiled moves are routed through the target monitor's active
    # workspace instead of movewindow mon:<name>. That avoids compositor crashes
    # seen with fullscreen/XWayland games such as Portal 2.
    target_ws=$(echo "$monitors" | jq -r --arg mon "$target_mon" '.[] | select(.name == $mon) | .activeWorkspace.id')
    [ -n "$target_ws" ] && [ "$target_ws" != "null" ] || return 1

    hyprctl dispatch movetoworkspacesilent "$target_ws"
    moved_window=$(hyprctl -j clients 2>/dev/null | jq -r --arg aaddr "$aaddr_local" '.[] | select(.address == $aaddr)')
    target_cx=$(echo "$moved_window" | jq -r '.at[0] + (.size[0] / 2 | floor)')
    target_cy=$(echo "$moved_window" | jq -r '.at[1] + (.size[1] / 2 | floor)')
    if [ "$target_cx" != "null" ] && [ "$target_cy" != "null" ]; then
        hyprctl dispatch movecursor "$target_cx $target_cy" >/dev/null 2>&1 || true
    fi

    if [ "$fullscreen" != "0" ] || [ "$xwayland" = "true" ]; then
        hyprctl dispatch focusmonitor "$target_mon" >/dev/null 2>&1 || true
    fi
}

active=$(hyprctl -j activewindow 2>/dev/null) || exit 0
[ "$(echo "$active" | jq -r '.address')" != "null" ] || exit 0

aaddr=$(echo "$active" | jq -r '.address')
ax=$(echo "$active" | jq '.at[0] + (.size[0] / 2 | floor)')
ay=$(echo "$active" | jq '.at[1] + (.size[1] / 2 | floor)')
aws=$(echo "$active" | jq '.workspace.id')
floating=$(echo "$active" | jq '.floating')

# Floating windows: just move to nearest monitor in that direction if one exists
if [ "$floating" = "true" ]; then
    cross_monitor_move "$active" >/dev/null 2>&1 || true
    exit 0
fi

clients=$(hyprctl -j clients 2>/dev/null)

action=$(echo "$clients" | jq -r \
  --arg d "$dir" --arg aaddr "$aaddr" --argjson ax "$ax" --argjson ay "$ay" --argjson ws "$aws" '
  [.[] | select(.address != $aaddr and .workspace.id == $ws and .floating == false)] |
  if length == 0 then "edge"
  else . as $others |
    ($others | any(
      (.at[0] + (.size[0]/2|floor)) as $ocx |
      (.at[1] + (.size[1]/2|floor)) as $ocy |
      ($d == "l" and $ocx < $ax) or ($d == "r" and $ocx > $ax) or
      ($d == "u" and $ocy < $ay) or ($d == "d" and $ocy > $ay)
    )) as $in_dir |
    if $in_dir then "swap"
    elif ($others | length) == 1 then
      ($others | any(
        (.at[0] + (.size[0]/2|floor)) as $ocx |
        (.at[1] + (.size[1]/2|floor)) as $ocy |
        (($ocx - $ax) * ($ocx - $ax)) as $dx2 |
        (($ocy - $ay) * ($ocy - $ay)) as $dy2 |
        (($d == "l" or $d == "r") and $dy2 > $dx2) or
        (($d == "u" or $d == "d") and $dx2 > $dy2)
      )) as $has_perp |
      if $has_perp then "reorient" else "edge" end
    else "edge"
    end
  end
')

case "$action" in
  swap)    hyprctl dispatch swapwindow "$dir" ;;
  reorient) hyprctl dispatch movewindow "$dir" ;;
  edge)
    if ! cross_monitor_move "$active"; then
      # No monitor in that direction: make full-height edge window (3+ windows only)
      other_count=$(echo "$clients" | jq \
        --arg aaddr "$aaddr" --argjson ws "$aws" \
        '[.[] | select(.address != $aaddr and .workspace.id == $ws and .floating == false)] | length')
      [ "$other_count" -ge 2 ] && hyprctl dispatch movewindow "$dir"
    fi
    ;;
esac
