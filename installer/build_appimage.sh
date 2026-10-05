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
"$here/../launcher/tools/write_manifest.sh" "$app/usr/share/cybergram/game"   # delta-update baseline (W15-UPD)
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
# Update information (W15-UPD): AppImageUpdate / zsync tools find newer releases on
# GitHub. The launcher itself updates the AppImage from the signed feed.
upd="${APPIMAGE_UPDATE_INFO-gh-releases-zsync|LetsManu|Cybergram|latest|Cybergram-*-x86_64.AppImage.zsync}"
uflag=(); [[ -n "$upd" ]] && uflag=(-u "$upd")
img="$out/Cybergram-$ver-x86_64.AppImage"
(cd "$out" && ARCH=x86_64 "$tool" --appimage-extract-and-run --no-appstream "${uflag[@]}" "$app" "$img")
chmod +x "$img"
# appimagetool writes <img>.zsync itself when zsyncmake is installed; make sure it exists.
if [[ -n "$upd" && ! -f "$img.zsync" ]] && command -v zsyncmake >/dev/null; then
  (cd "$out" && zsyncmake -u "$(basename "$img")" -o "$(basename "$img").zsync" "$(basename "$img")")
fi
ls -la "$img" "$img.zsync" 2>/dev/null || true
