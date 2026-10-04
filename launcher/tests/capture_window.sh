#!/usr/bin/env bash
# Screenshot of the launcher window (update-available state) via xvfb.
# Usage: GODOT=... launcher/tests/capture_window.sh <out.png> [offline]
# Serves a feed built from production/releases/v*.md on port 8091.
set -uo pipefail
godot="${GODOT:-godot}"
out="$1"; mode="${2:-online}"
here="$(cd "$(dirname "$0")/.." && pwd)"
repo="$(cd "$here/.." && pwd)"
tmp="$(mktemp -d)"
srv=""
trap '[[ -n "$srv" ]] && kill "$srv" 2>/dev/null; rm -rf "$tmp"' EXIT
mkdir -p "$tmp/w" "$tmp/l" "$tmp/inst/game" "$tmp/frames"
touch "$tmp/w/Cybergram.exe" "$tmp/l/Cybergram.x86_64" "$tmp/inst/game/Cybergram.x86_64"
echo 0.4.0 > "$tmp/inst/game/installed_version.txt"
notes="$(ls "$repo"/production/releases/v*.md | sort -V | tail -1)"
"$here/tools/make_update_feed.sh" v0.4.1 "$tmp/w" "$tmp/l" "$notes" "$tmp/host" > /dev/null
printf '[launcher]\nversion_url="http://127.0.0.1:8091/version.json"\n' > "$tmp/l.cfg"
if [[ "$mode" != "offline" ]]; then
  (cd "$tmp/host" && exec python3 -m http.server 8091 --bind 127.0.0.1 > /dev/null 2>&1) &
  srv=$!
  sleep 1
fi
xvfb-run -a -s "-screen 0 960x560x24" timeout 90 "$godot" --path "$here" --resolution 960x560 \
  --write-movie "$tmp/frames/f.png" --quit-after 60 -- --config "$tmp/l.cfg" --install-root "$tmp/inst" --no-launch > /dev/null 2>&1
mkdir -p "$(dirname "$out")"
cp "$(ls "$tmp"/frames/*.png | sort | tail -n 1)" "$out"
echo "captured $out"
