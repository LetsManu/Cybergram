#!/usr/bin/env bash
# Builds Cybergram-<version>-x86_64.AppImage: launcher as the entry point, game bundled
# (read-only; the launcher copies it to ~/.local/share/cybergram on first run and updates it there).
# Usage: installer/build_appimage.sh <version> <launcher_linux_dir> <game_linux_dir> <out_dir>
set -euo pipefail
[[ $# -eq 4 ]] || { echo "usage: $0 <version> <launcher_dir> <game_dir> <out_dir>" >&2; exit 2; }
ver="${1#v}"; launcher="$(cd "$2" && pwd)"; game="$(cd "$3" && pwd)"; mkdir -p "$4"; out="$(cd "$4" && pwd)"
here="$(cd "$(dirname "$0")" && pwd)"
tool="$("$here/fetch_appimagetool.sh" "${TOOL_DIR:-${TMPDIR:-/tmp}/cybergram-tools}")"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
app="$work/Cybergram.AppDir"
mkdir -p "$app/usr/bin" "$app/usr/share/cybergram/game"
cp "$launcher/CybergramLauncher.x86_64" "$launcher/launcher.cfg" "$app/usr/bin/"
chmod +x "$app/usr/bin/CybergramLauncher.x86_64"
cp -r "$game"/. "$app/usr/share/cybergram/game/"
chmod +x "$app/usr/share/cybergram/game/Cybergram.x86_64"
printf '%s\n' "$ver" > "$app/usr/share/cybergram/game/installed_version.txt"
cp "$here/cybergram.png" "$app/cybergram.png"
cp "$here/linux/cybergram.desktop" "$app/cybergram.desktop"
sed -i 's|^Exec=.*|Exec=AppRun|' "$app/cybergram.desktop"
cat > "$app/AppRun" <<'RUN'
#!/bin/sh
# Entry point: starts the launcher. APPDIR/APPIMAGE tell it to keep the game in a writable user folder.
HERE="$(dirname "$(readlink -f "$0")")"
export APPDIR="${APPDIR:-$HERE}"
exec "$HERE/usr/bin/CybergramLauncher.x86_64" "$@"
RUN
chmod +x "$app/AppRun"
ARCH=x86_64 "$tool" --appimage-extract-and-run --no-appstream "$app" "$out/Cybergram-$ver-x86_64.AppImage"
chmod +x "$out/Cybergram-$ver-x86_64.AppImage"
ls -la "$out/Cybergram-$ver-x86_64.AppImage"
