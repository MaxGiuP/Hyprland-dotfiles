#!/usr/bin/env bash
set -euo pipefail

TRANSLATION_DIR="$HOME/.config/quickshell/ii/translations"
LOCALE_CONF="/etc/locale.conf"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_LUA="$(cd "$SCRIPT_DIR/.." && pwd)/env.lua"

ENV_SYSTEM="/etc/environment"
DEFAULT_LOCALE="/etc/default/locale"
PROFILE_LOCALE="/etc/profile.d/locale.sh"
USER_ENV_LOCALE="$HOME/.config/environment.d/10-locale.conf"
SYSTEMD_SYSTEM_CONF="/etc/systemd/system.conf"
SYSTEMD_USER_CONF="/etc/systemd/user.conf"

# 1. Find available languages (strip .json and .bak)
LANGS=($(find "$TRANSLATION_DIR" -maxdepth 1 -type f -name "*.json" ! -name "*.bak" -exec basename {} .json \;))

if [[ ${#LANGS[@]} -eq 0 ]]; then
  echo "No translation files found in $TRANSLATION_DIR"
  exit 1
fi

# 2. Show menu
echo "Available languages:"
select lang in "${LANGS[@]}"; do
  [[ -n "$lang" ]] && break
  echo "Invalid choice. Try again."
done

# 3. Confirm
echo "Setting system and Hypr environment language to: $lang.UTF-8"

LOCALE_NAME="${lang}.UTF-8"
LOCALE_ENTRY="${LOCALE_NAME} UTF-8"

###############################################################################
# 4. Update /etc/locale.conf with LANG, LC_TIME, LC_CTYPE, LC_ALL
###############################################################################

sudo bash -c "cat > '$LOCALE_CONF' <<EOF
LANG=${LOCALE_NAME}
LC_TIME=${LOCALE_NAME}
LC_CTYPE=${LOCALE_NAME}
LC_MESSAGES=${LOCALE_NAME}
LC_ALL=${LOCALE_NAME}
EOF"

###############################################################################
# 4a. Ensure locale is enabled in /etc/locale.gen
###############################################################################

if grep -qE "^[#[:space:]]*${LOCALE_ENTRY}\$" /etc/locale.gen; then
  sudo sed -i "s/^#[[:space:]]*${LOCALE_ENTRY}/${LOCALE_ENTRY}/" /etc/locale.gen
else
  echo "$LOCALE_ENTRY" | sudo tee -a /etc/locale.gen >/dev/null
fi

###############################################################################
# 4b. Regenerate locales
###############################################################################

echo "Regenerating locales..."
sudo locale-gen

###############################################################################
# 5. Update Hypr env.lua (LANG, LC_TIME, LC_CTYPE, LC_ALL)
###############################################################################

if [[ -f "$ENV_LUA" ]]; then
  tmpfile=$(mktemp)
  awk -v newlang="$LOCALE_NAME" '
    BEGIN {found_LANG=0; found_LCTIME=0; found_LCTYPE=0; found_LCMESSAGES=0; found_LCALL=0}

    /^hl\.env\("LANG"/ {
      print "hl.env(\"LANG\", \"" newlang "\")"
      found_LANG=1
      next
    }

    /^hl\.env\("LC_TIME"/ {
      print "hl.env(\"LC_TIME\", \"" newlang "\")"
      found_LCTIME=1
      next
    }

    /^hl\.env\("LC_CTYPE"/ {
      print "hl.env(\"LC_CTYPE\", \"" newlang "\")"
      found_LCTYPE=1
      next
    }

    /^hl\.env\("LC_MESSAGES"/ {
      print "hl.env(\"LC_MESSAGES\", \"" newlang "\")"
      found_LCMESSAGES=1
      next
    }

    /^hl\.env\("LC_ALL"/ {
      print "hl.env(\"LC_ALL\", \"" newlang "\")"
      found_LCALL=1
      next
    }

    {print}

    END {
      if (!found_LANG)   print "hl.env(\"LANG\", \"" newlang "\")"
      if (!found_LCTIME) print "hl.env(\"LC_TIME\", \"" newlang "\")"
      if (!found_LCTYPE) print "hl.env(\"LC_CTYPE\", \"" newlang "\")"
      if (!found_LCMESSAGES) print "hl.env(\"LC_MESSAGES\", \"" newlang "\")"
      if (!found_LCALL)  print "hl.env(\"LC_ALL\", \"" newlang "\")"
    }
  ' "$ENV_LUA" > "$tmpfile"
  mv "$tmpfile" "$ENV_LUA"
else
  cat > "$ENV_LUA" <<EOF
hl.env("LANG", "${LOCALE_NAME}")
hl.env("LC_TIME", "${LOCALE_NAME}")
hl.env("LC_CTYPE", "${LOCALE_NAME}")
hl.env("LC_MESSAGES", "${LOCALE_NAME}")
hl.env("LC_ALL", "${LOCALE_NAME}")
EOF
fi

###############################################################################
# 5b. Update other global locale files used by apps like VMware
###############################################################################

# /etc/environment
sudo bash -c "cat > '$ENV_SYSTEM' <<EOF
LANG=${LOCALE_NAME}
LC_TIME=${LOCALE_NAME}
LC_CTYPE=${LOCALE_NAME}
LC_MESSAGES=${LOCALE_NAME}
LC_ALL=${LOCALE_NAME}
EOF"

# /etc/default/locale
sudo bash -c "cat > '$DEFAULT_LOCALE' <<EOF
LANG=${LOCALE_NAME}
LC_TIME=${LOCALE_NAME}
LC_CTYPE=${LOCALE_NAME}
LC_MESSAGES=${LOCALE_NAME}
LC_ALL=${LOCALE_NAME}
EOF"

# /etc/profile.d/locale.sh
sudo bash -c "cat > '$PROFILE_LOCALE' <<EOF
export LANG=${LOCALE_NAME}
export LC_TIME=${LOCALE_NAME}
export LC_CTYPE=${LOCALE_NAME}
export LC_MESSAGES=${LOCALE_NAME}
export LC_ALL=${LOCALE_NAME}
EOF"

mkdir -p "$(dirname "$USER_ENV_LOCALE")"
cat > "$USER_ENV_LOCALE" <<EOF
LANG=${LOCALE_NAME}
LC_TIME=${LOCALE_NAME}
LC_CTYPE=${LOCALE_NAME}
LC_MESSAGES=${LOCALE_NAME}
# Avoid forcing LC_ALL; let categories inherit from LANG
EOF

# /etc/systemd/system.conf
if grep -q '^DefaultEnvironment=' "$SYSTEMD_SYSTEM_CONF"; then
  sudo sed -i "s/^DefaultEnvironment=.*/DefaultEnvironment=LANG=${LOCALE_NAME} LC_TIME=${LOCALE_NAME} LC_CTYPE=${LOCALE_NAME} LC_MESSAGES=${LOCALE_NAME} LC_ALL=${LOCALE_NAME}/" "$SYSTEMD_SYSTEM_CONF"
else
  echo "DefaultEnvironment=LANG=${LOCALE_NAME} LC_TIME=${LOCALE_NAME} LC_CTYPE=${LOCALE_NAME} LC_MESSAGES=${LOCALE_NAME} LC_ALL=${LOCALE_NAME}" | sudo tee -a "$SYSTEMD_SYSTEM_CONF" >/dev/null
fi

# /etc/systemd/user.conf
if grep -q '^DefaultEnvironment=' "$SYSTEMD_USER_CONF"; then
  sudo sed -i "s/^DefaultEnvironment=.*/DefaultEnvironment=LANG=${LOCALE_NAME} LC_TIME=${LOCALE_NAME} LC_CTYPE=${LOCALE_NAME} LC_MESSAGES=${LOCALE_NAME} LC_ALL=${LOCALE_NAME}/" "$SYSTEMD_USER_CONF"
else
  echo "DefaultEnvironment=LANG=${LOCALE_NAME} LC_TIME=${LOCALE_NAME} LC_CTYPE=${LOCALE_NAME} LC_MESSAGES=${LOCALE_NAME} LC_ALL=${LOCALE_NAME}" | sudo tee -a "$SYSTEMD_USER_CONF" >/dev/null
fi

###############################################################################
# 6. Suggest reload
###############################################################################

echo
echo "Locale and Hypr env language updated successfully."
echo "Log out and back in (or reboot) to apply the new locale everywhere."
