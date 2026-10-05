#!/usr/bin/env bash
# W15-UPD end-to-end test against a local feed (Range-capable server on 8093):
# split packs, per-file delta update, pause + resume (HTTP Range), speed limit,
# pre-load + timed activation, optional pack remove/add, Lite first install,
# corrupt blob, per-file repair, AppImage self-update. Run from anywhere:
#   GODOT=godot launcher/tests/e2e_upd.sh
# Needs jq, zip, python3, curl. Exit 0 = all checks passed.
set -uo pipefail
godot="${GODOT:-godot}"
here="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
port=8093
fails=0
srv_pid=""
cleanup() {
  [[ -n "$srv_pid" ]] && kill "$srv_pid" 2>/dev/null
  rm -rf "$tmp"
}
trap cleanup EXIT

ok() { echo "  ok: $1"; }
bad() { echo "  FAIL: $1"; fails=$((fails + 1)); }
check() { if eval "$1"; then ok "$2"; else bad "$2"; fi; }
expect_exit() { # <want> <label> <cmd...>
  local want="$1" label="$2"; shift 2
  "$@" > "$tmp/out.log" 2>&1
  local got=$?
  grep -a "LAUNCHER" "$tmp/out.log" | tail -n 3
  grep -aq "SCRIPT ERROR" "$tmp/out.log" && { bad "$label: script error"; grep -a -A3 "SCRIPT ERROR" "$tmp/out.log" | head -8; }
  [[ "$got" == "$want" ]] && ok "$label (exit $got)" || bad "$label (exit $got, wanted $want)"
}
rnd() { head -c "$2" /dev/urandom > "$1"; }
sha() { sha256sum "$1" | cut -d' ' -f1; }
gets() { grep -c "GET /blobs/$1" "$tmp/http.log" || true; }

# --- builds: 0.5.0, 0.6.0 (exe + maps change), 0.7.0 (next, exe changes) ------------
mk() { # <dir> <exe text>
  mkdir -p "$1/packs" "$1/data"
  printf '#!/bin/sh\necho "%s"\n' "$2" > "$1/Cybergram.x86_64"
  echo "$2" > "$1/Cybergram.exe"
}
mk "$tmp/b5" "game 0.5.0"; rnd "$tmp/b5/packs/maps.pck" 400000; rnd "$tmp/b5/packs/heroes_hd.pck" 900000
rnd "$tmp/b5/Cybergram.pck" 300000; echo same > "$tmp/b5/data/same.txt"; echo gone > "$tmp/b5/data/old.txt"
cp -r "$tmp/b5" "$tmp/b6"; mk "$tmp/b6" "game 0.6.0"; rnd "$tmp/b6/packs/maps.pck" 1200000; rm "$tmp/b6/data/old.txt"
cp -r "$tmp/b6" "$tmp/b7"; mk "$tmp/b7" "game 0.7.0"; echo new > "$tmp/b7/data/new.txt"
printf '# notes\n- x\n' > "$tmp/notes.md"
feed() { "$here/tools/make_update_feed.sh" "$@" > /dev/null 2>&1 || { echo "feed build failed"; exit 1; }; }
feed v0.5.0 "$tmp/b5" "$tmp/b5" "$tmp/notes.md" "$tmp/host"

mkdir -p "$tmp/host"
python3 "$here/tests/range_server.py" "$port" "$tmp/host" 2> "$tmp/http.log" &
srv_pid=$!
for _ in $(seq 1 30); do curl -sf "http://127.0.0.1:$port/version.json" > /dev/null && break; sleep 0.2; done
printf '[launcher]\nversion_url="http://127.0.0.1:%s/version.json"\n' "$port" > "$tmp/launcher.cfg"
run() { timeout 90 "$godot" --headless --path "$here" -- --config "$tmp/launcher.cfg" --settings "$tmp/s.cfg" "$@"; }
G="$tmp/inst/game"

echo "[1] feed: groups and blobs"
check 'jq -e ".platforms.linux.files[] | select(.path==\"packs/heroes_hd.pck\") | .group == \"heroes_hd\"" "$tmp/host/version.json" > /dev/null' "heroes_hd group in the manifest"
check 'jq -e ".platforms.linux.groups.heroes_hd.optional and (.platforms.linux.groups.maps.optional|not)" "$tmp/host/version.json" > /dev/null' "group table: heroes_hd optional, maps required"
check '[[ -f "$tmp/host/blobs/$(sha "$tmp/b5/packs/maps.pck")" ]]' "blob stored by sha256"

echo "[2] first install (full zip) records a baseline"
expect_exit 0 "install 0.5.0" run --update-to "$tmp/inst"
check '[[ "$(cat "$G/installed_version.txt")" == 0.5.0 && -f "$G/packs/heroes_hd.pck" ]]' "0.5.0 with all packs"
check 'jq -e ".files | length == 7" "$G/installed_manifest.json" > /dev/null' "installed manifest written"

echo "[3] delta update 0.5.0 -> 0.6.0: pause after 300 KB at 256 KiB/s, then resume"
feed v0.6.0 "$tmp/b6" "$tmp/b6" "$tmp/notes.md" "$tmp/host"
: > "$tmp/http.log"
start=$(date +%s)
expect_exit 13 "paused mid-download" run --update-to "$tmp/inst" --pause-after 300000 --speed-limit 256
took=$(( $(date +%s) - start ))
check '[[ "$(cat "$G/installed_version.txt")" == 0.5.0 ]]' "still 0.5.0 while paused"
part="$(ls "$tmp/inst/downloads/blobs/"*.part 2>/dev/null | head -1)"
check '[[ -n "$part" && $(stat -c%s "$part") -ge 300000 && $(stat -c%s "$part") -lt 1200000 ]]' "partial blob kept ($( [[ -n "$part" ]] && stat -c%s "$part") bytes)"
check '[[ $took -ge 1 ]]' "speed limit slowed the transfer (${took}s for ~300 KB)"
expect_exit 0 "resume and finish" run --update-to "$tmp/inst"
check 'grep -q "GET /blobs/$(sha "$tmp/b6/packs/maps.pck") range=bytes=[1-9]" "$tmp/http.log"' "resumed with an HTTP Range request"
check '[[ "$(cat "$G/installed_version.txt")" == 0.6.0 && "$("$G/Cybergram.x86_64")" == "game 0.6.0" ]]' "0.6.0 installed and runs"
check 'cmp -s "$G/packs/maps.pck" "$tmp/b6/packs/maps.pck"' "changed pack swapped in"
check '[[ ! -e "$G/data/old.txt" && -f "$G/data/same.txt" ]]' "dropped file removed, unchanged kept"
check '[[ "$(gets "$(sha "$tmp/b6/packs/heroes_hd.pck")")" == 0 && "$(gets "$(sha "$tmp/b6/Cybergram.pck")")" == 0 ]]' "unchanged files not downloaded"
check '! grep -q "Cybergram-v0.6.0-linux" "$tmp/http.log"' "no full zip fetched"
check '[[ ! -e "$tmp/inst/game.stage" && ! -e "$tmp/inst/game.undo" && ! -e "$tmp/inst/downloads/blobs" ]]' "no staging leftovers"

echo "[4] optional pack off / on"
expect_exit 0 "turn HD hero textures off" run --install-root "$tmp/inst" --set-pack heroes_hd=off
check '[[ ! -e "$G/packs/heroes_hd.pck" ]] && grep -q heroes_hd "$tmp/inst/content.cfg"' "pack deleted, choice saved"
expect_exit 0 "check: still current without the pack" run --check-only --install-root "$tmp/inst"
: > "$tmp/http.log"
expect_exit 0 "turn HD hero textures on" run --install-root "$tmp/inst" --set-pack heroes_hd=on
check 'cmp -s "$G/packs/heroes_hd.pck" "$tmp/b6/packs/heroes_hd.pck"' "pack downloaded again"
check '[[ "$(grep -c "GET /blobs/" "$tmp/http.log")" == 1 ]]' "only that pack was downloaded"
expect_exit 1 "required pack cannot be removed" run --install-root "$tmp/inst" --set-pack maps=off

echo "[5] Lite first install"
mkdir -p "$tmp/lite"; printf '[content]\nskip=PackedStringArray("heroes_hd")\n' > "$tmp/lite/content.cfg"
expect_exit 0 "lite install" run --update-to "$tmp/lite"
check '[[ "$(cat "$tmp/lite/game/installed_version.txt")" == 0.6.0 && -f "$tmp/lite/game/packs/maps.pck" && ! -e "$tmp/lite/game/packs/heroes_hd.pck" ]]' "installed without heroes_hd"

echo "[6] repair re-downloads only the broken file"
echo broken > "$G/data/same.txt"
: > "$tmp/http.log"
expect_exit 0 "repair" run --repair --install-root "$tmp/inst"
check '[[ "$(cat "$G/data/same.txt")" == same && "$(grep -c "GET /blobs/" "$tmp/http.log")" == 1 ]]' "one file fetched and restored"

echo "[6b] blobs behind an HTTP redirect"
cp "$tmp/host/version.json" "$tmp/v6.json"
jq '.blobs = "r/blobs/"' "$tmp/v6.json" > "$tmp/host/version.json"
echo broken > "$G/data/same.txt"
: > "$tmp/http.log"
expect_exit 0 "repair through a redirect" run --repair --install-root "$tmp/inst"
check '[[ "$(cat "$G/data/same.txt")" == same ]] && grep -q "GET /r/blobs/" "$tmp/http.log"' "redirect followed"
cp "$tmp/v6.json" "$tmp/host/version.json"

echo "[7] corrupt blob on the host: old install survives"
cp -r "$tmp/inst" "$tmp/inst2"
mk "$tmp/b6b" "game 0.6.1"; cp -r "$tmp/b6/packs" "$tmp/b6/data" "$tmp/b6/Cybergram.pck" "$tmp/b6b/"
feed v0.6.1 "$tmp/b6b" "$tmp/b6b" "$tmp/notes.md" "$tmp/host2"
cp -r "$tmp/host2/blobs/." "$tmp/host/blobs/"; cp "$tmp/host/version.json" "$tmp/v6.json"; cp "$tmp/host2/version.json" "$tmp/host/version.json"
echo evil > "$tmp/host/blobs/$(sha "$tmp/b6b/Cybergram.x86_64")"
expect_exit 1 "update with a corrupt file fails" run --update-to "$tmp/inst2"
check '[[ "$(cat "$tmp/inst2/game/installed_version.txt")" == 0.6.0 && "$("$tmp/inst2/game/Cybergram.x86_64")" == "game 0.6.0" ]]' "0.6.0 untouched"
cp "$tmp/v6.json" "$tmp/host/version.json"

echo "[8] pre-load 0.7.0, activate at 2030-01-01T00:00:00Z"
NEXT_VERSION=v0.7.0 NEXT_WIN_DIR="$tmp/b7" NEXT_LIN_DIR="$tmp/b7" NEXT_ACTIVATE_AT=2030-01-01T00:00:00Z \
  feed v0.6.0 "$tmp/b6" "$tmp/b6" "$tmp/notes.md" "$tmp/host"
check 'jq -e ".next.version == \"0.7.0\" and .next.activate_at == \"2030-01-01T00:00:00Z\"" "$tmp/host/version.json" > /dev/null' "feed carries the next block"
expect_exit 0 "pre-load" run --preload --install-root "$tmp/inst"
check 'grep -q "Pre-loaded 0.7.0, ready at" "$tmp/out.log"' "pre-load status line"
check '[[ -f "$tmp/inst/preload/ready.json" && "$(cat "$G/installed_version.txt")" == 0.6.0 ]]' "staged, not activated"
: > "$tmp/http.log"
expect_exit 0 "pre-load again is a no-op" run --preload --install-root "$tmp/inst"
check '[[ "$(grep -c "GET /blobs/" "$tmp/http.log")" == 0 ]]' "nothing downloaded twice"
expect_exit 0 "check before the time" run --check-only --install-root "$tmp/inst" --now 2029-12-31T23:59:00Z
check '[[ "$(cat "$G/installed_version.txt")" == 0.6.0 ]]' "not active before activate_at"
kill "$srv_pid" 2>/dev/null; wait "$srv_pid" 2>/dev/null; srv_pid=""
expect_exit 20 "offline check after the time" run --check-only --install-root "$tmp/inst" --now 2030-01-01T00:00:05Z
check '[[ "$(cat "$G/installed_version.txt")" == 0.7.0 && "$("$G/Cybergram.x86_64")" == "game 0.7.0" && -f "$G/data/new.txt" ]]' "activated offline on the next launch"
check '[[ ! -e "$tmp/inst/preload" ]]' "pre-load cache cleared"
python3 "$here/tests/range_server.py" "$port" "$tmp/host" 2> "$tmp/http.log" &
srv_pid=$!
for _ in $(seq 1 30); do curl -sf "http://127.0.0.1:$port/version.json" > /dev/null && break; sleep 0.2; done
expect_exit 0 "online check: ahead of the feed counts as current" run --check-only --install-root "$tmp/inst"

echo "[9] uninstall keeps or deletes settings"
expect_exit 0 "uninstall" run --uninstall --keep-settings --install-root "$tmp/lite"
check '[[ ! -e "$tmp/lite/game" && ! -e "$tmp/lite/content.cfg" ]]' "game removed"

echo "[10] AppImage self-update"
mkdir -p "$tmp/ai" "$tmp/lw" "$tmp/ll"
echo cfg > "$tmp/lw/launcher.cfg"; echo cfg > "$tmp/ll/launcher.cfg"; echo exe > "$tmp/lw/CybergramLauncher.exe"; echo exe > "$tmp/ll/CybergramLauncher.x86_64"
printf '#!/bin/sh\necho new appimage\n' > "$tmp/ai/Cybergram-0.7.0-x86_64.AppImage"
APPIMAGE_FILE="$tmp/ai/Cybergram-0.7.0-x86_64.AppImage" feed v0.7.0 "$tmp/b7" "$tmp/b7" "$tmp/notes.md" "$tmp/host" "$tmp/lw" "$tmp/ll"
check 'jq -e ".launcher.platforms.linux.appimage.file == \"Cybergram-0.7.0-x86_64.AppImage\" and (.launcher.platforms.linux.appimage.sha256|length)==64" "$tmp/host/version.json" > /dev/null' "feed lists the AppImage + sha256"
mkdir -p "$tmp/apps"; printf '#!/bin/sh\necho old appimage\n' > "$tmp/apps/Cybergram.AppImage"; chmod +x "$tmp/apps/Cybergram.AppImage"
APPIMAGE="$tmp/apps/Cybergram.AppImage" expect_exit 0 "AppImage replaced" run --self-update --launcher-version 0.6.0 --install-root "$tmp/inst" --launcher-dir "$tmp/apps"
check '[[ "$("$tmp/apps/Cybergram.AppImage")" == "new appimage" && ! -e "$tmp/apps/Cybergram.AppImage.new" ]]' "new AppImage in place and executable"
jq '.launcher.platforms.linux.appimage.sha256 = "'"$(printf '0%.0s' {1..64})"'"' "$tmp/host/version.json" > "$tmp/v.json" && cp "$tmp/v.json" "$tmp/host/version.json"
printf '#!/bin/sh\necho old appimage\n' > "$tmp/apps/Cybergram.AppImage"
APPIMAGE="$tmp/apps/Cybergram.AppImage" expect_exit 1 "AppImage with a bad sha256 refused" run --self-update --launcher-version 0.6.0 --install-root "$tmp/inst" --launcher-dir "$tmp/apps"
check '[[ "$("$tmp/apps/Cybergram.AppImage")" == "old appimage" ]]' "old AppImage untouched"

echo
[[ "$fails" == 0 ]] && echo "E2E UPD PASS" || echo "E2E UPD FAILED ($fails)"
exit "$fails"
