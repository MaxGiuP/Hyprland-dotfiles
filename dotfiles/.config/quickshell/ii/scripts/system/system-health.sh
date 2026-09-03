#!/usr/bin/env bash
set -u

action="${1:-snapshot}"

if [[ "$action" == "restart-bridges" ]]; then
    systemctl --user restart kdeconnect-bridge.service tv-mode-daemon.service kdeconnect-cursor-sync.service
    exit $?
fi

if [[ "$action" == "open-logs" ]]; then
    exec kitty --class QSHealth --title "Quickshell Health Logs" \
        journalctl --user -u quickshell.service -b -f
fi

services=(
    quickshell.service
    kdeconnect-bridge.service
    tv-mode-daemon.service
    kdeconnect-cursor-sync.service
)
declare -A service_states=()
for unit in "${services[@]}"; do
    service_states["$unit"]="unknown"
done

while IFS=$'\t' read -r unit state; do
    [ -n "$unit" ] || continue
    service_states["$unit"]="${state:-unknown}"
done < <(
    systemctl --user show "${services[@]}" --property=Id,ActiveState --no-pager 2>/dev/null \
        | awk -F= '
            function emit() {
                if (id != "")
                    print id "\t" (state != "" ? state : "unknown")
                id = ""
                state = ""
            }
            $1 == "Id" { id = substr($0, 4); next }
            $1 == "ActiveState" { state = substr($0, 13); next }
            NF == 0 { emit() }
            END { emit() }
        '
)

for unit in "${services[@]}"; do
    printf 'service\t%s\t%s\n' "$unit" "${service_states[$unit]}"
done

root_usage="$(df -P / 2>/dev/null | awk 'NR==2 {gsub(/%/, "", $5); print $5}')"
printf 'disk\t%s\n' "${root_usage:-0}"

temperature="$(sensors 2>/dev/null | awk '
    /Package id 0:/ {gsub(/[+°C]/, "", $4); print int($4); exit}
    /Tctl:/ {gsub(/[+°C]/, "", $2); print int($2); exit}
')"
printf 'temperature\t%s\n' "${temperature:-0}"

read -r qml_warnings crashes < <(
    journalctl --user -u quickshell.service -b -p warning --no-pager --quiet 2>/dev/null \
        | awk 'BEGIN { warnings=0; crashes=0 } { warnings++ } /SIGSEGV|dumped core|status=11/ { crashes++ } END { print warnings, crashes }'
)
printf 'warnings\t%s\n' "${qml_warnings:-0}"
printf 'crashes\t%s\n' "${crashes:-0}"

profile="$(powerprofilesctl get 2>/dev/null || printf unknown)"
printf 'power\t%s\n' "$profile"
printf 'complete\t1\n'
