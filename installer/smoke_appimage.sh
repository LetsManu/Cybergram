#!/usr/bin/env bash
# Smoke test for the AppImage: extract it, run the launcher with --check-only against a local
# update feed, and check that the bundled game was copied to the per-user folder first.
# Usage: installer/smoke_appimage.sh <Cybergram-<ver>-x86_64.AppImage | extracted AppDir> <version>
# (an AppDir is accepted so the logic can be tested where AppImages cannot be run)
set -euo pipefail
src="$(readlink -f "$1")"; ver="${2#v}"
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"; srv=""
trap '[[ -n "$srv" ]] && kill "$srv" 2>/dev/null; rm -rf "$tmp"' EXIT
if [[ -d "$src" ]]; then app="$src"; else
  (cd "$tmp" && "$src" --appimage-extract > /dev/null); app="$tmp/squashfs-root"
fi
for f in AppRun cybergram.desktop cybergram.png usr/bin/CybergramLauncher.x86_64 usr/bin/launcher.cfg \
         usr/share/cybergram/game/Cybergram.x86_64 usr/share/cybergram/game/installed_version.txt; do
  [[ -e "$app/$f" ]] || { echo "FAIL: AppImage lacks $f"; exit 1; }
done
[[ -x "$app/AppRun" ]] || { echo "FAIL: AppRun not executable"; exit 1; }
# Local feed with the same version: the launcher must report "current" (exit 0).
mkdir -p "$tmp/w" "$tmp/l"
echo e > "$tmp/w/Cybergram.exe"; printf '#!/bin/sh\n' > "$tmp/l/Cybergram.x86_64"; printf '# v%s\n- test\n' "$ver" > "$tmp/notes.md"
"$here/../launcher/tools/make_update_feed.sh" "v$ver" "$tmp/w" "$tmp/l" "$tmp/notes.md" "$tmp/host" > /dev/null
port=8091
(cd "$tmp/host" && exec python3 -m http.server "$port" --bind 127.0.0.1 > /dev/null 2>&1) & srv=$!
for _ in $(seq 1 30); do curl -sf "http://127.0.0.1:$port/version.json" > /dev/null && break; sleep 0.2; done
printf '[launcher]\nversion_url="http://127.0.0.1:%s/version.json"\n' "$port" > "$tmp/launcher.cfg"
# APPIMAGE/APPDIR are what the AppImage runtime sets; they switch the launcher to AppImage mode.
export APPIMAGE="$src" APPDIR="$app" XDG_DATA_HOME="$tmp/data"
set +e
timeout 90 "$app/AppRun" --headless -- --check-only --config "$tmp/launcher.cfg" --settings "$tmp/s.cfg" > "$tmp/out.log" 2>&1
code=$?
set -e
tail -n 5 "$tmp/out.log"
[[ $code -eq 0 ]] || { echo "FAIL: --check-only exit $code (wanted 0 = current)"; exit 1; }
! grep -q "SCRIPT ERROR" "$tmp/out.log" || { echo "FAIL: script errors"; exit 1; }
[[ "$(cat "$tmp/data/cybergram/game/installed_version.txt")" == "$ver" ]] || { echo "FAIL: bundled game not seeded"; exit 1; }
[[ -x "$tmp/data/cybergram/game/Cybergram.x86_64" ]] || { echo "FAIL: seeded game not executable"; exit 1; }
echo "appimage smoke: ok"
