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

for unit in quickshell.service kdeconnect-bridge.service tv-mode-daemon.service kdeconnect-cursor-sync.service; do
    state="$(systemctl --user is-active "$unit" 2>/dev/null || true)"
    printf 'service\t%s\t%s\n' "$unit" "${state:-unknown}"
done

root_usage="$(df -P / 2>/dev/null | awk 'NR==2 {gsub(/%/, "", $5); print $5}')"
printf 'disk\t%s\n' "${root_usage:-0}"

temperature="$(sensors 2>/dev/null | awk '
    /Package id 0:/ {gsub(/[+°C]/, "", $4); print int($4); exit}
    /Tctl:/ {gsub(/[+°C]/, "", $2); print int($2); exit}
')"
printf 'temperature\t%s\n' "${temperature:-0}"

qml_warnings="$(journalctl --user -u quickshell.service -b -p warning --no-pager 2>/dev/null | wc -l)"
crashes="$(journalctl --user -u quickshell.service -b --no-pager 2>/dev/null | grep -Ec 'SIGSEGV|dumped core|status=11' || true)"
printf 'warnings\t%s\n' "${qml_warnings:-0}"
printf 'crashes\t%s\n' "${crashes:-0}"

profile="$(powerprofilesctl get 2>/dev/null || printf unknown)"
printf 'power\t%s\n' "$profile"
