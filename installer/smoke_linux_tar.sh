#!/usr/bin/env bash
# Smoke test for the Linux tar installer: install into a temp HOME, check the files and
# the .desktop entry, then uninstall (keeping, then removing, the settings).
# Usage: installer/smoke_linux_tar.sh <CybergramInstaller-*.tar.gz>
set -euo pipefail
tgz="$(readlink -f "$1")"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"; unset XDG_DATA_HOME
mkdir -p "$HOME" "$tmp/x"
tar -xzf "$tgz" -C "$tmp/x"
"$tmp"/x/cybergram-*/install.sh
d="$HOME/.local/share/cybergram"
for f in "$d/CybergramLauncher.x86_64" "$d/launcher.cfg" "$d/game/Cybergram.x86_64" "$d/game/installed_version.txt" \
         "$d/uninstall.sh" "$HOME/.local/share/icons/hicolor/256x256/apps/cybergram.png" \
         "$HOME/.local/share/applications/cybergram.desktop"; do
  [[ -f "$f" ]] || { echo "FAIL: missing $f"; exit 1; }
done
[[ -x "$d/CybergramLauncher.x86_64" && -x "$d/game/Cybergram.x86_64" ]] || { echo "FAIL: not executable"; exit 1; }
grep -qx "Exec=$d/CybergramLauncher.x86_64" "$HOME/.local/share/applications/cybergram.desktop" || { echo "FAIL: desktop Exec"; exit 1; }
if command -v desktop-file-validate >/dev/null 2>&1; then
  desktop-file-validate "$HOME/.local/share/applications/cybergram.desktop"
fi
settings="$HOME/.local/share/godot/app_userdata/Cybergram"
mkdir -p "$settings"
"$d/uninstall.sh" --keep-settings > /dev/null
[[ ! -e "$d" && ! -e "$HOME/.local/share/applications/cybergram.desktop" ]] || { echo "FAIL: uninstall left files"; exit 1; }
[[ -d "$settings" ]] || { echo "FAIL: settings were deleted despite --keep-settings"; exit 1; }
"$tmp"/x/cybergram-*/install.sh > /dev/null
"$d/uninstall.sh" --remove-settings > /dev/null
[[ ! -e "$settings" ]] || { echo "FAIL: settings kept despite --remove-settings"; exit 1; }
echo "linux tar installer smoke: ok"
