#!/usr/bin/env bash
set -euo pipefail

TRANSLATION_DIR="$HOME/.config/quickshell/translations"
LOCALE_CONF="/etc/locale.conf"
ENV_CONF="$HOME/.config/hypr/custom/env.conf"

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

# 4. Update /etc/locale.conf (requires root)
sudo bash -c "echo 'LANG=${lang}.UTF-8' > '$LOCALE_CONF'"

# 5. Update ~/.config/hypr/custom/env.conf
if [[ -f "$ENV_CONF" ]]; then
  tmpfile=$(mktemp)
  awk -v newlang="$lang" '
    BEGIN {changed=0}
    /^env *= *LANG=/ {
      print "env = LANG=" newlang ".UTF-8"
      changed=1
      next
    }
    {print}
    END {
      if (!changed) print "env = LANG=" newlang ".UTF-8"
    }
  ' "$ENV_CONF" > "$tmpfile"
  mv "$tmpfile" "$ENV_CONF"
else
  echo "env = LANG=${lang}.UTF-8" > "$ENV_CONF"
fi

# 6. Reload environment suggestion
echo
echo "Locale and Hypr env language updated successfully."
echo "You may need to re-login or run:"
echo "  source /etc/locale.conf"

