#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
DOT_DIR="$REPO_DIR/dotfiles"

backup_if_exists() {
  local target="$1"
  if [ -e "$target" ] || [ -L "$target" ]; then
    mv -f "$target" "$target.bak.$(date +%Y%m%d_%H%M%S)"
  fi
}

link_tree() {
  # crea symlink dei file in ~/.config
  local src_root="$1"
  local dst_root="$2"
  cd "$src_root"
  find . -type d -exec mkdir -p "$dst_root/{}" \;
  find . -type f | while read f; do
    if [ -e "$dst_root/$f" ] || [ -L "$dst_root/$f" ]; then
      backup_if_exists "$dst_root/$f"
    fi
    ln -s "$src_root/$f" "$dst_root/$f"
  done
}

# Hyprland
if [ -d "$DOT_DIR/hypr/.config/hypr" ]; then
  link_tree "$DOT_DIR/hypr/.config" "$HOME/.config"
fi

# Quickshell
if [ -d "$DOT_DIR/quickshell/.config/quickshell" ]; then
  link_tree "$DOT_DIR/quickshell/.config" "$HOME/.config"
fi

# Illogical-Impulse
if [ -d "$DOT_DIR/illogical-impulse/.config/illogical-impulse" ]; then
  link_tree "$DOT_DIR/illogical-impulse/.config" "$HOME/.config"
fi

echo "Done. Fai logout e rientra nella sessione."
