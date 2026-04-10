#!/usr/bin/env bash
set -euo pipefail

export LANG=C
export LC_ALL=C

sanitize() {
    local value="${1-}"
    value="${value//$'\t'/ }"
    value="${value//$'\r'/ }"
    value="${value//$'\n'/ }"
    printf '%s' "$value"
}

unescape_nm() {
    local value="${1-}"
    printf '%s' "${value//\\:/:}"
}

emit_card() {
    local dev="$1"
    local query_dev
    local type state connection hwaddr ip gateway dns

    query_dev="$(unescape_nm "$dev")"
    type="$(nmcli -g GENERAL.TYPE device show "$query_dev" 2>/dev/null | head -1 || true)"
    state="$(nmcli -g GENERAL.STATE device show "$query_dev" 2>/dev/null | head -1 || true)"
    connection="$(nmcli -g GENERAL.CONNECTION device show "$query_dev" 2>/dev/null | head -1 || true)"
    hwaddr="$(nmcli -g GENERAL.HWADDR device show "$query_dev" 2>/dev/null | head -1 || true)"
    ip="$(nmcli -g IP4.ADDRESS device show "$query_dev" 2>/dev/null | head -1 || true)"
    ip="${ip%%/*}"
    gateway="$(nmcli -g IP4.GATEWAY device show "$query_dev" 2>/dev/null | head -1 || true)"
    dns="$(nmcli -g IP4.DNS device show "$query_dev" 2>/dev/null | paste -sd ', ' - || true)"

    printf 'CARD\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$(sanitize "$(unescape_nm "$dev")")" \
        "$(sanitize "$type")" \
        "$(sanitize "$state")" \
        "$(sanitize "$connection")" \
        "$(sanitize "$(unescape_nm "$hwaddr")")" \
        "$(sanitize "$ip")" \
        "$(sanitize "$gateway")" \
        "$(sanitize "$dns")"
}

emit_wifi_record() {
    local in_use="${1-}"
    local signal="${2-}"
    local freq="${3-}"
    local ssid="${4-}"
    local bssid="${5-}"
    local security="${6-}"
    local device="${7-}"

    [[ -z "$device" ]] && return
    [[ "$ssid" == "--" ]] && ssid=""
    [[ "$security" == "--" ]] && security=""
    [[ -z "$ssid" ]] && return

    printf 'WIFI\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$(sanitize "$ssid")" \
        "$(sanitize "$bssid")" \
        "$(sanitize "$device")" \
        "$(sanitize "$signal")" \
        "$(sanitize "${freq%% MHz*}")" \
        "$(sanitize "$security")" \
        "$([[ "$in_use" == "*" ]] && printf '1' || printf '0')"
}

emit_profile() {
    local uuid="$1"
    local name="$2"
    local type="$3"
    local device="$4"
    local ifname autoconnect

    [[ -z "$uuid" ]] && return
    [[ "$device" == "--" ]] && device=""

    ifname="$(nmcli -g connection.interface-name connection show uuid "$uuid" 2>/dev/null | head -1 || true)"
    autoconnect="$(nmcli -g connection.autoconnect connection show uuid "$uuid" 2>/dev/null | head -1 || true)"

    printf 'PROFILE\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$(sanitize "$uuid")" \
        "$(sanitize "$name")" \
        "$(sanitize "$type")" \
        "$(sanitize "$device")" \
        "$(sanitize "$ifname")" \
        "$(sanitize "$autoconnect")"
}

snapshot() {
    local wifi_state
    wifi_state="$(nmcli radio wifi 2>/dev/null | head -1 | tr '[:upper:]' '[:lower:]' || true)"
    printf 'RADIO\twifi\t%s\n' "$([[ "$wifi_state" == "enabled" ]] && printf '1' || printf '0')"

    local radio_state wifi_radio wwan_radio
    radio_state="$(nmcli -t -f WIFI,WWAN radio all 2>/dev/null | head -1 | tr '[:upper:]' '[:lower:]' || true)"
    wifi_radio="${radio_state%%:*}"
    wwan_radio="${radio_state#*:}"
    if [[ -z "$wwan_radio" || "$wwan_radio" == "$radio_state" ]]; then
        wwan_radio="disabled"
    fi
    printf 'RADIO\tairplane\t%s\n' "$([[ "$wifi_radio" != "enabled" && "$wwan_radio" != "enabled" ]] && printf '1' || printf '0')"

    while IFS= read -r dev; do
        [[ -z "$dev" ]] && continue
        emit_card "$dev"
    done < <(nmcli -g DEVICE device status 2>/dev/null || true)

    local line key value in_use="" signal="" freq="" ssid="" bssid="" security="" device=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ -z "$line" ]]; then
            emit_wifi_record "$in_use" "$signal" "$freq" "$ssid" "$bssid" "$security" "$device"
            in_use=""
            signal=""
            freq=""
            ssid=""
            bssid=""
            security=""
            device=""
            continue
        fi

        key="${line%%:*}"
        value="${line#*:}"
        key="${key%"${key##*[![:space:]]}"}"
        value="${value#"${value%%[![:space:]]*}"}"

        case "$key" in
            IN-USE)
                if [[ -n "$device" || -n "$ssid" || -n "$bssid" ]]; then
                    emit_wifi_record "$in_use" "$signal" "$freq" "$ssid" "$bssid" "$security" "$device"
                    signal=""
                    freq=""
                    ssid=""
                    bssid=""
                    security=""
                    device=""
                fi
                in_use="$value"
                ;;
            SIGNAL) signal="$value" ;;
            FREQ) freq="$value" ;;
            SSID) ssid="$value" ;;
            BSSID) bssid="$(unescape_nm "$value")" ;;
            SECURITY) security="$value" ;;
            DEVICE) device="$(unescape_nm "$value")" ;;
        esac
    done < <(nmcli -m multiline -f IN-USE,SIGNAL,FREQ,SSID,BSSID,SECURITY,DEVICE device wifi list --rescan no 2>/dev/null || true)
    emit_wifi_record "$in_use" "$signal" "$freq" "$ssid" "$bssid" "$security" "$device"

    line=""
    key=""
    value=""
    local name="" type="" active_device="" uuid=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ -z "$line" ]]; then
            emit_profile "$uuid" "$name" "$type" "$active_device"
            name=""
            type=""
            active_device=""
            uuid=""
            continue
        fi

        key="${line%%:*}"
        value="${line#*:}"
        key="${key%"${key##*[![:space:]]}"}"
        value="${value#"${value%%[![:space:]]*}"}"

        case "$key" in
            NAME)
                if [[ -n "$uuid" || -n "$name" ]]; then
                    emit_profile "$uuid" "$name" "$type" "$active_device"
                    type=""
                    active_device=""
                    uuid=""
                fi
                name="$value"
                ;;
            TYPE) type="$value" ;;
            DEVICE) active_device="$(unescape_nm "$value")" ;;
            UUID) uuid="$value" ;;
        esac
    done < <(nmcli -m multiline -f NAME,TYPE,DEVICE,UUID connection show 2>/dev/null || true)
    emit_profile "$uuid" "$name" "$type" "$active_device"
}

toggle_wifi() {
    nmcli radio wifi "$1"
}

toggle_airplane() {
    nmcli radio all "$1"
}

rescan_wifi() {
    nmcli device wifi rescan
}

connect_wifi() {
    local ssid="${1-}"
    local bssid="${2-}"
    local device="${3-}"
    local password="${4-}"
    local cmd=(nmcli device wifi connect "$ssid")
    local current_connection=""

    if [[ -n "$device" ]]; then
        current_connection="$(nmcli -g GENERAL.CONNECTION device show "$device" 2>/dev/null | head -1 || true)"
        if [[ -n "$current_connection" && "$current_connection" != "--" && "$current_connection" != "$ssid" ]]; then
            nmcli device disconnect "$device" >/dev/null 2>&1 || true
        fi
    fi

    [[ -n "$bssid" ]] && cmd+=(bssid "$bssid")
    [[ -n "$password" ]] && cmd+=(password "$password")
    [[ -n "$device" ]] && cmd+=(ifname "$device")

    "${cmd[@]}"
}

disconnect_device() {
    nmcli device disconnect "$1"
}

connect_device() {
    nmcli device connect "$1"
}

assign_connection() {
    local uuid="${1-}"
    local ifname="${2-}"
    nmcli connection modify uuid "$uuid" connection.interface-name "$ifname"
}

activate_connection() {
    local uuid="${1-}"
    local ifname="${2-}"
    local cmd=(nmcli connection up uuid "$uuid")
    [[ -n "$ifname" ]] && cmd+=(ifname "$ifname")
    "${cmd[@]}"
}

main() {
    local mode="${1-}"
    shift || true

    case "$mode" in
        snapshot) snapshot ;;
        toggle-wifi) toggle_wifi "${1-}" ;;
        toggle-airplane) toggle_airplane "${1-}" ;;
        rescan-wifi) rescan_wifi ;;
        connect-wifi) connect_wifi "${1-}" "${2-}" "${3-}" "${4-}" ;;
        disconnect-device) disconnect_device "${1-}" ;;
        connect-device) connect_device "${1-}" ;;
        assign-connection) assign_connection "${1-}" "${2-}" ;;
        activate-connection) activate_connection "${1-}" "${2-}" ;;
        *)
            printf 'Unknown mode: %s\n' "$mode" >&2
            exit 64
            ;;
    esac
}

main "$@"
