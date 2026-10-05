#!/usr/bin/env bash
# Builds CybergramInstaller-<version>-linux-x86_64.tar.gz (install.sh / uninstall.sh + launcher + game).
# Usage: installer/build_linux_tar.sh <version> <launcher_linux_dir> <game_linux_dir> <out_dir>
set -euo pipefail
[[ $# -eq 4 ]] || { echo "usage: $0 <version> <launcher_dir> <game_dir> <out_dir>" >&2; exit 2; }
ver="${1#v}"; launcher="$(cd "$2" && pwd)"; game="$(cd "$3" && pwd)"; mkdir -p "$4"; out="$(cd "$4" && pwd)"
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
d="$work/cybergram-$ver"
mkdir -p "$d/files" "$d/game"
cp "$launcher/CybergramLauncher.x86_64" "$launcher/launcher.cfg" "$d/files/"
cp -r "$game"/. "$d/game/"
printf '%s\n' "$ver" > "$d/game/installed_version.txt"
cp "$here/linux/install.sh" "$here/linux/uninstall.sh" "$here/cybergram.png" "$d/"
chmod +x "$d/install.sh" "$d/uninstall.sh" "$d/files/CybergramLauncher.x86_64" "$d/game/Cybergram.x86_64"
tar -czf "$out/CybergramInstaller-$ver-linux-x86_64.tar.gz" -C "$work" "cybergram-$ver"
ls -la "$out/CybergramInstaller-$ver-linux-x86_64.tar.gz"
