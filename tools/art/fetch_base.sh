#!/usr/bin/env bash
# Fetches the CC0 MakeHuman base (mesh, default rig, skin weights, a few macro
# targets) at a pinned commit into tools/art/.cache (gitignored).
# Licence and attribution: assets/models/heroes/LICENSES.md.
set -euo pipefail
COMMIT=a8bc2d54ff0ac92e78ff71431b1023eda42bf482
BASE="https://raw.githubusercontent.com/makehumancommunity/makehuman/${COMMIT}"
OUT="$(cd "$(dirname "$0")" && pwd)/.cache/makehuman"
mkdir -p "$OUT/targets"
get() { [ -s "$2" ] || curl -sSfL "$BASE/$1" -o "$2"; }
get LICENSE.ASSETS.md "$OUT/LICENSE.ASSETS.md"
get makehuman/data/3dobjs/base.obj "$OUT/base.obj"
get makehuman/data/rigs/default.mhskel "$OUT/default.mhskel"
get makehuman/data/rigs/default_weights.mhw "$OUT/default_weights.mhw"
for g in male female; do
  for m in averagemuscle maxmuscle; do
    for w in averageweight minweight; do
      get "makehuman/data/targets/macrodetails/universal-$g-young-$m-$w.target" \
          "$OUT/targets/universal-$g-young-$m-$w.target"
      get "makehuman/data/targets/macrodetails/proportions/$g-young-$m-$w-idealproportions.target" \
          "$OUT/targets/$g-young-$m-$w-idealproportions.target"
    done
  done
done
echo "MakeHuman CC0 base at $OUT"
