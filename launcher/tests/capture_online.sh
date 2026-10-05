#!/usr/bin/env bash
# W15-ONLINE screenshots of the launcher's online UI via xvfb.
# Usage: GODOT=... launcher/tests/capture_online.sh <out.png> [status|friends|party|crash|privacy|diag]
# Serves a feed + a status.json with a message of the day on port 8092 and
# runs a local headless game server (plain, guest-only) on UDP 7795 so the
# ping is a real ENet round trip. States other than "status" add
# --online-preview <state> (sample friends / party data, dialogs opened).
set -uo pipefail
godot="${GODOT:-godot}"
out="$1"; state="${2:-status}"
here="$(cd "$(dirname "$0")/.." && pwd)"
repo="$(cd "$here/.." && pwd)"
tmp="$(mktemp -d)"
pids=()
trap 'for p in "${pids[@]}"; do kill "$p" 2>/dev/null; done; rm -rf "$tmp"' EXIT
mkdir -p "$tmp/w" "$tmp/l" "$tmp/inst/game" "$tmp/frames" "$tmp/acc" "$tmp/home"
touch "$tmp/w/Cybergram.exe" "$tmp/l/Cybergram.x86_64" "$tmp/inst/game/Cybergram.x86_64"
echo 0.4.1 > "$tmp/inst/game/installed_version.txt"
notes="$(ls "$repo"/production/releases/v*.md | sort -V | tail -1)"
"$here/tools/make_update_feed.sh" v0.4.1 "$tmp/w" "$tmp/l" "$notes" "$tmp/host" > /dev/null
echo '{"online":7,"in_lobby":3,"in_match":4,"max_players":32,"updated":1,"motd":"Weekend event: double XP on Shardline Front until Sunday 22:00 CET. Server maintenance Monday 06:00."}' > "$tmp/host/status.json"
(cd "$tmp/host" && exec python3 -m http.server 8092 --bind 127.0.0.1 > /dev/null 2>&1) &
pids+=($!)
"$godot" --headless --path "$repo" -- --server --port 7795 --max-clients 4 --data-dir "$tmp/acc" > "$tmp/server.log" 2>&1 &
pids+=($!)
for _ in $(seq 1 60); do grep -q "open on UDP 7795" "$tmp/server.log" && break; sleep 0.5; done
printf '[launcher]\nversion_url="http://127.0.0.1:8092/version.json"\ngame_server="127.0.0.1:7795"\nclose_on_launch=false\n' > "$tmp/l.cfg"
extra="--page home"  # skips the UX first-run system check dialog
[[ "$state" != "status" ]] && extra="$extra --online-preview $state"
HOME="$tmp/home" XDG_DATA_HOME="$tmp/home/.local/share" xvfb-run -a -s "-screen 0 ${CAP_RES:-1280x720}x24" timeout 90 "$godot" --path "$here" --rendering-driver opengl3 --resolution ${CAP_RES:-1280x720} \
  --write-movie "$tmp/frames/f.png" --quit-after "${FRAMES:-240}" -- --config "$tmp/l.cfg" --install-root "$tmp/inst" \
  --settings "$tmp/settings.cfg" --no-launch $extra > "$tmp/launcher.log" 2>&1
mkdir -p "$(dirname "$out")"
cp "$(ls "$tmp"/frames/*.png | sort | tail -n 1)" "$out"
grep -a "SCRIPT ERROR\|^ERROR" "$tmp/launcher.log" | head -5
echo "captured $out"
