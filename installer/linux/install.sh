#!/usr/bin/env bash
# Cybergram per-user installer: no root needed.
#   ./install.sh            installs to ${XDG_DATA_HOME:-~/.local/share}/cybergram
#   ./install.sh --lite     Lite install: skips the HD hero textures (smaller, for
#                           weaker PCs; switch them on later in the launcher's Settings)
# Adds a menu entry (.desktop) and an icon. Remove again with uninstall.sh.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
lite=0
[[ "${1:-}" == "--lite" ]] && lite=1
data="${XDG_DATA_HOME:-$HOME/.local/share}"
dest="$data/cybergram"
[[ -f "$here/files/CybergramLauncher.x86_64" && -f "$here/game/Cybergram.x86_64" ]] \
  || { echo "install.sh must stay inside the extracted installer folder." >&2; exit 1; }

mkdir -p "$dest"
cp "$here/files/CybergramLauncher.x86_64" "$dest/CybergramLauncher.x86_64"
chmod +x "$dest/CybergramLauncher.x86_64"
# launcher.cfg is the player's own config: keep it on re-install.
[[ -f "$dest/launcher.cfg" ]] || cp "$here/files/launcher.cfg" "$dest/launcher.cfg"
rm -rf "$dest/game"
cp -r "$here/game" "$dest/game"
rm -f "$dest/content.cfg"
if [[ $lite == 1 ]]; then
  rm -f "$dest/game/packs/heroes_hd.pck"
  printf '[content]\n\nskip=PackedStringArray("heroes_hd")\n' > "$dest/content.cfg"
fi
chmod +x "$dest/game/Cybergram.x86_64"
cp "$here/cybergram.png" "$dest/cybergram.png"
cp "$here/uninstall.sh" "$dest/uninstall.sh"
chmod +x "$dest/uninstall.sh"

mkdir -p "$data/applications" "$data/icons/hicolor/256x256/apps"
cp "$here/cybergram.png" "$data/icons/hicolor/256x256/apps/cybergram.png"
cat > "$data/applications/cybergram.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=Cybergram
Comment=PvP first-person MOBA shooter
Exec=$dest/CybergramLauncher.x86_64
Path=$dest
Icon=cybergram
Categories=Game;
Terminal=false
DESK
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$data/applications" >/dev/null 2>&1 || true
echo "Cybergram installed to $dest"
echo "Start it from your application menu (Games > Cybergram) or run $dest/CybergramLauncher.x86_64"
