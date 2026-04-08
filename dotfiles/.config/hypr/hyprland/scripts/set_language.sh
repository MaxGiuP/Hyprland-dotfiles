#!/usr/bin/env bash
# Non-interactive version of language_select.sh.
# Usage: set_language.sh <lang_code>   e.g. set_language.sh it_IT
set -euo pipefail

if [[ $# -lt 1 || -z "$1" ]]; then
  echo "Usage: $(basename "$0") <lang_code>" >&2
  exit 1
fi

lang="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_CONF="$(cd "$SCRIPT_DIR/.." && pwd)/env.conf"

LOCALE_NAME="${lang}.UTF-8"
LOCALE_ENTRY="${LOCALE_NAME} UTF-8"

LOCALE_CONF="/etc/locale.conf"
ENV_SYSTEM="/etc/environment"
DEFAULT_LOCALE="/etc/default/locale"
PROFILE_LOCALE="/etc/profile.d/locale.sh"
SYSTEMD_SYSTEM_CONF="/etc/systemd/system.conf"
SYSTEMD_USER_CONF="/etc/systemd/user.conf"

echo "Setting locale to: $LOCALE_NAME"

# /etc/locale.conf
sudo bash -c "cat > '$LOCALE_CONF' <<EOF
LANG=${LOCALE_NAME}
LC_TIME=${LOCALE_NAME}
LC_CTYPE=${LOCALE_NAME}
LC_ALL=${LOCALE_NAME}
EOF"

# /etc/locale.gen — enable locale if not already active
if grep -qE "^[#[:space:]]*${LOCALE_ENTRY}\$" /etc/locale.gen; then
  sudo sed -i "s/^#[[:space:]]*${LOCALE_ENTRY}/${LOCALE_ENTRY}/" /etc/locale.gen
else
  echo "$LOCALE_ENTRY" | sudo tee -a /etc/locale.gen >/dev/null
fi

echo "Regenerating locales..."
sudo locale-gen

# Hypr env.conf
if [[ -f "$ENV_CONF" ]]; then
  tmpfile=$(mktemp)
  awk -v newlang="$LOCALE_NAME" '
    BEGIN {found_LANG=0; found_LCTIME=0; found_LCTYPE=0; found_LCALL=0}
    /^env *= *LANG=/    { print "env = LANG="    newlang; found_LANG=1;   next }
    /^env *= *LC_TIME=/ { print "env = LC_TIME=" newlang; found_LCTIME=1; next }
    /^env *= *LC_CTYPE=/{ print "env = LC_CTYPE="newlang; found_LCTYPE=1; next }
    /^env *= *LC_ALL=/  { print "env = LC_ALL="  newlang; found_LCALL=1;  next }
    { print }
    END {
      if (!found_LANG)   print "env = LANG="    newlang
      if (!found_LCTIME) print "env = LC_TIME=" newlang
      if (!found_LCTYPE) print "env = LC_CTYPE="newlang
      if (!found_LCALL)  print "env = LC_ALL="  newlang
    }
  ' "$ENV_CONF" > "$tmpfile"
  mv "$tmpfile" "$ENV_CONF"
else
  cat > "$ENV_CONF" <<EOF
env = LANG=${LOCALE_NAME}
env = LC_TIME=${LOCALE_NAME}
env = LC_CTYPE=${LOCALE_NAME}
env = LC_ALL=${LOCALE_NAME}
EOF
fi

# /etc/environment
sudo bash -c "cat > '$ENV_SYSTEM' <<EOF
LANG=${LOCALE_NAME}
LC_TIME=${LOCALE_NAME}
LC_CTYPE=${LOCALE_NAME}
LC_ALL=${LOCALE_NAME}
EOF"

# /etc/default/locale
sudo bash -c "cat > '$DEFAULT_LOCALE' <<EOF
LANG=${LOCALE_NAME}
LC_TIME=${LOCALE_NAME}
LC_CTYPE=${LOCALE_NAME}
LC_ALL=${LOCALE_NAME}
EOF"

# /etc/profile.d/locale.sh
sudo bash -c "cat > '$PROFILE_LOCALE' <<EOF
export LANG=${LOCALE_NAME}
export LC_TIME=${LOCALE_NAME}
export LC_CTYPE=${LOCALE_NAME}
export LC_ALL=${LOCALE_NAME}
EOF"

# /etc/systemd/system.conf
if grep -q '^DefaultEnvironment=' "$SYSTEMD_SYSTEM_CONF"; then
  sudo sed -i "s/^DefaultEnvironment=.*/DefaultEnvironment=LANG=${LOCALE_NAME} LC_TIME=${LOCALE_NAME} LC_CTYPE=${LOCALE_NAME} LC_ALL=${LOCALE_NAME}/" "$SYSTEMD_SYSTEM_CONF"
else
  echo "DefaultEnvironment=LANG=${LOCALE_NAME} LC_TIME=${LOCALE_NAME} LC_CTYPE=${LOCALE_NAME} LC_ALL=${LOCALE_NAME}" | sudo tee -a "$SYSTEMD_SYSTEM_CONF" >/dev/null
fi

# /etc/systemd/user.conf
if grep -q '^DefaultEnvironment=' "$SYSTEMD_USER_CONF"; then
  sudo sed -i "s/^DefaultEnvironment=.*/DefaultEnvironment=LANG=${LOCALE_NAME} LC_TIME=${LOCALE_NAME} LC_CTYPE=${LOCALE_NAME} LC_ALL=${LOCALE_NAME}/" "$SYSTEMD_USER_CONF"
else
  echo "DefaultEnvironment=LANG=${LOCALE_NAME} LC_TIME=${LOCALE_NAME} LC_CTYPE=${LOCALE_NAME} LC_ALL=${LOCALE_NAME}" | sudo tee -a "$SYSTEMD_USER_CONF" >/dev/null
fi

echo "Done. Log out and back in (or reboot) to apply everywhere."
