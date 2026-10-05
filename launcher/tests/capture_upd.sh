#!/usr/bin/env bash
# W15-UPD screenshots of the launcher window via xvfb (Range-capable feed on 8094).
# Usage: GODOT=... launcher/tests/capture_upd.sh <out.png> <content|uninstall|paused|preloaded>
#   content    Settings page: Installation, Content (packs + Lite), Storage
#   uninstall  Settings with the uninstall confirmation open
#   paused     a delta update paused part-way (RESUME on the play button)
#   preloaded  game current, next patch pre-loaded ("Pre-loaded ..., ready at ...")
set -uo pipefail
godot="${GODOT:-godot}"
out="$1"; mode="$2"
here="$(cd "$(dirname "$0")/.." && pwd)"
repo="$(cd "$here/.." && pwd)"
tmp="$(mktemp -d)"; srv=""
trap '[[ -n "$srv" ]] && kill "$srv" 2>/dev/null; rm -rf "$tmp"' EXIT
mk() { # <dir> <version> <maps bytes> <hd bytes>
  mkdir -p "$1/packs"
  printf '#!/bin/sh\necho %s\n' "$2" > "$1/Cybergram.x86_64"; cp "$1/Cybergram.x86_64" "$1/Cybergram.exe"
  head -c 52000000 /dev/zero > "$1/Cybergram.pck"
  head -c "$3" /dev/urandom > "$1/packs/maps.pck"; head -c "$4" /dev/urandom > "$1/packs/heroes_hd.pck"
}
notes="$(ls "$repo"/production/releases/v*.md | sort -V | tail -1)"
mk "$tmp/b1" "0.10.0" 3000000 17000000
"$here/tools/make_update_feed.sh" v0.10.0 "$tmp/b1" "$tmp/b1" "$notes" "$tmp/host" > /dev/null 2>&1
echo '{"online":5,"in_lobby":2,"in_match":3,"max_players":0,"updated":1}' > "$tmp/host/status.json"
python3 "$here/tests/range_server.py" 8094 "$tmp/host" 2> /dev/null & srv=$!
for _ in $(seq 1 30); do curl -sf "http://127.0.0.1:8094/version.json" > /dev/null && break; sleep 0.2; done
printf '[launcher]\nversion_url="http://127.0.0.1:8094/version.json"\ngame_server="127.0.0.1:1"\n' > "$tmp/l.cfg"
run() { timeout 120 "$godot" --headless --path "$here" -- --config "$tmp/l.cfg" --settings "$tmp/s.cfg" "$@" > /dev/null 2>&1; }
run --update-to "$tmp/inst"
extra=(); frames=90
case "$mode" in
  content) extra=(--show-page settings) ;;
  uninstall) extra=(--show-uninstall); frames=120 ;;
  paused)
    mk "$tmp/b2" "0.11.0" 24000000 17000000; cp "$tmp/b1/packs/heroes_hd.pck" "$tmp/b2/packs/"
    "$here/tools/make_update_feed.sh" v0.11.0 "$tmp/b2" "$tmp/b2" "$notes" "$tmp/host" > /dev/null 2>&1
    extra=(--auto-update --pause-after 9500000); frames=240 ;;
  preloaded)
    mk "$tmp/b2" "0.11.0" 6000000 17000000; cp "$tmp/b1/packs/heroes_hd.pck" "$tmp/b2/packs/"
    NEXT_VERSION=v0.11.0 NEXT_WIN_DIR="$tmp/b2" NEXT_LIN_DIR="$tmp/b2" NEXT_ACTIVATE_AT=2026-10-12T18:00:00Z \
      "$here/tools/make_update_feed.sh" v0.10.0 "$tmp/b1" "$tmp/b1" "$notes" "$tmp/host" > /dev/null 2>&1
    run --preload --install-root "$tmp/inst"
    extra=(--now 2026-10-05T12:00:00Z) ;;
esac
mkdir -p "$tmp/frames"
xvfb-run -a -s "-screen 0 1280x720x24" timeout 120 "$godot" --path "$here" --rendering-driver opengl3 --resolution 1280x720 \
  --write-movie "$tmp/frames/f.png" --quit-after "$frames" -- --config "$tmp/l.cfg" --settings "$tmp/s.cfg" \
  --install-root "$tmp/inst" --no-launch "${extra[@]}" > "$tmp/run.log" 2>&1
grep -a "SCRIPT ERROR" -A3 "$tmp/run.log" | head -8
mkdir -p "$(dirname "$out")"
cp "$(ls "$tmp"/frames/*.png | sort | tail -n 1)" "$out"
echo "captured $out"
