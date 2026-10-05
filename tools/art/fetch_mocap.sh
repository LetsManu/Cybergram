#!/usr/bin/env bash
# Fetches the CMU mocap BVH trials used by tools/art/mocap.py into
# tools/art/.cache/cmu (gitignored). Source: the CMU Graphics Lab Motion Capture
# Database (mocap.cs.cmu.edu), BVH conversion by Bruce Hahne (cgspeed), mirrored
# at github.com/una-dinosauria/cmu-mocap (pinned commit). Credit line and the
# per-clip trial table: assets/models/heroes/LICENSES.md.
set -euo pipefail
COMMIT=09a07f54f3
BASE="https://raw.githubusercontent.com/una-dinosauria/cmu-mocap"
OUT="$(cd "$(dirname "$0")" && pwd)/.cache/cmu"
mkdir -p "$OUT"
sha="$(git ls-remote https://github.com/una-dinosauria/cmu-mocap HEAD | cut -f1)"
case "$sha" in "$COMMIT"*) ;; *) echo "note: mirror HEAD moved to $sha (pinned $COMMIT)";; esac
for t in 16_15 16_35 16_01 40_10 90_16 77_18; do
  s="${t%%_*}"
  [ -s "$OUT/$t.bvh" ] || curl -sSfL "$BASE/$sha/data/0$s/$t.bvh" -o "$OUT/$t.bvh"
done
echo "CMU BVH trials at $OUT"
