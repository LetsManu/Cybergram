#!/usr/bin/env bash
# Screenshot of the launcher window (update-available state) via xvfb.
# Usage: GODOT=... launcher/tests/capture_window.sh <out.png> [online|offline|ready|updating|login]
# online = update available, ready = up to date (PLAY), updating = throttled download in progress,
# login = sign-in dialog open.
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
[[ "$mode" == "ready" ]] && echo 0.4.1 > "$tmp/inst/game/installed_version.txt"
[[ "$mode" == "updating" ]] && head -c 40000000 /dev/urandom > "$tmp/w/Cybergram.exe" && head -c 40000000 /dev/urandom > "$tmp/l/Cybergram.x86_64"
notes="$(ls "$repo"/production/releases/v*.md | sort -V | tail -1)"
"$here/tools/make_update_feed.sh" v0.4.1 "$tmp/w" "$tmp/l" "$notes" "$tmp/host" > /dev/null
echo '{"online":5,"in_lobby":2,"in_match":3,"max_players":0,"updated":1}' > "$tmp/host/status.json"
printf '[launcher]\nversion_url="http://127.0.0.1:8091/version.json"\n' > "$tmp/l.cfg"
[[ "$mode" == "login" ]] && printf 'game_server="127.0.0.1:1"\n' >> "$tmp/l.cfg"
if [[ "$mode" != "offline" ]]; then
  if [[ "$mode" == "updating" ]]; then
    cat > "$tmp/slow.py" <<'PY'
import http.server, os, time
class H(http.server.SimpleHTTPRequestHandler):
    def copyfile(self, src, dst):
        slow = self.path.endswith(".zip")
        while True:
            b = src.read(262144 if slow else 65536)
            if not b: break
            dst.write(b); dst.flush()
            if slow: time.sleep(0.25)
    def log_message(self, *a): pass
http.server.ThreadingHTTPServer(("127.0.0.1", 8091), H).serve_forever()
PY
    (cd "$tmp/host" && exec python3 "$tmp/slow.py" > /dev/null 2>&1) &
  else
    (cd "$tmp/host" && exec python3 -m http.server 8091 --bind 127.0.0.1 > /dev/null 2>&1) &
  fi
  srv=$!
  sleep 1
fi
frames=60; extra=""
[[ "$mode" == "updating" ]] && { frames=150; extra="--auto-update"; }
[[ "$mode" == "login" ]] && { extra="--show-login"; frames=900; }
xvfb-run -a -s "-screen 0 ${CAP_RES:-1280x720}x24" timeout 90 "$godot" --path "$here" --rendering-driver opengl3 --resolution ${CAP_RES:-1280x720} \
  --write-movie "$tmp/frames/f.png" --quit-after "$frames" -- --config "$tmp/l.cfg" --install-root "$tmp/inst" --no-launch $extra > /dev/null 2>&1
mkdir -p "$(dirname "$out")"
cp "$(ls "$tmp"/frames/*.png | sort | tail -n 1)" "$out"
echo "captured $out"
