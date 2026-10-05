#!/usr/bin/env bash
# Removes Cybergram (program files, menu entry, icon). Asks before deleting your settings.
#   ./uninstall.sh [--remove-settings | --keep-settings]
set -euo pipefail
data="${XDG_DATA_HOME:-$HOME/.local/share}"
dest="$data/cybergram"
mode="ask"
case "${1:-}" in --remove-settings) mode=yes ;; --keep-settings) mode=no ;; esac

rm -rf "$dest"
rm -f "$data/applications/cybergram.desktop" "$data/icons/hicolor/256x256/apps/cybergram.png"
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$data/applications" >/dev/null 2>&1 || true
echo "Cybergram has been removed."

settings=("$data/godot/app_userdata/Cybergram" "$data/godot/app_userdata/Cybergram Launcher")
if [[ "$mode" == ask ]]; then
  echo
  echo "Do you also want to delete your saved settings and sign-in name? They are stored in:"
  printf '  %s\n' "${settings[@]}"
  read -r -p "Delete them? [y/N] " ans || ans=""
  [[ "$ans" =~ ^[Yy] ]] && mode=yes || mode=no
fi
if [[ "$mode" == yes ]]; then
  rm -rf "${settings[@]}"
  echo "Settings deleted."
else
  echo "Settings kept."
fi
