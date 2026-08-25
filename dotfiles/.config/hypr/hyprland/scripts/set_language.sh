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
ENV_LUA="$(cd "$SCRIPT_DIR/.." && pwd)/env.lua"

LOCALE_NAME="${lang}.UTF-8"
LOCALE_ENTRY="${LOCALE_NAME} UTF-8"

LOCALE_CONF="/etc/locale.conf"
ENV_SYSTEM="/etc/environment"
DEFAULT_LOCALE="/etc/default/locale"
PROFILE_LOCALE="/etc/profile.d/locale.sh"
USER_HOME="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
USER_ENV_LOCALE="$USER_HOME/.config/environment.d/10-locale.conf"
SYSTEMD_SYSTEM_CONF="/etc/systemd/system.conf"
SYSTEMD_USER_CONF="/etc/systemd/user.conf"

echo "Setting locale to: $LOCALE_NAME"

# /etc/locale.conf
printf 'LANG=%s\nLC_TIME=%s\nLC_CTYPE=%s\nLC_MESSAGES=%s\nLC_ALL=%s\n' \
    "$LOCALE_NAME" "$LOCALE_NAME" "$LOCALE_NAME" "$LOCALE_NAME" "$LOCALE_NAME" \
    > "$LOCALE_CONF"

# /etc/locale.gen — enable locale if not already active
if grep -qE "^[#[:space:]]*${LOCALE_ENTRY}\$" /etc/locale.gen; then
  sed -i "s/^#[[:space:]]*${LOCALE_ENTRY}/${LOCALE_ENTRY}/" /etc/locale.gen
else
  echo "$LOCALE_ENTRY" >> /etc/locale.gen
fi

echo "Regenerating locales..."
locale-gen

# Hypr env.lua
if [[ -f "$ENV_LUA" ]]; then
  original_owner=$(stat -c '%U:%G' "$ENV_LUA")
  original_perms=$(stat -c '%a' "$ENV_LUA")
  tmpfile=$(mktemp)
  awk -v newlang="$LOCALE_NAME" '
    BEGIN {found_LANG=0; found_LCTIME=0; found_LCTYPE=0; found_LCMESSAGES=0; found_LCALL=0}
    /^hl\.env\("LANG"/    { print "hl.env(\"LANG\", \""    newlang "\")"; found_LANG=1;   next }
    /^hl\.env\("LC_TIME"/ { print "hl.env(\"LC_TIME\", \"" newlang "\")"; found_LCTIME=1; next }
    /^hl\.env\("LC_CTYPE"/{ print "hl.env(\"LC_CTYPE\", \""newlang "\")"; found_LCTYPE=1; next }
    /^hl\.env\("LC_MESSAGES"/{ print "hl.env(\"LC_MESSAGES\", \""newlang "\")"; found_LCMESSAGES=1; next }
    /^hl\.env\("LC_ALL"/  { print "hl.env(\"LC_ALL\", \""  newlang "\")"; found_LCALL=1;  next }
    { print }
    END {
      if (!found_LANG)   print "hl.env(\"LANG\", \""    newlang "\")"
      if (!found_LCTIME) print "hl.env(\"LC_TIME\", \"" newlang "\")"
      if (!found_LCTYPE) print "hl.env(\"LC_CTYPE\", \""newlang "\")"
      if (!found_LCMESSAGES) print "hl.env(\"LC_MESSAGES\", \""newlang "\")"
      if (!found_LCALL)  print "hl.env(\"LC_ALL\", \""  newlang "\")"
    }
  ' "$ENV_LUA" > "$tmpfile"
  mv "$tmpfile" "$ENV_LUA"
  chown "$original_owner" "$ENV_LUA"
  chmod "$original_perms" "$ENV_LUA"
else
  cat > "$ENV_LUA" <<EOF
hl.env("LANG", "${LOCALE_NAME}")
hl.env("LC_TIME", "${LOCALE_NAME}")
hl.env("LC_CTYPE", "${LOCALE_NAME}")
hl.env("LC_MESSAGES", "${LOCALE_NAME}")
hl.env("LC_ALL", "${LOCALE_NAME}")
EOF
fi

# /etc/environment
printf 'LANG=%s\nLC_TIME=%s\nLC_CTYPE=%s\nLC_MESSAGES=%s\nLC_ALL=%s\n' \
    "$LOCALE_NAME" "$LOCALE_NAME" "$LOCALE_NAME" "$LOCALE_NAME" "$LOCALE_NAME" \
    > "$ENV_SYSTEM"

# /etc/default/locale
printf 'LANG=%s\nLC_TIME=%s\nLC_CTYPE=%s\nLC_MESSAGES=%s\nLC_ALL=%s\n' \
    "$LOCALE_NAME" "$LOCALE_NAME" "$LOCALE_NAME" "$LOCALE_NAME" "$LOCALE_NAME" \
    > "$DEFAULT_LOCALE"

# /etc/profile.d/locale.sh
printf 'export LANG=%s\nexport LC_TIME=%s\nexport LC_CTYPE=%s\nexport LC_MESSAGES=%s\nexport LC_ALL=%s\n' \
    "$LOCALE_NAME" "$LOCALE_NAME" "$LOCALE_NAME" "$LOCALE_NAME" "$LOCALE_NAME" \
    > "$PROFILE_LOCALE"

mkdir -p "$(dirname "$USER_ENV_LOCALE")"
cat > "$USER_ENV_LOCALE" <<EOF
LANG=${LOCALE_NAME}
LC_TIME=${LOCALE_NAME}
LC_CTYPE=${LOCALE_NAME}
LC_MESSAGES=${LOCALE_NAME}
# Avoid forcing LC_ALL; let categories inherit from LANG
EOF
home_owner=$(stat -c '%U:%G' "$USER_HOME")
chown "$home_owner" "$USER_ENV_LOCALE"

# /etc/systemd/system.conf
if grep -q '^DefaultEnvironment=' "$SYSTEMD_SYSTEM_CONF"; then
  sed -i "s/^DefaultEnvironment=.*/DefaultEnvironment=LANG=${LOCALE_NAME} LC_TIME=${LOCALE_NAME} LC_CTYPE=${LOCALE_NAME} LC_MESSAGES=${LOCALE_NAME} LC_ALL=${LOCALE_NAME}/" "$SYSTEMD_SYSTEM_CONF"
else
  echo "DefaultEnvironment=LANG=${LOCALE_NAME} LC_TIME=${LOCALE_NAME} LC_CTYPE=${LOCALE_NAME} LC_MESSAGES=${LOCALE_NAME} LC_ALL=${LOCALE_NAME}" >> "$SYSTEMD_SYSTEM_CONF"
fi

# /etc/systemd/user.conf
if grep -q '^DefaultEnvironment=' "$SYSTEMD_USER_CONF"; then
  sed -i "s/^DefaultEnvironment=.*/DefaultEnvironment=LANG=${LOCALE_NAME} LC_TIME=${LOCALE_NAME} LC_CTYPE=${LOCALE_NAME} LC_MESSAGES=${LOCALE_NAME} LC_ALL=${LOCALE_NAME}/" "$SYSTEMD_USER_CONF"
else
  echo "DefaultEnvironment=LANG=${LOCALE_NAME} LC_TIME=${LOCALE_NAME} LC_CTYPE=${LOCALE_NAME} LC_MESSAGES=${LOCALE_NAME} LC_ALL=${LOCALE_NAME}" >> "$SYSTEMD_USER_CONF"
fi

echo "Done. Log out and back in (or reboot) to apply everywhere."
