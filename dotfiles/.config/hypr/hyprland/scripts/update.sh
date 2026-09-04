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
SKIP_PKGS=()
PENDING_AUR_HELPER=""
PENDING_AUR_CAPTURED=""
PENDING_AUR_IGNORE_ARGS=()
declare -A CONFLICT_DECISIONS=()   # Per-run: "installed:incoming" -> "skip"|"remove"
declare -A CONFLICT_PREFERENCES=() # Package pair -> preferred package
declare -A CONFLICT_PREFERENCE_DATES=()
CONFLICT_PREFERENCES_LOADED=0
CONFLICT_PREFERENCES_PRIMED=0
CONFLICT_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hyprland-updater"
CONFLICT_PREFERENCES_FILE="$CONFLICT_STATE_DIR/conflict-preferences.tsv"
CONFLICT_NEW_DECISION=0            # set to 1 when resolve_conflicts shows a new menu
CONFLICT_ABORT=0                   # set to 1 when the user aborts conflict handling
ASSUME_INSTALLED=()                # packages to pass as --assume-installed when skipping
REBOOT_REQUIRED=0
REBOOT_REASONS=()
UPDATE_PLAN="full"
REBOOT_UPDATE_PACKAGES=()
declare -A REBOOT_PACKAGE_VERSIONS_BEFORE=()
declare -A INSTALLED_KERNEL_PACKAGES=()

conflict_pair_key() {
    local pkg_a="$1" pkg_b="$2"

    if [[ "$pkg_a" < "$pkg_b" ]]; then
        printf '%s\x1f%s' "$pkg_a" "$pkg_b"
    else
        printf '%s\x1f%s' "$pkg_b" "$pkg_a"
    fi
}

valid_conflict_package_name() {
    [[ "${1:-}" =~ ^[[:alnum:]@._+:-]+$ ]]
}

load_conflict_preferences() {
    local pkg_a pkg_b preferred saved_at key

    [ "$CONFLICT_PREFERENCES_LOADED" -eq 0 ] || return 0
    CONFLICT_PREFERENCES_LOADED=1
    [ -r "$CONFLICT_PREFERENCES_FILE" ] || return 0

    while IFS=$'\t' read -r pkg_a pkg_b preferred saved_at _rest; do
        [[ -n "$pkg_a" && "${pkg_a:0:1}" != "#" ]] || continue
        valid_conflict_package_name "$pkg_a" || continue
        valid_conflict_package_name "$pkg_b" || continue
        [ "$pkg_a" != "$pkg_b" ] || continue
        [ "$preferred" = "$pkg_a" ] || [ "$preferred" = "$pkg_b" ] || continue
        [[ "$saved_at" =~ ^[0-9]+$ ]] || saved_at=0

        key=$(conflict_pair_key "$pkg_a" "$pkg_b")
        CONFLICT_PREFERENCES[$key]="$preferred"
        CONFLICT_PREFERENCE_DATES[$key]="$saved_at"
    done < "$CONFLICT_PREFERENCES_FILE"
}

save_conflict_preferences() {
    local tmp key pkg_a pkg_b

    mkdir -p "$CONFLICT_STATE_DIR" || return 1
    chmod 700 "$CONFLICT_STATE_DIR" 2>/dev/null || true
    tmp=$(mktemp "$CONFLICT_STATE_DIR/.conflict-preferences.XXXXXX") || return 1
    chmod 600 "$tmp" 2>/dev/null || true

    {
        printf '# package-a\tpackage-b\tpreferred\tsaved-at\n'
        for key in "${!CONFLICT_PREFERENCES[@]}"; do
            IFS=$'\x1f' read -r pkg_a pkg_b <<< "$key"
            printf '%s\t%s\t%s\t%s\n' \
                "$pkg_a" "$pkg_b" "${CONFLICT_PREFERENCES[$key]}" \
                "${CONFLICT_PREFERENCE_DATES[$key]:-0}"
        done | LC_ALL=C sort
    } > "$tmp"

    if ! mv -f "$tmp" "$CONFLICT_PREFERENCES_FILE"; then
        rm -f "$tmp"
        return 1
    fi
}

remember_conflict_preference() {
    local pkg_a="$1" pkg_b="$2" preferred="$3" key

    load_conflict_preferences
    key=$(conflict_pair_key "$pkg_a" "$pkg_b")
    CONFLICT_PREFERENCES[$key]="$preferred"
    CONFLICT_PREFERENCE_DATES[$key]="$(date +%s)"
    save_conflict_preferences
}

forget_conflict_preference() {
    local pkg_a="$1" pkg_b="$2" key

    load_conflict_preferences
    key=$(conflict_pair_key "$pkg_a" "$pkg_b")
    if [ -z "${CONFLICT_PREFERENCES[$key]+x}" ]; then
        printf 'No remembered preference for %s and %s.\n' "$pkg_a" "$pkg_b"
        return 0
    fi

    unset 'CONFLICT_PREFERENCES[$key]' 'CONFLICT_PREFERENCE_DATES[$key]'
    save_conflict_preferences
    printf 'Forgot the preference for %s and %s.\n' "$pkg_a" "$pkg_b"
}

show_conflict_preferences() {
    local key pkg_a pkg_b preferred saved_at saved_on

    load_conflict_preferences
    if [ "${#CONFLICT_PREFERENCES[@]}" -eq 0 ]; then
        echo "No remembered package conflict preferences."
        return 0
    fi

    echo "Remembered package conflict preferences:"
    while IFS=$'\t' read -r pkg_a pkg_b preferred saved_at; do
        if [ "$saved_at" -gt 0 ] 2>/dev/null; then
            saved_on=$(date -d "@$saved_at" +%Y-%m-%d 2>/dev/null || printf 'unknown date')
        else
            saved_on="unknown date"
        fi
        printf '  %-30s ↔ %-30s prefer %s  (%s)\n' "$pkg_a" "$pkg_b" "$preferred" "$saved_on"
    done < <(
        for key in "${!CONFLICT_PREFERENCES[@]}"; do
            IFS=$'\x1f' read -r pkg_a pkg_b <<< "$key"
            printf '%s\t%s\t%s\t%s\n' \
                "$pkg_a" "$pkg_b" "${CONFLICT_PREFERENCES[$key]}" \
                "${CONFLICT_PREFERENCE_DATES[$key]:-0}"
        done | LC_ALL=C sort
    )
    echo
    echo "Forget one with: $0 --forget-conflict PACKAGE_A PACKAGE_B"
    echo "Forget all with: $0 --reset-conflict-preferences"
}

case "${1:-}" in
    --conflict-preferences)
        show_conflict_preferences
        exit 0
        ;;
    --forget-conflict)
        if [ "$#" -ne 3 ]; then
            echo "Usage: $0 --forget-conflict PACKAGE_A PACKAGE_B" >&2
            exit 2
        fi
        forget_conflict_preference "$2" "$3"
        exit $?
        ;;
    --reset-conflict-preferences)
        rm -f "$CONFLICT_PREFERENCES_FILE"
        echo "Forgot all package conflict preferences."
        exit 0
        ;;
esac

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

package_upstream_version() {
    local version
    version=$(package_version "$1" || true)
    version=${version#*:}
    version=${version%-*}
    [ -n "$version" ] && printf '%s\n' "$version"
}

installed_linux_release() {
    local version
    version=$(package_version linux || true)
    [ -n "$version" ] || return 1
    printf '%s\n' "${version/.arch/-arch}"
}

loaded_nvidia_version() {
    [ -r /proc/driver/nvidia/version ] || return 1
    awk '/NVRM version:/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+([.][0-9]+)+$/) { print $i; exit } }' \
        /proc/driver/nvidia/version
}

mark_reboot_required() {
    local reason="$1"
    local existing

    REBOOT_REQUIRED=1
    for existing in "${REBOOT_REASONS[@]:-}"; do
        [ "$existing" = "$reason" ] && return 0
    done
    REBOOT_REASONS+=("$reason")
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
        "$HOME/.cache/yay/quickshell-git"
        "$HOME/.cache/paru/clone/$qs_pkg"
        "$HOME/.cache/paru/clone/quickshell-git"
        "$HOME/Downloads/dots-hyprland/sdata/dist-arch/$qs_pkg"
        "$HOME/Downloads/dots-hyprland/sdata/dist-arch/illogical-impulse-quickshell-git"
        "$HOME/.cache/dots-hyprland/sdata/dist-arch/illogical-impulse-quickshell-git"
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

sync_quickshell_user_local() {
    local build_dir="${1:-}"
    local src_root bin_src qml_src dest_version candidate_version newest_version
    local dest_bin="$HOME/.local/libexec/quickshell/quickshell"
    local dest_qml="$HOME/.local/lib/qt6/qml"

    src_root=""
    if [ -n "$build_dir" ] && [ -d "$build_dir/pkg" ]; then
        src_root=$(find "$build_dir/pkg" -mindepth 1 -maxdepth 1 -type d -name '*quickshell*' -print -quit 2>/dev/null || true)
    fi

    bin_src=""
    if [ -n "$src_root" ] && [ -x "$src_root/usr/bin/quickshell" ]; then
        bin_src="$src_root/usr/bin/quickshell"
    elif [ -x /usr/bin/quickshell ]; then
        bin_src=/usr/bin/quickshell
    fi

    if [ -z "$bin_src" ]; then
        return 1
    fi

    # A host-built release may intentionally be newer than the pinned package
    # candidate. Preserve it (and its matching QML metadata) while it remains
    # ABI compatible; a future package at the same or newer version wins.
    if [ -x "$dest_bin" ] && [ -d "$dest_qml/Quickshell" ] \
        && "$dest_bin" --private-check-compat >/dev/null 2>&1; then
        dest_version=$("$dest_bin" --version 2>/dev/null | sed -nE 's/.* ([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' | head -n 1)
        candidate_version=$("$bin_src" --version 2>/dev/null | sed -nE 's/.* ([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' | head -n 1)
        if [ -n "$dest_version" ] && [ -n "$candidate_version" ] && [ "$dest_version" != "$candidate_version" ]; then
            newest_version=$(printf '%s\n%s\n' "$dest_version" "$candidate_version" | sort -V | tail -n 1)
            if [ "$newest_version" = "$dest_version" ]; then
                printf 'Preserving newer compatible local Quickshell %s (package candidate %s)\n' "$dest_version" "$candidate_version"
                return 0
            fi
        fi
    fi

    # Do not retain a 170+ MB byte-for-byte copy of the packaged binary. The
    # wrappers already fall back to /usr/bin/quickshell, while a genuinely
    # different compatibility build still remains user-local.
    if [ -x /usr/bin/quickshell ] && cmp -s "$bin_src" /usr/bin/quickshell; then
        rm -f -- "$dest_bin" || return 1
    else
        install -Dm755 "$bin_src" "$dest_bin" || return 1
    fi

    qml_src=""
    if [ -n "$src_root" ] && [ -d "$src_root/usr/lib/qt6/qml/Quickshell" ]; then
        qml_src="$src_root/usr/lib/qt6/qml/Quickshell"
    elif [ -d /usr/lib/qt6/qml/Quickshell ]; then
        qml_src=/usr/lib/qt6/qml/Quickshell
    fi

    qml_matches_system=0
    if [ -n "$qml_src" ] && [ -d /usr/lib/qt6/qml/Quickshell ] \
        && diff -qr "$qml_src" /usr/lib/qt6/qml/Quickshell >/dev/null 2>&1; then
        qml_matches_system=1
    fi

    if [ -n "$qml_src" ] && [ "$qml_matches_system" -eq 0 ]; then
        install -d "$dest_qml" || return 1
        rm -rf "$dest_qml/Quickshell" || return 1
        cp -a "$qml_src" "$dest_qml/" || return 1
    elif [ "$qml_matches_system" -eq 1 ] && [ -d "$dest_qml/Quickshell" ]; then
        rm -rf -- "$dest_qml/Quickshell" || return 1
    fi
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

find_vmware_workstation_dkms_version() {
    local dir latest

    latest=""
    for dir in /usr/src/vmware-workstation-*; do
        [ -d "$dir" ] || continue
        [ -f "$dir/dkms.conf" ] || continue
        latest="${dir##*/vmware-workstation-}"
    done

    [ -n "$latest" ] || return 1
    printf '%s\n' "$latest"
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
    local n=0 p=0 a=0 f=0 helper="" output="" status=0
    # Use a process-unique temp DB to avoid lock conflicts with concurrent runs
    local tmpdb
    tmpdb=$(mktemp -d "/tmp/checkup-db-${UID}-XXXXXX") || return 1

    if command -v checkupdates >/dev/null 2>&1; then
        output=$(CHECKUPDATES_DB="$tmpdb" checkupdates 2>/dev/null)
        status=$?
        if [ "$status" -ne 0 ] && [ "$status" -ne 2 ]; then
            rm -rf -- "$tmpdb"
            return 1
        fi
        p=$(awk 'NF { count++ } END { print count + 0 }' <<< "$output")
    fi

    helper=$(preferred_aur_helper 2>/dev/null || true)
    if [ -n "$helper" ]; then
        if ! output=$("$helper" -Qua 2>/dev/null); then
            rm -rf -- "$tmpdb"
            return 1
        fi
        a=$(awk 'NF { count++ } END { print count + 0 }' <<< "$output")
    fi
    n=$((p + a))

    if command -v flatpak >/dev/null 2>&1; then
        if ! output=$(flatpak remote-ls --updates 2>/dev/null); then
            rm -rf -- "$tmpdb"
            return 1
        fi
        f=$(awk 'NF { count++ } END { print count + 0 }' <<< "$output")
    fi

    rm -rf -- "$tmpdb"
    printf '%s\n' $((n + f))
}

count_updates_cached() {
    local cache_dir cache_file lock_file now cached_at cached_count count tmp
    local ttl="${UPDATE_COUNT_CACHE_TTL:-600}"
    cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/hyprland-updater"
    cache_file="$cache_dir/update-count"
    lock_file="$cache_dir/update-count.lock"
    if [[ ! "$ttl" =~ ^[0-9]+$ ]] || [ "${#ttl}" -gt 6 ]; then
        ttl=600
    else
        ttl=$((10#$ttl))
        [ "$ttl" -le 86400 ] || ttl=86400
    fi
    now=$(date +%s)

    mkdir -p "$cache_dir"
    chmod 700 "$cache_dir" 2>/dev/null || true

    read_cache() {
        cached_at=""
        cached_count=""
        [ -r "$cache_file" ] || return 1
        read -r cached_at cached_count < "$cache_file" || return 1
        [[ "$cached_at" =~ ^[0-9]+$ && "$cached_count" =~ ^[0-9]+$ ]] || return 1
        [ "${#cached_at}" -le 12 ] && [ "${#cached_count}" -le 9 ] || return 1
        cached_at=$((10#$cached_at))
        cached_count=$((10#$cached_count))
    }

    cache_is_fresh() {
        read_cache || return 1
        [ "$cached_at" -le "$now" ] && [ $((now - cached_at)) -lt "$ttl" ]
    }

    if cache_is_fresh; then
        printf '%s\n' "$cached_count"
        return 0
    fi

    # Reloads can start several shell instances together. Only one is allowed
    # to query package/AUR/Flatpak metadata; followers reuse its result.
    exec 9>"$lock_file"
    if command -v flock >/dev/null 2>&1; then
        flock -w 2 9 || {
            if read_cache && [ "$cached_at" -le "$now" ]; then
                printf '%s\n' "$cached_count"
                return 0
            fi
            return 1
        }
    fi

    now=$(date +%s)
    if cache_is_fresh; then
        printf '%s\n' "$cached_count"
        return 0
    fi

    if ! count=$(count_updates) || [[ ! "$count" =~ ^[0-9]+$ ]]; then
        if read_cache && [ "$cached_at" -le "$now" ]; then
            printf '%s\n' "$cached_count"
            return 0
        fi
        return 1
    fi
    now=$(date +%s)
    tmp=$(mktemp "$cache_dir/.update-count.XXXXXX") || {
        printf '%s\n' "$count"
        return 0
    }
    chmod 600 "$tmp" 2>/dev/null || true
    printf '%s %s\n' "$now" "$count" > "$tmp"
    mv -f "$tmp" "$cache_file" || rm -f -- "$tmp"
    printf '%s\n' "$count"
}

pending_native_packages() {
    local tmpdb="/tmp/reboot-plan-db-${UID}-$$" helper

    if command -v checkupdates >/dev/null 2>&1; then
        CHECKUPDATES_DB="$tmpdb" checkupdates 2>/dev/null || true
    else
        pacman -Qu 2>/dev/null || true
    fi

    helper=$(preferred_aur_helper 2>/dev/null || true)
    if [ -n "$helper" ]; then
        "$helper" -Qua 2>/dev/null || true
    fi

    rm -rf "$tmpdb"
}

is_reboot_sensitive_package() {
    local pkg="$1"

    [ -n "${INSTALLED_KERNEL_PACKAGES[$pkg]+x}" ] && return 0

    case "$pkg" in
        linux|linux-lts|linux-zen|linux-hardened|linux-rt|linux-rt-lts|linux-cachyos*)
            return 0
            ;;
        linux-firmware|linux-firmware-*|amd-ucode|intel-ucode)
            return 0
            ;;
        nvidia|nvidia-*|lib32-nvidia-*|opencl-nvidia|opencl-nvidia-*|lib32-opencl-nvidia*)
            return 0
            ;;
        *-nvidia|*-nvidia-*)
            return 0
            ;;
    esac

    return 1
}

detect_reboot_sensitive_updates() {
    local pkg owner
    local -A seen=()

    REBOOT_UPDATE_PACKAGES=()
    REBOOT_PACKAGE_VERSIONS_BEFORE=()
    INSTALLED_KERNEL_PACKAGES=()

    while IFS= read -r owner; do
        [ -n "$owner" ] && INSTALLED_KERNEL_PACKAGES[$owner]=1
    done < <(pacman -Qqo /usr/lib/modules/*/vmlinuz 2>/dev/null | sort -u)

    while IFS= read -r pkg; do
        [ -n "$pkg" ] || continue
        [ -z "${seen[$pkg]+x}" ] || continue
        seen[$pkg]=1
        is_reboot_sensitive_package "$pkg" || continue
        REBOOT_UPDATE_PACKAGES+=("$pkg")
        REBOOT_PACKAGE_VERSIONS_BEFORE[$pkg]="$(package_version "$pkg" || true)"
    done < <(pending_native_packages | awk '{print $1}' | LC_ALL=C sort -u)
}

mark_updated_reboot_packages() {
    local pkg before after
    local -a changed=()

    for pkg in "${REBOOT_UPDATE_PACKAGES[@]:-}"; do
        before="${REBOOT_PACKAGE_VERSIONS_BEFORE[$pkg]:-}"
        after=$(package_version "$pkg" || true)
        [ "$before" != "$after" ] && changed+=("$pkg")
    done

    if [ "${#changed[@]}" -gt 0 ]; then
        mark_reboot_required "reboot-sensitive packages updated: ${changed[*]}"
    fi
}

if [ "${1:-}" = "--reboot-sensitive" ]; then
    detect_reboot_sensitive_updates
    if [ "${#REBOOT_UPDATE_PACKAGES[@]}" -eq 0 ]; then
        echo "No pending reboot-sensitive package updates detected."
    else
        printf '%s\n' "${REBOOT_UPDATE_PACKAGES[@]}"
    fi
    exit 0
fi

# ── Fast path for badge ───────────────────────────────────────────────────────
if [ "${1:-}" = "--count-only" ]; then
    count_updates_cached
    exit 0
fi

# ── Load translations ─────────────────────────────────────────────────────────
normalize_lang_code() {
    local value="${1:-}"
    value="${value%%:*}"
    value="${value%%.*}"
    value="${value%%@*}"
    value="${value//-/_}"

    case "$value" in
        ""|auto|C|POSIX) return 1 ;;
    esac

    printf '%s\n' "$value"
}

translation_lang_code() {
    local value="$1" match

    if [ "${value#*_}" = "$value" ]; then
        match=$(find "$HOME/.config/quickshell/ii/translations" -maxdepth 1 -type f -name "${value}_*.json" -print 2>/dev/null | sort | head -n 1)
        if [ -n "$match" ]; then
            basename "$match" .json
            return 0
        fi
    fi

    printf '%s\n' "$value"
}

locale_value_from_file() {
    local file="$1" key="$2"
    [ -r "$file" ] || return 1

    awk -F= -v key="$key" '
        $1 == key {
            gsub(/^[[:space:]"'\''"]+|[[:space:]"'\''"]+$/, "", $2)
            print $2
            exit
        }
    ' "$file"
}

detect_lang_code() {
    local explicit="${1:-}" candidate

    if candidate=$(normalize_lang_code "$explicit"); then
        translation_lang_code "$candidate"
        return 0
    fi

    for candidate in \
        "${LC_ALL:-}" \
        "${LC_MESSAGES:-}" \
        "${LANG:-}" \
        "$(locale_value_from_file "$HOME/.config/environment.d/10-locale.conf" LANG 2>/dev/null || true)" \
        "$(locale_value_from_file /etc/locale.conf LANG 2>/dev/null || true)" \
        "$(locale_value_from_file /etc/default/locale LANG 2>/dev/null || true)"; do
        if candidate=$(normalize_lang_code "$candidate"); then
            translation_lang_code "$candidate"
            return 0
        fi
    done

    printf 'en_US\n'
}

LANG_CODE="$(detect_lang_code "${1:-}")"
LOCALE_NAME="${LANG_CODE}.UTF-8"
TRANS_FILE="$HOME/.config/quickshell/ii/translations/${LANG_CODE}.json"
LANGUAGE_NAME="${LANG_CODE}:${LANG_CODE%%_*}"

# Run the updater itself under the selected UI locale so sudo/pkexec prompts
# and subprocess output use the same language immediately.
export LANG="$LOCALE_NAME"
export LC_TIME="$LOCALE_NAME"
export LC_CTYPE="$LOCALE_NAME"
export LC_MESSAGES="$LOCALE_NAME"
export LC_ALL="$LOCALE_NAME"
export LANGUAGE="$LANGUAGE_NAME"

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

# ── Conflict resolution ───────────────────────────────────────────────────────

is_conflict_error() {
    grep -qiE \
        'irrisolvab|irresolvable|unresolvable|non risolvib|nicht auflösbar|konflikt|conflict|conflit|conflitto|conflicto|conflicting.dep|package.conflict|failed to prepare|could not prepare|konnte nicht vorbereitet' \
        <<< "${1:-}"
}

is_conflict_line() {
    grep -q '::' <<< "${1:-}" \
        && grep -qiE 'konflikt|conflict|conflit|conflitto|conflicto' <<< "${1:-}"
}

# Strip epoch:version-pkgrel from a package+version string.
#   "python-materialyoucolor-3.0.2-1"              → "python-materialyoucolor"
#   "python-materialyoucolor-git-3.0.1.r1.gABC-1"  → "python-materialyoucolor-git"
strip_pkg_version() {
    printf '%s' "$1" | sed -E 's/-[0-9:][^[:space:]-]*(-[0-9]+)?$//'
}

# Print description, version, and reverse-deps for a package.
show_pkg_info() {
    local pkg="$1"
    if pacman -Qi "$pkg" &>/dev/null; then
        echo -e "  ${DIM}  Status:      installed${R}"
        LC_ALL=C pacman -Qi "$pkg" 2>/dev/null \
            | grep -E '^\s*(Description|Version|Required By|Install Reason)\s*:' \
            | sed 's/^[[:space:]]*//' \
            | while IFS= read -r line; do echo -e "  ${DIM}  ${line}${R}"; done
    else
        echo -e "  ${DIM}  Status:      not yet installed (incoming)${R}"
        { LC_ALL=C yay -Si "$pkg" 2>/dev/null || LC_ALL=C pacman -Si "$pkg" 2>/dev/null; } \
            | grep -E '^\s*(Description|Version|URL|Repository)\s*:' \
            | head -4 \
            | sed 's/^[[:space:]]*//' \
            | while IFS= read -r line; do echo -e "  ${DIM}  ${line}${R}"; done
    fi
}

append_unique() {
    local -n _arr="$1"
    local _value="$2" _existing

    [ -n "$_value" ] || return 0
    for _existing in "${_arr[@]:-}"; do
        [ "$_existing" = "$_value" ] && return 0
    done
    _arr+=("$_value")
}

pkg_required_by() {
    local pkg="$1" required

    required=$(LC_ALL=C pacman -Qi "$pkg" 2>/dev/null \
        | awk -F: '/^Required By/ {
            value=$2
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            print value
            exit
        }')
    [ -n "$required" ] || required="None"
    printf '%s\n' "$required"
}

pkg_install_reason() {
    local pkg="$1" reason

    reason=$(LC_ALL=C pacman -Qi "$pkg" 2>/dev/null \
        | awk -F: '/^Install Reason/ {
            value=$2
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            print value
            exit
        }')
    [ -n "$reason" ] || reason="unknown"
    printf '%s\n' "$reason"
}

pkg_satisfies_dependency() {
    local pkg="$1" dep="$2"
    local provides token name

    [ "$pkg" = "$dep" ] && return 0

    provides=$(LC_ALL=C pacman -Qi "$pkg" 2>/dev/null \
        | awk -F: '/^Provides/ {
            value=$2
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            print value
            exit
        }')
    [ -n "$provides" ] && [ "$provides" != "None" ] || return 1

    for token in $provides; do
        name="${token%%[<>=]*}"
        [ "$name" = "$dep" ] && return 0
    done

    return 1
}

add_skip_resolution() {
    local -n _skip_arr="$1"
    local installed="$2" incoming="$3"

    append_unique _skip_arr "$incoming"
    if pkg_satisfies_dependency "$installed" "$incoming"; then
        append_unique ASSUME_INSTALLED "${incoming}=9999:0-0"
        echo -e "  ${DIM}  ${installed} provides ${incoming}; adding --assume-installed for dependency solving.${R}"
    fi
}

# Apply the non-destructive half of remembered preferences before the first
# package-manager attempt. If the preferred package is already installed, its
# known alternative can be ignored immediately instead of making pacman rediscover
# the same conflict (and possibly show its own replacement prompt) every run.
prime_conflict_preferences() {
    local key pkg_a pkg_b preferred alternative

    [ "$CONFLICT_PREFERENCES_PRIMED" -eq 0 ] || return 0
    CONFLICT_PREFERENCES_PRIMED=1
    load_conflict_preferences

    for key in "${!CONFLICT_PREFERENCES[@]}"; do
        IFS=$'\x1f' read -r pkg_a pkg_b <<< "$key"
        preferred="${CONFLICT_PREFERENCES[$key]}"
        if [ "$preferred" = "$pkg_a" ]; then
            alternative="$pkg_b"
        else
            alternative="$pkg_a"
        fi

        if pacman -Q "$preferred" >/dev/null 2>&1 \
            && ! pacman -Q "$alternative" >/dev/null 2>&1; then
            add_skip_resolution SKIP_PKGS "$preferred" "$alternative"
        fi
    done
}

conflict_recommendation() {
    local installed="$1" incoming="$2"
    local required reason

    required=$(pkg_required_by "$installed")
    if [ -n "$required" ] && [ "$required" != "None" ]; then
        printf 'skip\t%s is required by: %s\n' "$installed" "$required"
        return 0
    fi

    reason=$(pkg_install_reason "$installed")
    case "${reason,,}" in
        *dependency*)
            printf 'remove\t%s is not required by another installed package; replacing it should unblock the transaction\n' "$installed"
            ;;
        *)
            printf 'remove\t%s has no reverse dependencies; replacing it with %s is usually the cleanest fix\n' "$installed" "$incoming"
            ;;
    esac
}

remove_conflict_package() {
    local pkg="$1"
    local required confirm

    required=$(pkg_required_by "$pkg")
    if [ -n "$required" ] && [ "$required" != "None" ]; then
        echo
        echo -e "  ${WARN}  ${YELLOW}${pkg} is required by: ${required}${R}"
        echo -e "  ${WARN}  ${YELLOW}Force-removing it may temporarily break those packages until the replacement transaction succeeds.${R}"

        if [ ! -t 0 ]; then
            echo -e "  ${FAIL}  ${RED}No interactive terminal available to confirm forced removal.${R}"
            return 1
        fi

        read -rp "  Type 'REMOVE ${pkg}' to force-remove it, or press Enter to abort: " confirm
        if [ "$confirm" != "REMOVE ${pkg}" ]; then
            echo -e "  ${WARN}  ${YELLOW}Removal cancelled.${R}"
            return 1
        fi

        priv pacman -Rdd --noconfirm "$pkg" 2>&1 | sed 's/^/    /'
        return "${PIPESTATUS[0]}"
    fi

    if priv pacman -Rns --noconfirm "$pkg" 2>&1 | sed 's/^/    /'; then
        return 0
    fi

    echo -e "  ${WARN}  ${YELLOW}Normal removal failed; trying forced removal for ${pkg}.${R}"
    priv pacman -Rdd --noconfirm "$pkg" 2>&1 | sed 's/^/    /'
    return "${PIPESTATUS[0]}"
}

# Parse yay/pacman output for conflict lines.
# Prints "installed_pkg:incoming_pkg" pairs (deduplicated).
extract_conflicts() {
    local output="$1"
    local -a seen=()

    while IFS= read -r line; do
        is_conflict_line "$line" || continue

        local remove_pkg after tok1 tok3 pkg1 pkg2

        # Language-agnostic: extract the package pacman asks to Remove, when
        # pacman offers a direct removal prompt.
        remove_pkg=$(printf '%s' "$line" | grep -oP \
            '(?i)(?:Remove|Rimuovere|Supprimer|Entfernen|Verwijderen|Eliminar)\s+\K[a-z0-9@._+][a-z0-9@._+\-]*(?=\?)')

        # The two conflicting packages (with versions) follow "::". The second
        # field is a localized conjunction ("and", "und", "e", "et", etc.).
        after=$(printf '%s' "$line" | sed 's/^.*::[[:space:]]*//')
        tok1=$(printf '%s' "$after" | awk '{print $1}')
        tok3=$(printf '%s' "$after" | awk '{print $3}')
        [ -n "$tok1" ] && [ -n "$tok3" ] || continue

        pkg1=$(strip_pkg_version "$tok1")
        pkg2=$(strip_pkg_version "$tok3")
        [ -n "$pkg1" ] && [ -n "$pkg2" ] || continue

        local installed incoming
        if [ -n "$remove_pkg" ]; then
            # installed = the one pacman wants to remove; incoming = the other
            if   [ "$remove_pkg" = "$pkg1" ]; then installed="$pkg1"; incoming="$pkg2"
            elif [ "$remove_pkg" = "$pkg2" ]; then installed="$pkg2"; incoming="$pkg1"
            else                                   installed="$remove_pkg"; incoming="$pkg1"
            fi
        elif pacman -Q "$pkg1" >/dev/null 2>&1 && ! pacman -Q "$pkg2" >/dev/null 2>&1; then
            installed="$pkg1"
            incoming="$pkg2"
        elif pacman -Q "$pkg2" >/dev/null 2>&1 && ! pacman -Q "$pkg1" >/dev/null 2>&1; then
            installed="$pkg2"
            incoming="$pkg1"
        else
            installed="$pkg1"
            incoming="$pkg2"
        fi

        local key="${installed}:${incoming}"
        local dup=0
        for s in "${seen[@]:-}"; do [ "$s" = "$key" ] && dup=1 && break; done
        [ "$dup" -eq 1 ] && continue
        seen+=("$key")
        printf '%s\n' "$key"
    done <<< "$output"
}

# Interactive conflict resolution menu.
# Sets CONFLICT_NEW_DECISION=1 if any pair required user input; 0 if all were auto-applied.
resolve_conflicts() {
    local -a pairs=("$@")
    local -a to_remove=() to_skip=()
    CONFLICT_NEW_DECISION=0
    CONFLICT_ABORT=0
    load_conflict_preferences

    for pair in "${pairs[@]}"; do
        local installed="${pair%%:*}"
        local incoming="${pair##*:}"
        local _dkey="${installed}:${incoming}"
        local _pkey
        _pkey=$(conflict_pair_key "$installed" "$incoming")

        # First honour a one-run decision. This prevents duplicate prompts when
        # pacman and the AUR helper report the same pair in one update session.
        if [ -n "${CONFLICT_DECISIONS[$_dkey]+x}" ]; then
            echo -e "\n  ${DIM}Reusing this run's decision for ${WHITE}${installed}${R}${DIM} ↔ ${CYAN}${incoming}${R}${DIM}: ${CONFLICT_DECISIONS[$_dkey]}${R}"
            case "${CONFLICT_DECISIONS[$_dkey]}" in
                skip)
                    add_skip_resolution to_skip "$installed" "$incoming"
                    ;;
                remove) append_unique to_remove "$installed" ;;
            esac
            continue
        fi

        # Persistent choices name the preferred package, rather than an action.
        # That remains correct if a future pacman message presents the pair in
        # the opposite order.
        if [ -n "${CONFLICT_PREFERENCES[$_pkey]+x}" ]; then
            local preferred="${CONFLICT_PREFERENCES[$_pkey]}"
            echo
            echo -e "  ${GREEN}${BOLD}✓ Remembered package preference${R}"
            echo -e "  ${DIM}${WHITE}${installed}${R}${DIM} ↔ ${CYAN}${incoming}${R}${DIM}: prefer ${BOLD}${preferred}${R}"
            echo -e "  ${DIM}Change it with: $0 --forget-conflict ${installed} ${incoming}${R}"

            if [ "$preferred" = "$installed" ]; then
                add_skip_resolution to_skip "$installed" "$incoming"
            else
                append_unique to_remove "$installed"
            fi
            continue
        fi

        CONFLICT_NEW_DECISION=1
        local recommendation rec_reason default_choice keep_note replace_note
        IFS=$'\t' read -r recommendation rec_reason < <(conflict_recommendation "$installed" "$incoming")
        case "$recommendation" in
            remove)
                default_choice=2
                keep_note=""
                replace_note=" ${GREEN}· recommended${R}"
                ;;
            *)
                default_choice=1
                keep_note=" ${GREEN}· recommended${R}"
                replace_note=""
                ;;
        esac

        echo
        echo -e "  ${RED}${BOLD}⚡ Package conflict${R}"
        echo -e "  ${DIM}  ─────────────────────────────────────────────────────────${R}"
        echo
        echo -e "  ${BOLD}${WHITE}${installed}${R}  ${DIM}(currently installed)${R}"
        show_pkg_info "$installed"
        echo
        echo -e "  ${BOLD}${CYAN}${incoming}${R}  ${DIM}(incoming — conflicts with installed)${R}"
        show_pkg_info "$incoming"
        echo
        echo -e "  ${BOLD}Recommended course of action:${R}"
        if [ "$recommendation" = "remove" ]; then
            echo -e "  ${GREEN}Remove ${WHITE}${installed}${R}${GREEN}, then rerun pacman so ${CYAN}${incoming}${R}${GREEN} can be installed/upgraded.${R}"
        else
            echo -e "  ${GREEN}Keep ${WHITE}${installed}${R}${GREEN} and skip ${CYAN}${incoming}${R}${GREEN} for this run.${R}"
        fi
        echo -e "  ${DIM}Reason: ${rec_reason}${R}"
        echo
        echo -e "  ${DIM}Remembered preferences apply only to this exact package pair and can be reviewed later.${R}"
        echo

        local choice
        while true; do
            echo -e "  ${BOLD}Remember my preference${R}"
            echo -e "  ${GREEN}1)${R} Prefer ${WHITE}${installed}${R} — automatically skip ${CYAN}${incoming}${R} when this pair conflicts${keep_note}"
            echo -e "  ${GREEN}2)${R} Prefer ${CYAN}${incoming}${R} — automatically replace ${WHITE}${installed}${R} when this pair conflicts${replace_note}"
            echo
            echo -e "  ${BOLD}Just this update${R}"
            echo -e "  ${GREEN}3)${R} Keep ${WHITE}${installed}${R} this time"
            echo -e "  ${GREEN}4)${R} Replace ${WHITE}${installed}${R} this time"
            echo -e "  ${GREEN}5)${R} Abort package updates"

            if [ ! -t 0 ]; then
                choice=3
                echo -e "  ${DIM}No interactive terminal; safely keeping ${installed} for this run without saving a preference.${R}"
            else
                read -rp "  Choice [${default_choice}]: " choice
                choice="${choice:-$default_choice}"
            fi

            case "$choice" in
                1)
                    add_skip_resolution to_skip "$installed" "$incoming"
                    CONFLICT_DECISIONS[$_dkey]="skip"
                    if remember_conflict_preference "$installed" "$incoming" "$installed"; then
                        echo -e "  ${PASS}  ${GREEN}Preference saved: prefer ${installed}.${R}"
                    else
                        echo -e "  ${WARN}  ${YELLOW}Could not save the preference; it will apply only to this run.${R}"
                    fi
                    break
                    ;;
                2)
                    append_unique to_remove "$installed"
                    CONFLICT_DECISIONS[$_dkey]="remove"
                    if remember_conflict_preference "$installed" "$incoming" "$incoming"; then
                        echo -e "  ${PASS}  ${GREEN}Preference saved: prefer ${incoming}.${R}"
                    else
                        echo -e "  ${WARN}  ${YELLOW}Could not save the preference; it will apply only to this run.${R}"
                    fi
                    break
                    ;;
                3)
                    add_skip_resolution to_skip "$installed" "$incoming"
                    CONFLICT_DECISIONS[$_dkey]="skip"
                    break
                    ;;
                4)
                    append_unique to_remove "$installed"
                    CONFLICT_DECISIONS[$_dkey]="remove"
                    break
                    ;;
                5)
                    CONFLICT_ABORT=1
                    return 1
                    ;;
                *) echo -e "  ${WARN}  Please enter 1, 2, 3, 4, or 5." ;;
            esac
        done
    done

    if [ ${#to_remove[@]} -gt 0 ]; then
        echo
        echo -e "  ${WARN}  ${YELLOW}Removing: ${to_remove[*]}${R}"
        local _pkg
        for _pkg in "${to_remove[@]}"; do
            if ! remove_conflict_package "$_pkg"; then
                CONFLICT_ABORT=1
                return 1
            fi
        done
    fi
    for p in "${to_skip[@]}"; do append_unique SKIP_PKGS "$p"; done
    return 0
}

# ── pacman updates ────────────────────────────────────────────────────────────

run_visible_capture() {
    local __outvar="$1" tmp rc captured
    shift

    tmp=$(mktemp -t update-output.XXXXXX) || return 1
    "$@" 2>&1 | tee "$tmp"
    rc=${PIPESTATUS[0]}
    captured=$(cat "$tmp" 2>/dev/null || true)
    rm -f "$tmp"
    printf -v "$__outvar" '%s' "$captured"
    return "$rc"
}

run_pacman_updates() {
    section "${T[PACMAN]}"

    if ! command -v pacman >/dev/null 2>&1; then
        skip "pacman"
        return 0
    fi

    prime_conflict_preferences

    local rc captured loop ok
    local -a ignore_args assume_args pairs

    ignore_args=()
    for p in "${SKIP_PKGS[@]:-}"; do
        [ -n "$p" ] && ignore_args+=(--ignore "$p")
    done
    assume_args=()
    for p in "${ASSUME_INSTALLED[@]:-}"; do
        [ -n "$p" ] && assume_args+=(--assume-installed "$p")
    done

    if run_visible_capture captured priv pacman -Syu "${ignore_args[@]}" "${assume_args[@]}"; then
        ok "pacman"
        return 0
    fi

    if is_conflict_error "$captured"; then
        echo -e "\n  ${WARN}  ${YELLOW}Detected a pacman package conflict in the failed transaction.${R}"
    else
        echo -e "\n  ${DIM}Analysing pacman failure...${R}"
        captured=$(LC_ALL=C priv pacman -Syu --noconfirm --noprogressbar --print \
            "${ignore_args[@]}" "${assume_args[@]}" 2>&1 || true)
    fi

    if ! is_conflict_error "$captured"; then
        fail "pacman"
        return 1
    fi

    ok=0
    loop=0
    while is_conflict_error "$captured"; do
        loop=$((loop + 1))
        [ "$loop" -gt 10 ] && break

        pairs=()
        while IFS= read -r _p; do
            [ -n "$_p" ] && pairs+=("$_p")
        done < <(extract_conflicts "$captured")

        if [ "${#pairs[@]}" -eq 0 ]; then
            echo
            echo -e "  ${WARN}  ${YELLOW}pacman reported a conflict, but it could not be parsed automatically.${R}"
            break
        fi

        if ! resolve_conflicts "${pairs[@]}"; then
            echo
            echo -e "  ${WARN}  ${YELLOW}pacman conflict handling was aborted.${R}"
            break
        fi

        ignore_args=()
        for _p in "${SKIP_PKGS[@]:-}"; do
            [ -n "$_p" ] && ignore_args+=(--ignore "$_p")
        done
        assume_args=()
        for _p in "${ASSUME_INSTALLED[@]:-}"; do
            [ -n "$_p" ] && assume_args+=(--assume-installed "$_p")
        done

        echo
        echo -e "  ${DIM}Re-running pacman after conflict resolution...${R}"
        run_visible_capture captured priv pacman -Syu "${ignore_args[@]}" "${assume_args[@]}"
        rc=$?
        if [ "$rc" -eq 0 ]; then
            ok=1
            break
        fi

        if ! is_conflict_error "$captured"; then
            echo -e "\n  ${DIM}Re-analysing pacman failure...${R}"
            captured=$(LC_ALL=C priv pacman -Syu --noconfirm --noprogressbar --print \
                "${ignore_args[@]}" "${assume_args[@]}" 2>&1 || true)
        fi

        if ! is_conflict_error "$captured"; then
            echo
            echo -e "  ${WARN}  ${YELLOW}pacman still failed, but not with a parseable package conflict.${R}"
            break
        fi

        if [ "$CONFLICT_NEW_DECISION" -eq 0 ]; then
            echo
            echo -e "  ${WARN}  ${YELLOW}pacman conflict persists even with the stored decision applied.${R}"
            break
        fi

        echo -e "\n  ${DIM}New conflict still present; prompting again if needed...${R}"
    done

    [ "$ok" -eq 1 ] && ok "pacman" || fail "pacman"
}

# ── AUR updates ───────────────────────────────────────────────────────────────

run_aur_updates() {
    local helper title rc attempt delay captured
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

    prime_conflict_preferences

    # Build --ignore flags from any packages the user chose to skip
    local -a ignore_args=()
    for p in "${SKIP_PKGS[@]:-}"; do
        [ -n "$p" ] && ignore_args+=(--ignore "$p")
    done

    # Phase 1: run interactively so the user sees all yay output.
    # yay writes progress/prompts to /dev/tty (not stdout/stderr), so we
    # cannot capture it here — we only check the exit code.
    captured=""
    for attempt in 1 2 3; do
        "$helper" -Sua --devel --noconfirm "${ignore_args[@]}"
        rc=$?
        [ $rc -eq 0 ] && { ok "$helper"; return 0; }

        # Phase 2: re-run with flags that suppress yay's own interactive prompts
        # (diff viewer, clean-build questions).  Without those prompts yay writes
        # to stdout/stderr instead of /dev/tty, so we can capture and analyse it.
        echo -e "\n  ${DIM}Analysing failure...${R}"
        captured=$(LC_ALL=C "$helper" -Sua --devel --noconfirm \
            --answerdiff=None --answerclean=None --answeredit=None --noprogressbar \
            "${ignore_args[@]}" 2>&1 || true)

        if is_rate_limited "$captured"; then
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

        break  # Non-rate-limit error — fall through to conflict resolution
    done

    if is_conflict_error "$captured"; then
        PENDING_AUR_HELPER="$helper"
        PENDING_AUR_CAPTURED="$captured"
        PENDING_AUR_IGNORE_ARGS=("${ignore_args[@]}")
        echo -e "  ${WARN}  ${YELLOW}Package conflict detected — deferring resolution to end of update run.${R}"
        return 0
    fi

    fail "$helper"
    return 1
}

choose_update_plan() {
    local pkg choice

    detect_reboot_sensitive_updates
    [ "${#REBOOT_UPDATE_PACKAGES[@]}" -gt 0 ] || return 0

    section "Restart-aware update plan"
    echo -e "  ${WARN}  ${YELLOW}${BOLD}A reboot-sensitive system update is waiting.${R}"
    echo
    for pkg in "${REBOOT_UPDATE_PACKAGES[@]}"; do
        echo -e "  ${YELLOW}●${R} ${WHITE}${pkg}${R}  ${DIM}${REBOOT_PACKAGE_VERSIONS_BEFORE[$pkg]:-installed}${R}"
    done
    echo
    echo -e "  ${DIM}Kernel, graphics-driver, firmware, and microcode packages only become fully active after reboot.${R}"
    echo -e "  ${DIM}Arch repository packages must stay in one complete transaction, so the updater will not create${R}"
    echo -e "  ${DIM}an unsafe partial upgrade by separating pacman applications from these system packages.${R}"
    echo
    echo -e "  ${BOLD}Choose an update plan${R}"
    echo -e "  ${GREEN}1)${R} Apps first, then full system update  ${GREEN}· recommended${R}"
    echo -e "     ${DIM}Update Flatpak apps, then Arch/AUR together; offer a reboot when finished.${R}"
    echo -e "  ${GREEN}2)${R} Apps only for now"
    echo -e "     ${DIM}Update independent Flatpak apps and defer the complete Arch/AUR update.${R}"
    echo -e "  ${GREEN}3)${R} Cancel"

    if [ ! -t 0 ]; then
        UPDATE_PLAN="apps-only"
        echo -e "  ${DIM}No interactive terminal; choosing apps only and deferring the system transaction.${R}"
        return 0
    fi

    while true; do
        read -rp "  Choice [1]: " choice
        choice="${choice:-1}"
        case "$choice" in
            1)
                UPDATE_PLAN="full"
                return 0
                ;;
            2)
                UPDATE_PLAN="apps-only"
                return 0
                ;;
            3)
                UPDATE_PLAN="cancel"
                return 0
                ;;
            *)
                echo -e "  ${WARN}  ${YELLOW}Please enter 1, 2, or 3.${R}"
                ;;
        esac
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
elif [[ "$LANG_CODE" == de_* ]]; then
echo ' █████╗ ██╗  ██╗████████╗██╗   ██╗ █████╗ ██╗      ██╗███████╗██╗███████╗██████╗ ███████╗███╗   ██╗'
echo '██╔══██╗██║ ██╔╝╚══██╔══╝██║   ██║██╔══██╗██║      ██║██╔════╝██║██╔════╝██╔══██╗██╔════╝████╗  ██║'
echo '███████║█████╔╝    ██║   ██║   ██║███████║██║      ██║███████╗██║█████╗  ██████╔╝█████╗  ██╔██╗ ██║'
echo '██╔══██║██╔═██╗    ██║   ██║   ██║██╔══██║██║      ██║╚════██║██║██╔══╝  ██╔══██╗██╔══╝  ██║╚██╗██║'
echo '██║  ██║██║  ██╗   ██║   ╚██████╔╝██║  ██║███████╗ ██║███████║██║███████╗██║  ██║███████╗██║ ╚████║'
echo '╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚══════╝ ╚═╝╚══════╝╚═╝╚══════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝'
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
if ! TOTAL=$(count_updates); then
    echo -e "  ${FAIL}  ${RED}Could not query package updates; no changes were made.${R}"
    exit 1
fi
if [ "$TOTAL" -eq 0 ]; then
    echo -e "  ${PASS}  ${GREEN}${T[UP_TO_DATE]}${R}"
else
    msg="${T[AVAILABLE]//%1/$TOTAL}"
    echo -e "  ${WARN}  ${YELLOW}${BOLD}${msg}${R}"
fi

choose_update_plan
if [ "$UPDATE_PLAN" = "cancel" ]; then
    echo
    echo -e "  ${DIM}Update cancelled; no packages were changed.${R}"
    exit 0
fi

# Flatpak has its own runtime and repository model, so it is safe to update
# before (or independently from) the native Arch transaction.
section "Apps — ${T[FLATPAK]}"
run_pkg "flatpak" flatpak update -y

# ── Auth ──────────────────────────────────────────────────────────────────────
USE_SUDO=1
if [ "$UPDATE_PLAN" = "full" ]; then
    section "${T[AUTH]}"
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
else
    SKIPPED+=("Arch system and AUR updates (deferred together)")
fi

priv() {
    if [ "$USE_SUDO" -eq 1 ]; then sudo "$@"; else pkexec "$@"; fi
}

VMWARE_WORKSTATION_BEFORE=""
VMWARE_HOST_MODULES_PKG_BEFORE=""
VMWARE_HOST_MODULES_BEFORE=""
KERNEL_BEFORE=""
KERNEL_HEADERS_BEFORE=""
if [ "$UPDATE_PLAN" = "full" ]; then
    VMWARE_WORKSTATION_BEFORE=$(package_version vmware-workstation || true)
    VMWARE_HOST_MODULES_PKG_BEFORE=$(detect_vmware_host_modules_pkg || true)
    if [ -n "$VMWARE_HOST_MODULES_PKG_BEFORE" ]; then
        VMWARE_HOST_MODULES_BEFORE=$(package_version "$VMWARE_HOST_MODULES_PKG_BEFORE" || true)
    fi
    KERNEL_BEFORE=$(package_version linux || true)
    KERNEL_HEADERS_BEFORE=$(package_version linux-headers || true)
fi

if [ "$UPDATE_PLAN" = "full" ]; then
    # Arch repository packages stay together in one full system transaction.
    run_pacman_updates
    run_aur_updates
fi

# ── quickshell (rebuild from source) ─────────────────────────────────────────
rebuild_quickshell() {
    section "quickshell — source rebuild"

    local qs_pkg build_dir git_dir helper compat_output behind rebuild_needed rebuild_reason
    local package_bin resolved_bin
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
    package_bin="/usr/bin/quickshell"
    resolved_bin=$(command -v quickshell 2>/dev/null || true)

    if [ -x "$package_bin" ]; then
        compat_output=$("$package_bin" --private-check-compat 2>&1 || true)
        if [ -n "$compat_output" ]; then
            printf '%s\n' "$compat_output"
        fi
        if ! "$package_bin" --private-check-compat >/dev/null 2>&1; then
            rebuild_needed=1
            rebuild_reason="packaged Qt compatibility mismatch"
        fi
    fi

    if [ -n "$resolved_bin" ] && [ "$resolved_bin" != "$package_bin" ]; then
        compat_output=$("$resolved_bin" --private-check-compat 2>&1 || true)
        if [ -n "$compat_output" ]; then
            printf '%s\n' "$compat_output"
        fi
        if ! "$resolved_bin" --private-check-compat >/dev/null 2>&1; then
            rebuild_needed=1
            if [ -n "$rebuild_reason" ]; then
                rebuild_reason="${rebuild_reason}; wrapper compatibility mismatch"
            else
                rebuild_reason="wrapper compatibility mismatch"
            fi
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
        sync_quickshell_user_local "" >/dev/null 2>&1 || true
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

    if sync_quickshell_user_local "$build_dir"; then
        echo -e "  ${PASS}  ${GREEN}synced user-local quickshell binary${R}"
    else
        echo -e "  ${WARN}  ${YELLOW}could not sync user-local quickshell binary${R}"
    fi

    if [ -x "$package_bin" ] && "$package_bin" --private-check-compat >/dev/null 2>&1 \
        && command -v quickshell >/dev/null 2>&1 && quickshell --private-check-compat >/dev/null 2>&1; then
        ok "quickshell"
    else
        fail "quickshell"
        return 1
    fi
}

if [ "$UPDATE_PLAN" = "full" ]; then
    rebuild_quickshell
fi

# ── VMware (host modules rebuild) ────────────────────────────────────────────
repair_vmware() {
    section "VMware — host modules"

    local workstation_after host_pkg_after host_after kernel_after headers_after kernel_release_after
    local repair_needed repair_reason build_dir helper vmware_branch vmware_repo branch_ref
    local workstation_dkms_version dkms_state legacy_module legacy_line legacy_version
    local build_tmp module_dir

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
    kernel_release_after=$(uname -r)
    workstation_dkms_version=$(find_vmware_workstation_dkms_version 2>/dev/null || true)

    echo -e "  ${DIM}Detected: vmware-workstation ${workstation_after}${R}"
    if [ -n "$workstation_dkms_version" ]; then
        echo -e "  ${DIM}Workstation DKMS: vmware-workstation/${workstation_dkms_version}${R}"
    fi
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

    if [ -n "$host_pkg_after" ] && [ -n "$workstation_dkms_version" ]; then
        repair_needed=1
        if [ -n "$repair_reason" ]; then
            repair_reason="${repair_reason}; legacy host modules package installed"
        else
            repair_reason="legacy host modules package installed"
        fi
    fi

    if [ -n "$workstation_dkms_version" ] && command -v dkms >/dev/null 2>&1; then
        dkms_state=$(dkms status -m vmware-workstation -v "$workstation_dkms_version" 2>/dev/null || true)
        if ! grep -q "${kernel_release_after}.*installed" <<<"$dkms_state" || grep -qiE 'Differences|broken|bad|added' <<<"$dkms_state"; then
            repair_needed=1
            if [ -n "$repair_reason" ]; then
                repair_reason="${repair_reason}; Workstation DKMS needs reinstall"
            else
                repair_reason="Workstation DKMS needs reinstall"
            fi
        fi
    fi

    if [ "$repair_needed" -eq 0 ]; then
        echo -e "  ${PASS}  ${GREEN}VMware modules look unchanged — no repair needed${R}"
        return 0
    fi

    echo -e "  ${WARN}  ${YELLOW}Repairing VMware modules: ${repair_reason}${R}"

    if [ -n "$workstation_dkms_version" ]; then
        if [ -n "$host_pkg_after" ]; then
            echo -e "  ${WARN}  ${YELLOW}Removing obsolete ${host_pkg_after}; vmware-workstation now provides matching DKMS modules.${R}"
            if ! priv pacman -Rns --noconfirm "$host_pkg_after"; then
                fail "vmware"
                return 1
            fi
        fi

        for legacy_module in vmmon vmnet; do
            while IFS= read -r legacy_line; do
                legacy_version=${legacy_line#${legacy_module}/}
                legacy_version=${legacy_version%%,*}
                [ -n "$legacy_version" ] || continue
                echo -e "  ${DIM}Removing legacy DKMS entry: ${legacy_module}/${legacy_version}${R}"
                priv dkms remove -m "$legacy_module" -v "$legacy_version" --all >/dev/null 2>&1 || true
            done < <(dkms status -m "$legacy_module" 2>/dev/null || true)
        done

        echo -e "  ${DIM}Installing vmware-workstation DKMS for ${kernel_release_after}${R}"
        if priv dkms install -m vmware-workstation -v "$workstation_dkms_version" -k "$kernel_release_after" --force \
            && priv depmod -a "$kernel_release_after"; then
            :
        else
            fail "vmware"
            return 1
        fi
    else
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
            module_dir="/lib/modules/${kernel_release_after}/updates/dkms"

            if git -C "$vmware_repo" archive "$branch_ref" | tar -x -C "$build_tmp" \
                && git -C "$vmware_repo" archive -o "$build_tmp/vmmon.tar" "$branch_ref" vmmon-only \
                && git -C "$vmware_repo" archive -o "$build_tmp/vmnet.tar" "$branch_ref" vmnet-only \
                && make VM_UNAME="$kernel_release_after" -C "$build_tmp" \
                && zstd -f "$build_tmp/vmmon-only/vmmon.ko" -o "$build_tmp/vmmon.ko.zst" \
                && zstd -f "$build_tmp/vmnet-only/vmnet.ko" -o "$build_tmp/vmnet.ko.zst" \
                && priv install -d "$module_dir" /usr/lib/vmware/modules/source \
                && priv install -m 0644 "$build_tmp/vmmon.ko.zst" "$module_dir/vmmon.ko.zst" \
                && priv install -m 0644 "$build_tmp/vmnet.ko.zst" "$module_dir/vmnet.ko.zst" \
                && priv install -m 0644 "$build_tmp/vmmon.tar" /usr/lib/vmware/modules/source/vmmon.tar \
                && priv install -m 0644 "$build_tmp/vmnet.tar" /usr/lib/vmware/modules/source/vmnet.tar \
                && priv depmod -a "$kernel_release_after"; then
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

if [ "$UPDATE_PLAN" = "full" ]; then
    repair_vmware
fi

hyprland_binary_replaced() {
    local pid exe

    while IFS= read -r pid; do
        [ -n "$pid" ] || continue
        exe=$(readlink "/proc/$pid/exe" 2>/dev/null || true)
        case "$exe" in
            *"(deleted)"*) return 0 ;;
        esac
    done < <(pgrep -x Hyprland 2>/dev/null || true)

    return 1
}

check_post_update_runtime() {
    section "Post-update runtime"

    local running_kernel installed_kernel loaded_nvidia installed_nvidia

    running_kernel=$(uname -r)
    installed_kernel=$(installed_linux_release 2>/dev/null || true)

    if [ -n "$installed_kernel" ] && [ "$running_kernel" != "$installed_kernel" ]; then
        mark_reboot_required "running kernel ${running_kernel}, installed kernel ${installed_kernel}"
        echo -e "  ${WARN}  ${YELLOW}Kernel package changed; reboot required to load ${installed_kernel}.${R}"
    else
        echo -e "  ${PASS}  ${GREEN}running kernel matches installed linux package${R}"
    fi

    loaded_nvidia=$(loaded_nvidia_version 2>/dev/null || true)
    installed_nvidia=$(package_upstream_version nvidia-utils 2>/dev/null || true)
    if [ -n "$loaded_nvidia" ] && [ -n "$installed_nvidia" ]; then
        if [ "$loaded_nvidia" != "$installed_nvidia" ]; then
            mark_reboot_required "loaded NVIDIA kernel module ${loaded_nvidia}, installed userspace ${installed_nvidia}"
            echo -e "  ${WARN}  ${YELLOW}NVIDIA API mismatch detected; reboot required before Hyprland can start reliably.${R}"
        else
            echo -e "  ${PASS}  ${GREEN}NVIDIA userspace and loaded kernel module match${R}"
        fi
    else
        echo -e "  ${DIM}  –  NVIDIA module not loaded or nvidia-utils not installed${R}"
    fi

    if hyprland_binary_replaced; then
        mark_reboot_required "running Hyprland binary was replaced during the update"
        echo -e "  ${WARN}  ${YELLOW}Running Hyprland binary was replaced; clean restart/reboot required.${R}"
    else
        echo -e "  ${PASS}  ${GREEN}running Hyprland binary is not deleted/replaced${R}"
    fi

    if [ "$REBOOT_REQUIRED" -eq 1 ]; then
        echo
        echo -e "  ${WARN}  ${YELLOW}${BOLD}A reboot is required to finish this update safely.${R}"
        for reason in "${REBOOT_REASONS[@]}"; do
            echo -e "  ${DIM}  • ${reason}${R}"
        done
    fi
}

prompt_reboot_if_required() {
    local choice

    [ "$REBOOT_REQUIRED" -eq 1 ] || return 0

    echo
    if [ "${UPDATE_AUTO_REBOOT:-0}" = "1" ] || [ "${AG_UPDATE_AUTO_REBOOT:-0}" = "1" ]; then
        echo -e "  ${WARN}  ${YELLOW}Auto-reboot enabled; rebooting now.${R}"
        priv systemctl reboot
        return 0
    fi

    read -rp "  Reboot now to finish the update safely? [y/N]: " choice
    case "$choice" in
        y|Y|yes|YES)
            priv systemctl reboot
            ;;
        *)
            echo -e "  ${WARN}  ${YELLOW}Reboot deferred. Hyprland/NVIDIA may remain unstable until reboot.${R}"
            ;;
    esac
}

# ── Deferred AUR conflict resolution ─────────────────────────────────────────
if [ "$UPDATE_PLAN" = "full" ] && [ -n "$PENDING_AUR_HELPER" ]; then
    section "Conflict Resolution — ${PENDING_AUR_HELPER}"
    _def_captured="$PENDING_AUR_CAPTURED"
    _def_ignore=("${PENDING_AUR_IGNORE_ARGS[@]}")
    _def_ok=0
    _def_loop=0

    while is_conflict_error "$_def_captured"; do
        _def_loop=$((_def_loop + 1))
        [ "$_def_loop" -gt 10 ] && break

        _def_pairs=()
        while IFS= read -r _p; do [ -n "$_p" ] && _def_pairs+=("$_p"); done \
            < <(extract_conflicts "$_def_captured")
        [ "${#_def_pairs[@]}" -eq 0 ] && break

        if ! resolve_conflicts "${_def_pairs[@]}"; then
            echo
            echo -e "  ${WARN}  ${YELLOW}${PENDING_AUR_HELPER} conflict handling was aborted.${R}"
            break
        fi

        _def_ignore=()
        for _p in "${SKIP_PKGS[@]:-}"; do [ -n "$_p" ] && _def_ignore+=(--ignore "$_p"); done
        _def_assume=()
        for _p in "${ASSUME_INSTALLED[@]:-}"; do [ -n "$_p" ] && _def_assume+=(--assume-installed "$_p"); done

        echo
        echo -e "  ${DIM}Re-running ${PENDING_AUR_HELPER} after conflict resolution...${R}"
        "$PENDING_AUR_HELPER" -Sua --devel --noconfirm "${_def_ignore[@]}" "${_def_assume[@]}"
        _def_rc=$?

        if [ "$_def_rc" -eq 0 ]; then
            _def_ok=1
            break
        fi

        # If resolve_conflicts made no new decisions (all were auto-applied from stored
        # decisions) and the run still failed, the conflict is unresolvable.
        if [ "$CONFLICT_NEW_DECISION" -eq 0 ]; then
            echo
            echo -e "  ${WARN}  ${YELLOW}Conflict persists even with --ignore and --assume-installed.${R}"
            echo -e "  ${DIM}  Consider option 2 (replace installed with incoming) to unblock updates.${R}"
            break
        fi

        echo -e "\n  ${DIM}Re-analysing failure...${R}"
        _def_captured=$(LC_ALL=C "$PENDING_AUR_HELPER" -Sua --devel --noconfirm \
            --answerdiff=None --answerclean=None --answeredit=None --noprogressbar \
            "${_def_ignore[@]}" "${_def_assume[@]}" 2>&1 || true)
    done

    [ "$_def_ok" -eq 1 ] && ok "$PENDING_AUR_HELPER" || fail "$PENDING_AUR_HELPER"
fi

if [ "$UPDATE_PLAN" = "full" ]; then
    mark_updated_reboot_packages
    check_post_update_runtime
fi

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
    prompt_reboot_if_required
    read -rp "  ${T[PRESS_ENTER]}"
    exit 1
fi

echo
if [ "$UPDATE_PLAN" = "apps-only" ]; then
    echo -e "  ${GREEN}${BOLD}  ✔  App updates finished.${R}"
    echo -e "  ${DIM}     Arch system and AUR updates remain grouped and ready for a later full update.${R}"
else
    echo -e "  ${GREEN}${BOLD}  ✔  ${T[ALL_DONE]}${R}"
fi
echo
[ "$UPDATE_PLAN" = "full" ] && prompt_reboot_if_required
read -rp "  ${T[PRESS_ENTER]}"
