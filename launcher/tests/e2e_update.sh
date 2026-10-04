#!/usr/bin/env bash
# End-to-end update test: fake old install + local update host (port 8090) +
# launcher in headless mode. Run from anywhere:
#   GODOT=~/godot/Godot_v4.7-stable_linux.x86_64 launcher/tests/e2e_update.sh
# Needs zip, jq, python3. Exit 0 = all checks passed.
set -uo pipefail
godot="${GODOT:-godot}"
here="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
port=8090
fails=0
srv_pid=""
cleanup() {
  [[ -n "$srv_pid" ]] && kill "$srv_pid" 2>/dev/null
  rm -rf "$tmp"
}
trap cleanup EXIT

ok() { echo "  ok: $1"; }
bad() { echo "  FAIL: $1"; fails=$((fails + 1)); }
expect_exit() { # <want> <label> <cmd...>
  local want="$1" label="$2"; shift 2
  "$@" > "$tmp/out.log" 2>&1
  local got=$?
  tail -n 6 "$tmp/out.log" | grep "LAUNCHER" | head -4
  [[ "$got" == "$want" ]] && ok "$label (exit $got)" || bad "$label (exit $got, wanted $want)"
}

# --- fake builds and feed ---------------------------------------------------
for d in win lin; do mkdir -p "$tmp/$d/data"; echo "payload 0.5.0" > "$tmp/$d/data/x.txt"; done
printf '#!/bin/sh\necho "fake game 0.5.0"\n' > "$tmp/lin/Cybergram.x86_64"
echo "fake exe" > "$tmp/win/Cybergram.exe"
printf '# v0.5.0\n- **new** thing\n' > "$tmp/notes.md"
"$here/tools/make_update_feed.sh" v0.5.0 "$tmp/win" "$tmp/lin" "$tmp/notes.md" "$tmp/host" > /dev/null || { echo "feed build failed"; exit 1; }

# --- fake old install ---------------------------------------------------------
mkdir -p "$tmp/install/game"
printf '#!/bin/sh\necho "old game"\n' > "$tmp/install/game/Cybergram.x86_64"
chmod +x "$tmp/install/game/Cybergram.x86_64"
echo "0.4.1" > "$tmp/install/game/installed_version.txt"
echo "stale file" > "$tmp/install/game/stale.txt"

printf '[launcher]\nversion_url="http://127.0.0.1:%s/version.json"\n' "$port" > "$tmp/launcher.cfg"
run() { timeout 60 "$godot" --headless --path "$here" -- --config "$tmp/launcher.cfg" "$@"; }

# --- 1. host down: offline -----------------------------------------------------
echo "[1] offline"
expect_exit 20 "check-only with host down" run --check-only --install-root "$tmp/install"

(cd "$tmp/host" && exec python3 -m http.server "$port" --bind 127.0.0.1 > "$tmp/http.log" 2>&1) &
srv_pid=$!
for _ in $(seq 1 30); do curl -sf "http://127.0.0.1:$port/version.json" > /dev/null && break; sleep 0.2; done

# --- 2. update available -----------------------------------------------------
echo "[2] check, then update"
expect_exit 10 "check-only sees 0.4.1 -> 0.5.0" run --check-only --install-root "$tmp/install"
expect_exit 0 "update-to installs" run --update-to "$tmp/install"
[[ "$(cat "$tmp/install/game/installed_version.txt")" == "0.5.0" ]] && ok "version file is 0.5.0" || bad "version file"
[[ "$(cat "$tmp/install/game/data/x.txt")" == "payload 0.5.0" ]] && ok "payload unpacked" || bad "payload"
[[ ! -e "$tmp/install/game/stale.txt" ]] && ok "stale file gone" || bad "stale file kept"
[[ -x "$tmp/install/game/Cybergram.x86_64" ]] && ok "exe is executable" || bad "exe not executable"
[[ "$("$tmp/install/game/Cybergram.x86_64")" == "fake game 0.5.0" ]] && ok "new exe runs" || bad "new exe output"
[[ ! -e "$tmp/install/game.new" && ! -e "$tmp/install/game.old" ]] && ok "no leftovers" || bad "game.new/game.old left"
expect_exit 0 "check-only now current" run --check-only --install-root "$tmp/install"

# --- 3. first run (nothing installed) -----------------------------------------
echo "[3] first run"
expect_exit 0 "fresh install" run --update-to "$tmp/fresh"
[[ "$(cat "$tmp/fresh/game/installed_version.txt" 2>/dev/null)" == "0.5.0" ]] && ok "fresh install version" || bad "fresh install version"

# --- 4. corrupt download: old install must survive ----------------------------
echo "[4] bad checksum"
mkdir -p "$tmp/old2/game"
echo "0.4.1" > "$tmp/old2/game/installed_version.txt"
printf '#!/bin/sh\n' > "$tmp/old2/game/Cybergram.x86_64"
jq '.platforms.linux.sha256 = "deadbeef"' "$tmp/host/version.json" > "$tmp/host/v.tmp" && mv "$tmp/host/v.tmp" "$tmp/host/version.json"
expect_exit 1 "update with wrong sha256 fails" run --update-to "$tmp/old2"
[[ "$(cat "$tmp/old2/game/installed_version.txt")" == "0.4.1" ]] && ok "old install untouched" || bad "old install damaged"
[[ ! -e "$tmp/old2/game.new" ]] && ok "no staging dir left" || bad "staging dir left"

# --- 5. manifest, repair, move -------------------------------------------------
echo "[5] manifest + repair + move"
"$here/tools/make_update_feed.sh" v0.5.0 "$tmp/win" "$tmp/lin" "$tmp/notes.md" "$tmp/host" > /dev/null
jq -e '.platforms.linux.files | map(.path) | contains(["Cybergram.x86_64","data/x.txt"])' "$tmp/host/version.json" > /dev/null && ok "feed lists linux files" || bad "feed linux file list"
jq -e '.platforms.windows.files | map(.path) | contains(["Cybergram.exe"])' "$tmp/host/version.json" > /dev/null && ok "feed lists windows files" || bad "feed windows file list"
jq -e '.platforms.linux.files[] | select(.path=="data/x.txt") | .sha256 | length == 64' "$tmp/host/version.json" > /dev/null && ok "file sha256 present" || bad "file sha256"
expect_exit 0 "repair on intact install" run --repair --install-root "$tmp/install"
echo "tampered" > "$tmp/install/game/data/x.txt"
expect_exit 0 "repair fixes a tampered file" run --repair --install-root "$tmp/install"
[[ "$(cat "$tmp/install/game/data/x.txt")" == "payload 0.5.0" ]] && ok "tampered file restored" || bad "tampered file not restored"
rm "$tmp/install/game/data/x.txt"
expect_exit 0 "repair fixes a missing file" run --repair --install-root "$tmp/install"
[[ -f "$tmp/install/game/data/x.txt" ]] && ok "missing file restored" || bad "missing file not restored"
expect_exit 0 "move install" run --install-root "$tmp/install" --move-install-to "$tmp/moved"
[[ -f "$tmp/moved/game/data/x.txt" && ! -e "$tmp/install/game" ]] && ok "install moved" || bad "install not moved"
expect_exit 0 "moved install is current" run --check-only --install-root "$tmp/moved"

echo
[[ "$fails" == 0 ]] && echo "E2E PASS" || echo "E2E FAILED ($fails)"
exit "$fails"
