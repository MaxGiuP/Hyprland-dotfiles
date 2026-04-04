#!/usr/bin/env bash

# ── Colors ────────────────────────────────────────────────────────────────────
R=$'\033[0m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
RED=$'\033[1;31m'
GREEN=$'\033[1;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[1;34m'
CYAN=$'\033[1;36m'
WHITE=$'\033[1;37m'

PASS="${GREEN}✔${R}"
FAIL="${RED}✘${R}"
WARN="${YELLOW}!${R}"

FAILED=()
SKIPPED=()
UPDATED=()

preferred_aur_helper() {
    if command -v yay >/dev/null 2>&1; then
        echo "yay"
    elif command -v paru >/dev/null 2>&1; then
        echo "paru"
    else
        return 1
    fi
}

is_rate_limited() {
    grep -qiE 'status 429|rate limit' <<<"${1:-}"
}

detect_quickshell_pkg() {
    pacman -Qo /usr/bin/quickshell 2>/dev/null | awk '{print $(NF-1)}'
}

package_version() {
    pacman -Q "$1" 2>/dev/null | awk '{print $2}'
}

detect_vmware_host_modules_pkg() {
    pacman -Qq 2>/dev/null | rg '^vmware-host-modules' | head -n 1
}

detect_vmware_workstation_branch() {
    local pkgver branchver
    pkgver=$(package_version vmware-workstation || true)
    pkgver=${pkgver%%-*}
    branchver=${pkgver,,}
    [ -n "$branchver" ] && printf 'workstation-%s\n' "$branchver"
}

find_quickshell_build_dir() {
    local qs_pkg="$1"
    local candidate found
    local -a candidates=(
        "$HOME/$qs_pkg"
        "$HOME/quickshell-git"
        "$HOME/quickshell"
        "$HOME/.cache/yay/$qs_pkg"
        "$HOME/.cache/paru/clone/$qs_pkg"
        "$HOME/Downloads/dots-hyprland/sdata/dist-arch/$qs_pkg"
    )

    for candidate in "${candidates[@]}"; do
        if [ -f "$candidate/PKGBUILD" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    found=$(find "$HOME" -maxdepth 6 -path "*/$qs_pkg/PKGBUILD" -print -quit 2>/dev/null || true)
    if [ -n "$found" ]; then
        dirname "$found"
        return 0
    fi

    return 1
}

find_vmware_build_dir() {
    local pkg="$1"
    local candidate found
    local -a candidates=(
        "$HOME/$pkg"
        "$HOME/.cache/yay/$pkg"
        "$HOME/.cache/paru/clone/$pkg"
        "$HOME/Downloads/dots-hyprland/sdata/dist-arch/$pkg"
    )

    for candidate in "${candidates[@]}"; do
        if [ -f "$candidate/PKGBUILD" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    found=$(find "$HOME" -maxdepth 6 -path "*/$pkg/PKGBUILD" -print -quit 2>/dev/null || true)
    if [ -n "$found" ]; then
        dirname "$found"
        return 0
    fi

    return 1
}

find_vmware_source_repo() {
    local candidate found
    local -a candidates=(
        "$HOME/.cache/yay/vmware-host-modules-dkms-fix-git/vmware-host-modules"
        "$HOME/.cache/yay/vmware-host-modules-dkms-git/vmware-host-modules"
        "$HOME/.cache/paru/clone/vmware-host-modules-dkms-fix-git/vmware-host-modules"
        "$HOME/.cache/paru/clone/vmware-host-modules-dkms-git/vmware-host-modules"
    )

    for candidate in "${candidates[@]}"; do
        if [ -d "$candidate/.git" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    found=$(find "$HOME" -maxdepth 7 -path '*/vmware-host-modules/.git' -print -quit 2>/dev/null || true)
    if [ -n "$found" ]; then
        dirname "$found"
        return 0
    fi

    return 1
}

find_quickshell_git_dir() {
    local build_dir="$1"
    local candidate

    for candidate in \
        "$build_dir/quickshell" \
        "$build_dir/src/quickshell" \
        "$build_dir/src/quickshell-git"; do
        if [ -d "$candidate/.git" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

# ── Count updates ─────────────────────────────────────────────────────────────
count_updates() {
    local n=0 p=0 a=0 f=0 helper=""
    # Use a process-unique temp DB to avoid lock conflicts with concurrent runs
    local tmpdb="/tmp/checkup-db-${UID}-$$"
    if command -v checkupdates-with-aur >/dev/null 2>&1; then
        n=$(CHECKUPDATES_DB="$tmpdb" checkupdates-with-aur 2>/dev/null | wc -l | tr -d ' ')
    else
        command -v checkupdates >/dev/null 2>&1 && p=$(CHECKUPDATES_DB="$tmpdb" checkupdates 2>/dev/null | wc -l | tr -d ' ') || true
        helper=$(preferred_aur_helper 2>/dev/null || true)
        if [ -n "$helper" ]; then
            a=$("$helper" -Qua 2>/dev/null | wc -l | tr -d ' ') || true
        fi
        n=$((p + a))
    fi
    command -v flatpak >/dev/null 2>&1 && f=$(flatpak remote-ls --updates 2>/dev/null | wc -l | tr -d ' ') || true
    rm -rf "$tmpdb"
    echo $((n + f))
}

# ── Fast path for badge ───────────────────────────────────────────────────────
if [ "${1:-}" = "--count-only" ]; then
    count_updates
    exit 0
fi

# ── Load translations ─────────────────────────────────────────────────────────
LANG_CODE="${1:-en_US}"
TRANS_FILE="$HOME/.config/quickshell/ii/translations/${LANG_CODE}.json"

declare -A T
T[SUBTITLE]="Arch Linux system update"
T[CHECKING]="Checking for updates..."
T[UP_TO_DATE]="Everything is up to date"
T[AVAILABLE]="%1 update(s) available"
T[AUTH]="Authentication"
T[SUDO_OK]="sudo authenticated"
T[PKEXEC_FALLBACK]="sudo unavailable — falling back to pkexec"
T[NO_PRIV]="Cannot escalate privileges. Aborting."
T[PRESS_ENTER]="Press Enter to close..."
T[PACMAN]="pacman  —  official repos"
T[YAY]="yay  —  AUR"
T[PARU]="paru  —  AUR"
T[FLATPAK]="flatpak"
T[NOT_FOUND]="not found, skipping"
T[SUMMARY]="Summary"
T[UPDATED]="Updated:"
T[SKIPPED]="Skipped:"
T[FAILED]="Failed:"
T[ERRORS]="One or more package managers encountered errors."
T[SCROLL]="Scroll up to review the output above."
T[ALL_DONE]="All done! Your system is up to date."

if [ -f "$TRANS_FILE" ] && command -v python3 >/dev/null 2>&1; then
    while IFS=$'\x01' read -r key val; do
        [ -n "${T[$key]+x}" ] && T[$key]="$val"
    done < <(python3 - "$TRANS_FILE" <<'PYEOF'
import json, sys
keys = {
    "SUBTITLE":        "Arch Linux system update",
    "CHECKING":        "Checking for updates...",
    "UP_TO_DATE":      "Everything is up to date",
    "AVAILABLE":       "%1 update(s) available",
    "AUTH":            "Authentication",
    "SUDO_OK":         "sudo authenticated",
    "PKEXEC_FALLBACK": "sudo unavailable — falling back to pkexec",
    "NO_PRIV":         "Cannot escalate privileges. Aborting.",
    "PRESS_ENTER":     "Press Enter to close...",
    "PACMAN":          "pacman  —  official repos",
    "YAY":             "yay  —  AUR",
    "PARU":            "paru  —  AUR",
    "FLATPAK":         "flatpak",
    "NOT_FOUND":       "not found, skipping",
    "SUMMARY":         "Summary",
    "UPDATED":         "Updated:",
    "SKIPPED":         "Skipped:",
    "FAILED":          "Failed:",
    "ERRORS":          "One or more package managers encountered errors.",
    "SCROLL":          "Scroll up to review the output above.",
    "ALL_DONE":        "All done! Your system is up to date.",
}
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
except Exception:
    d = {}
for k, english in keys.items():
    val = d.get(english, english)
    print(f"{k}\x01{val}")
PYEOF
    )
fi

# ── Helpers ───────────────────────────────────────────────────────────────────
section() {
    echo
    echo -e "${BOLD}${BLUE}  ┌─ ${WHITE}${1}${R}"
    echo -e "${BLUE}  └──────────────────────────────────────────────────────${R}"
    echo
}

ok()   { echo -e "  ${PASS}  ${GREEN}${1}${R}"; UPDATED+=("${1}"); }
fail() { echo -e "  ${FAIL}  ${RED}${1}${R}";   FAILED+=("${1}"); }
skip() { echo -e "  ${DIM}  –  ${1} ${T[NOT_FOUND]}${R}"; SKIPPED+=("${1}"); }

run_pkg() {
    local name="$1"; shift
    if command -v "${1}" >/dev/null 2>&1; then
        if "$@"; then ok "${name}"; else fail "${name}"; fi
    else
        skip "${name}"
    fi
}

run_aur_updates() {
    local helper title output rc attempt delay
    helper=$(preferred_aur_helper 2>/dev/null || true)

    if [ -z "$helper" ]; then
        skip "AUR helper"
        return 0
    fi

    if [ "$helper" = "yay" ]; then
        title="${T[YAY]}"
    else
        title="${T[PARU]}"
    fi

    section "$title"

    for attempt in 1 2 3; do
        output=$("$helper" -Sua --devel --noconfirm 2>&1)
        rc=$?
        [ -n "$output" ] && printf '%s\n' "$output"

        if [ $rc -eq 0 ]; then
            ok "$helper"
            return 0
        fi

        if is_rate_limited "$output"; then
            if [ "$attempt" -lt 3 ]; then
                delay=$((attempt * 15))
                echo -e "  ${WARN}  ${YELLOW}${helper} hit the AUR rate limit; retrying in ${delay}s...${R}"
                sleep "$delay"
                continue
            fi

            echo -e "  ${WARN}  ${YELLOW}${helper} hit the AUR rate limit again; skipping AUR updates for this run.${R}"
            SKIPPED+=("${helper} (rate-limited)")
            return 0
        fi

        fail "$helper"
        return 1
    done
}

# ── Banner ────────────────────────────────────────────────────────────────────
clear
echo
echo -e "${CYAN}${BOLD}"
if [[ "$LANG_CODE" == it_* ]]; then
echo '   █████╗  ██████╗  ██████╗ ██╗ ██████╗ ██████╗ ███╗   ██╗ █████╗ '
echo '  ██╔══██╗██╔════╝ ██╔════╝ ██║██╔═══██╗██╔══██╗████╗  ██║██╔══██╗'
echo '  ███████║██║  ███╗██║  ███╗██║██║   ██║██████╔╝██╔██╗ ██║███████║'
echo '  ██╔══██║██║   ██║██║   ██║██║██║   ██║██╔══██╗██║╚██╗██║██╔══██║'
echo '  ██║  ██║╚██████╔╝╚██████╔╝██║╚██████╔╝██║  ██╗██║ ╚████║██║  ██║'
echo '  ╚═╝  ╚═╝ ╚═════╝  ╚═════╝ ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝'
else
echo '        ██╗   ██╗██████╗ ██████╗  █████╗ ████████╗███████╗'
echo '        ██║   ██║██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝'
echo '        ██║   ██║██████╔╝██║  ██║███████║   ██║   █████╗  '
echo '        ██║   ██║██╔═══╝ ██║  ██║██╔══██║   ██║   ██╔══╝  '
echo '        ╚██████╔╝██║     ██████╔╝██║  ██║   ██║   ███████╗'
echo '         ╚═════╝ ╚═╝     ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝'
fi
echo -e "${R}"
echo -e "  ${DIM}─────────────────────────────────────────────────────────────${R}"
echo -e "  ${DIM}  ${T[SUBTITLE]}  ·  $(date '+%Y-%m-%d  %H:%M:%S')${R}"
echo -e "  ${DIM}─────────────────────────────────────────────────────────────${R}"

# ── Count ─────────────────────────────────────────────────────────────────────
echo
echo -e "  ${DIM}${T[CHECKING]}${R}"
TOTAL=$(count_updates)
if [ "$TOTAL" -eq 0 ]; then
    echo -e "  ${PASS}  ${GREEN}${T[UP_TO_DATE]}${R}"
else
    msg="${T[AVAILABLE]//%1/$TOTAL}"
    echo -e "  ${WARN}  ${YELLOW}${BOLD}${msg}${R}"
fi

# ── Auth ──────────────────────────────────────────────────────────────────────
section "${T[AUTH]}"
USE_SUDO=1
if sudo -v 2>/dev/null; then
    ok "sudo"
elif command -v pkexec >/dev/null 2>&1; then
    USE_SUDO=0
    echo -e "  ${WARN}  ${YELLOW}${T[PKEXEC_FALLBACK]}${R}"
else
    fail "auth"
    echo
    echo -e "  ${RED}  ${T[NO_PRIV]}${R}"
    echo
    read -rp "  ${T[PRESS_ENTER]}"
    exit 1
fi

priv() {
    if [ "$USE_SUDO" -eq 1 ]; then sudo "$@"; else pkexec "$@"; fi
}

VMWARE_WORKSTATION_BEFORE=$(package_version vmware-workstation || true)
VMWARE_HOST_MODULES_PKG_BEFORE=$(detect_vmware_host_modules_pkg || true)
VMWARE_HOST_MODULES_BEFORE=""
if [ -n "$VMWARE_HOST_MODULES_PKG_BEFORE" ]; then
    VMWARE_HOST_MODULES_BEFORE=$(package_version "$VMWARE_HOST_MODULES_PKG_BEFORE" || true)
fi
KERNEL_BEFORE=$(package_version linux || true)
KERNEL_HEADERS_BEFORE=$(package_version linux-headers || true)

# ── pacman ────────────────────────────────────────────────────────────────────
section "${T[PACMAN]}"
if command -v pacman >/dev/null 2>&1; then
    if priv pacman -Syu; then ok "pacman"; else fail "pacman"; fi
else
    skip "pacman"
fi

# ── AUR ───────────────────────────────────────────────────────────────────────
run_aur_updates

# ── flatpak ───────────────────────────────────────────────────────────────────
section "${T[FLATPAK]}"
run_pkg "flatpak" flatpak update -y

# ── quickshell (rebuild from source) ─────────────────────────────────────────
rebuild_quickshell() {
    section "quickshell — source rebuild"

    local qs_pkg build_dir git_dir helper compat_output behind rebuild_needed rebuild_reason
    qs_pkg=$(detect_quickshell_pkg)
    if [ -z "$qs_pkg" ]; then
        skip "quickshell"
        return 0
    fi
    echo -e "  ${DIM}Detected: ${qs_pkg}${R}"

    build_dir=$(find_quickshell_build_dir "$qs_pkg" 2>/dev/null || true)
    if [ -n "$build_dir" ]; then
        echo -e "  ${DIM}PKGBUILD: ${build_dir}${R}"
    fi

    rebuild_needed=0
    rebuild_reason=""

    if command -v quickshell >/dev/null 2>&1; then
        compat_output=$(quickshell --private-check-compat 2>&1 || true)
        if [ -n "$compat_output" ]; then
            printf '%s\n' "$compat_output"
        fi
        if ! quickshell --private-check-compat >/dev/null 2>&1; then
            rebuild_needed=1
            rebuild_reason="Qt compatibility mismatch"
        fi
    fi

    git_dir=""
    if [ -n "$build_dir" ]; then
        git_dir=$(find_quickshell_git_dir "$build_dir" 2>/dev/null || true)
    fi

    if [ -n "$git_dir" ]; then
        echo -e "  ${DIM}Fetching upstream...${R}"
        git -C "$git_dir" fetch origin --quiet 2>/dev/null || true

        behind=$(git -C "$git_dir" rev-list HEAD..@{u} --count 2>/dev/null || echo "0")
        if [ "$behind" -gt 0 ]; then
            rebuild_needed=1
            if [ -n "$rebuild_reason" ]; then
                rebuild_reason="${rebuild_reason}; ${behind} new upstream commit(s)"
            else
                rebuild_reason="${behind} new upstream commit(s)"
            fi
            echo -e "  ${WARN}  ${YELLOW}${behind} new commit(s) detected${R}"
            git -C "$git_dir" log --oneline HEAD..@{u} 2>/dev/null | while read -r line; do
                echo -e "  ${DIM}    • $line${R}"
            done
        fi
    fi

    if [ "$rebuild_needed" -eq 0 ]; then
        echo -e "  ${PASS}  ${GREEN}quickshell compatibility OK — no rebuild needed${R}"
        return 0
    fi

    echo -e "  ${WARN}  ${YELLOW}Rebuilding quickshell: ${rebuild_reason}${R}"

    if [ -n "$build_dir" ]; then
        if (cd "$build_dir" && makepkg -sif --noconfirm); then
            :
        else
            fail "quickshell"
            return 1
        fi
    else
        helper=$(preferred_aur_helper 2>/dev/null || true)
        if [ -z "$helper" ]; then
            fail "quickshell"
            return 1
        fi
        echo -e "  ${DIM}No local PKGBUILD found — using ${helper}${R}"
        if "$helper" -S "$qs_pkg" --devel --rebuild --noconfirm; then
            :
        else
            fail "quickshell"
            return 1
        fi
    fi

    if command -v quickshell >/dev/null 2>&1 && quickshell --private-check-compat >/dev/null 2>&1; then
        ok "quickshell"
    else
        fail "quickshell"
        return 1
    fi
}

rebuild_quickshell

# ── VMware (host modules rebuild) ────────────────────────────────────────────
repair_vmware() {
    section "VMware — host modules"

    local workstation_after host_pkg_after host_after kernel_after headers_after
    local repair_needed repair_reason build_dir helper vmware_branch vmware_repo branch_ref
    local tarball_tmp

    workstation_after=$(package_version vmware-workstation || true)
    if [ -z "$workstation_after" ]; then
        skip "vmware"
        return 0
    fi

    host_pkg_after=$(detect_vmware_host_modules_pkg || true)
    host_after=""
    if [ -n "$host_pkg_after" ]; then
        host_after=$(package_version "$host_pkg_after" || true)
    fi

    kernel_after=$(package_version linux || true)
    headers_after=$(package_version linux-headers || true)

    echo -e "  ${DIM}Detected: vmware-workstation ${workstation_after}${R}"
    if [ -n "$host_pkg_after" ]; then
        echo -e "  ${DIM}Host modules: ${host_pkg_after} ${host_after}${R}"
    fi

    repair_needed=0
    repair_reason=""

    if [ "${VMWARE_WORKSTATION_BEFORE:-}" != "$workstation_after" ]; then
        repair_needed=1
        repair_reason="vmware-workstation changed"
    fi

    if [ "${VMWARE_HOST_MODULES_BEFORE:-}" != "$host_after" ]; then
        repair_needed=1
        if [ -n "$repair_reason" ]; then
            repair_reason="${repair_reason}; host modules changed"
        else
            repair_reason="host modules changed"
        fi
    fi

    if [ "${KERNEL_BEFORE:-}" != "$kernel_after" ] || [ "${KERNEL_HEADERS_BEFORE:-}" != "$headers_after" ]; then
        repair_needed=1
        if [ -n "$repair_reason" ]; then
            repair_reason="${repair_reason}; kernel packages changed"
        else
            repair_reason="kernel packages changed"
        fi
    fi

    if [ "$repair_needed" -eq 0 ]; then
        echo -e "  ${PASS}  ${GREEN}VMware modules look unchanged — no repair needed${R}"
        return 0
    fi

    echo -e "  ${WARN}  ${YELLOW}Repairing VMware modules: ${repair_reason}${R}"

    vmware_branch=$(detect_vmware_workstation_branch || true)
    vmware_repo=$(find_vmware_source_repo 2>/dev/null || true)
    branch_ref=""

    if [ -n "$vmware_repo" ] && [ -n "$vmware_branch" ]; then
        git -C "$vmware_repo" fetch origin --quiet 2>/dev/null || true
        if git -C "$vmware_repo" rev-parse --verify "${vmware_branch}^{commit}" >/dev/null 2>&1; then
            branch_ref="$vmware_branch"
        elif git -C "$vmware_repo" rev-parse --verify "origin/${vmware_branch}^{commit}" >/dev/null 2>&1; then
            branch_ref="origin/${vmware_branch}"
        fi
    fi

    if [ -n "$branch_ref" ] && [ -n "$vmware_repo" ]; then
        echo -e "  ${DIM}Using VMware source branch: ${vmware_branch}${R}"
        build_tmp=$(mktemp -d /tmp/vmware-host-modules.XXXXXX)
        module_dir="/lib/modules/${kernel_after}/updates/dkms"

        if git -C "$vmware_repo" archive "$branch_ref" | tar -x -C "$build_tmp" \
            && git -C "$vmware_repo" archive -o "$build_tmp/vmmon.tar" "$branch_ref" vmmon-only \
            && git -C "$vmware_repo" archive -o "$build_tmp/vmnet.tar" "$branch_ref" vmnet-only \
            && make VM_UNAME="$kernel_after" -C "$build_tmp" \
            && zstd -f "$build_tmp/vmmon-only/vmmon.ko" -o "$build_tmp/vmmon.ko.zst" \
            && zstd -f "$build_tmp/vmnet-only/vmnet.ko" -o "$build_tmp/vmnet.ko.zst" \
            && priv install -d "$module_dir" /usr/lib/vmware/modules/source \
            && priv install -m 0644 "$build_tmp/vmmon.ko.zst" "$module_dir/vmmon.ko.zst" \
            && priv install -m 0644 "$build_tmp/vmnet.ko.zst" "$module_dir/vmnet.ko.zst" \
            && priv install -m 0644 "$build_tmp/vmmon.tar" /usr/lib/vmware/modules/source/vmmon.tar \
            && priv install -m 0644 "$build_tmp/vmnet.tar" /usr/lib/vmware/modules/source/vmnet.tar \
            && priv depmod -a "$kernel_after"; then
            rm -rf "$build_tmp"
        else
            rm -rf "$build_tmp"
            fail "vmware"
            return 1
        fi
    elif [ -n "$host_pkg_after" ]; then
        build_dir=$(find_vmware_build_dir "$host_pkg_after" 2>/dev/null || true)
        if [ -n "$build_dir" ]; then
            echo -e "  ${DIM}PKGBUILD: ${build_dir}${R}"
            if (cd "$build_dir" && makepkg -sif --noconfirm); then
                :
            else
                fail "vmware"
                return 1
            fi
        else
            helper=$(preferred_aur_helper 2>/dev/null || true)
            if [ -z "$helper" ]; then
                fail "vmware"
                return 1
            fi
            echo -e "  ${DIM}No local PKGBUILD found — using ${helper}${R}"
            if "$helper" -S "$host_pkg_after" --rebuild --noconfirm; then
                :
            else
                fail "vmware"
                return 1
            fi
        fi
    elif command -v vmware-modconfig >/dev/null 2>&1; then
        if priv env DISPLAY= WAYLAND_DISPLAY= VMWARE_SKIP_SERVICES=1 vmware-modconfig --console --install-all; then
            :
        else
            fail "vmware"
            return 1
        fi
    else
        fail "vmware"
        return 1
    fi

    if pgrep -fa 'vmware-vmx|vmplayer|vmware$|vmware ' >/dev/null 2>&1; then
        echo -e "  ${WARN}  ${YELLOW}VMware is running — skipping module reload. Close VMware once before launching it again.${R}"
    else
        priv systemctl stop vmware-networks.service vmware-usbarbitrator.service >/dev/null 2>&1 || true
        priv modprobe -r vmnet vmmon >/dev/null 2>&1 || true
        priv modprobe vmmon >/dev/null 2>&1 || true
        priv modprobe vmnet >/dev/null 2>&1 || true
        priv systemctl start vmware-networks.service vmware-usbarbitrator.service >/dev/null 2>&1 || true
    fi

    if modinfo vmmon >/dev/null 2>&1 && modinfo vmnet >/dev/null 2>&1; then
        ok "vmware"
    else
        fail "vmware"
        return 1
    fi
}

repair_vmware

# ── Summary ───────────────────────────────────────────────────────────────────
echo
echo -e "  ${BOLD}${BLUE}┌──────────────────────────────────────────────────────────┐${R}"
echo -e "  ${BOLD}${BLUE}│${WHITE}  ${T[SUMMARY]}$(printf '%*s' $((56 - ${#T[SUMMARY]})) '')${BOLD}${BLUE}│${R}"
echo -e "  ${BOLD}${BLUE}└──────────────────────────────────────────────────────────┘${R}"
echo

[ ${#UPDATED[@]} -gt 0 ] && echo -e "  ${PASS}  ${GREEN}${T[UPDATED]}${R}  ${UPDATED[*]}"
[ ${#SKIPPED[@]} -gt 0 ] && echo -e "  ${DIM}  –  ${T[SKIPPED]} ${SKIPPED[*]}${R}"

if [ ${#FAILED[@]} -gt 0 ]; then
    echo
    echo -e "  ${FAIL}  ${RED}${BOLD}${T[FAILED]} ${FAILED[*]}${R}"
    echo
    echo -e "  ${RED}  ⚠  ${T[ERRORS]}${R}"
    echo -e "  ${DIM}     ${T[SCROLL]}${R}"
    echo
    read -rp "  ${T[PRESS_ENTER]}"
    exit 1
fi

echo
echo -e "  ${GREEN}${BOLD}  ✔  ${T[ALL_DONE]}${R}"
echo
read -rp "  ${T[PRESS_ENTER]}"
