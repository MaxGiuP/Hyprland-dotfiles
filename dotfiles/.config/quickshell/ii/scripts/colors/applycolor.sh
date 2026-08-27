#!/usr/bin/env bash

QUICKSHELL_CONFIG_NAME="ii"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CONFIG_DIR="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME"
CACHE_DIR="$XDG_CACHE_HOME/quickshell"
STATE_DIR="$XDG_STATE_HOME/quickshell"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

term_alpha=100 #Set this to < 100 make all your terminals transparent
# sleep 0 # idk i wanted some delay or colors dont get applied properly
if [ ! -d "$STATE_DIR"/user/generated ]; then
  mkdir -p "$STATE_DIR"/user/generated
fi
cd "$CONFIG_DIR" || exit

colorlist=()
colorvalues=()

# Parse the generated SCSS with Bash builtins. The old cat/cut pipeline started
# four processes every time a wallpaper changed.
while IFS=': ' read -r color_name color_value; do
  [[ -z "$color_name" || -z "$color_value" ]] && continue
  colorlist+=("$color_name")
  colorvalues+=("${color_value%;}")
done < "$STATE_DIR/user/generated/material_colors.scss"

apply_term() {
  # Check if terminal escape sequence template exists
  if [ ! -f "$SCRIPT_DIR/terminal/sequences.txt" ]; then
    echo "Template file not found for Terminal. Skipping that."
    return
  fi
  # Copy template
  mkdir -p "$STATE_DIR"/user/generated/terminal
  cp "$SCRIPT_DIR/terminal/sequences.txt" "$STATE_DIR"/user/generated/terminal/sequences.txt
  # Build one sed program instead of starting sed once for every palette entry.
  local sed_program="$STATE_DIR/user/generated/terminal/colors.sed"
  : > "$sed_program"
  for i in "${!colorlist[@]}"; do
    printf 's/%s #/%s/g\n' "${colorlist[$i]}" "${colorvalues[$i]#\#}" >> "$sed_program"
  done
  printf 's/\\$alpha/%s/g\n' "$term_alpha" >> "$sed_program"
  sed -i -f "$sed_program" "$STATE_DIR/user/generated/terminal/sequences.txt"
  rm -f "$sed_program"

  for file in /dev/pts/*; do
    if [[ $file =~ ^/dev/pts/[0-9]+$ ]]; then
      {
      cat "$STATE_DIR"/user/generated/terminal/sequences.txt >"$file"
      } & disown || true
    fi
  done
}

apply_qt() {
  python3 "$CONFIG_DIR/scripts/colors/apply_qt_kde.py"
}

apply_gtk() {
  sh "$CONFIG_DIR/scripts/colors/applygtk.sh"
}

apply_gnome_accent() {
  python3 "$CONFIG_DIR/scripts/colors/apply_gnome_accent.py"
}

apply_browsers() {
  python3 "$CONFIG_DIR/scripts/colors/apply_browser_theme.py"
}

apply_vscodium() {
  python3 "$CONFIG_DIR/scripts/colors/apply_vscodium_theme.py"
}

# Check if terminal theming is enabled in config
CONFIG_FILE="$XDG_CONFIG_HOME/illogical-impulse/config.json"
if [ -f "$CONFIG_FILE" ]; then
  apply_gnome_accent &

  # Read all feature switches in one jq invocation.
  IFS=$'\t' read -r enable_terminal enable_gtk enable_qt < <(
    jq -r '[
      .appearance.wallpaperTheming.enableTerminal,
      (.appearance.wallpaperTheming.enableGtkApps // true),
      (.appearance.wallpaperTheming.enableQtApps // true)
    ] | @tsv' "$CONFIG_FILE"
  )
  if [ "$enable_terminal" = "true" ]; then
    apply_term &
  fi

  if [ "$enable_gtk" = "true" ]; then
    apply_gtk
  fi

  if [ "$enable_qt" = "true" ]; then
    apply_qt &
  fi

  apply_browsers &
else
  echo "Config file not found at $CONFIG_FILE. Applying terminal theming by default."
  apply_gnome_accent || true
  apply_term &
  apply_gtk
  apply_browsers &
  apply_qt &
fi

apply_vscodium &
