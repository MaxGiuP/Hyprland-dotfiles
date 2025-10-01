#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "[*] Syncing configs into repo..."

rsync -av --delete ~/.config/hypr/              "$REPO_DIR/dotfiles/hypr/.config/hypr/"
rsync -av --delete ~/.config/quickshell/        "$REPO_DIR/dotfiles/quickshell/.config/quickshell/"
rsync -av --delete ~/.config/illogical-impulse/ "$REPO_DIR/dotfiles/illogical-impulse/.config/illogical-impulse/"

cd "$REPO_DIR"
git add -A
git commit -m "Update dotfiles from system on $(date)"
git push
