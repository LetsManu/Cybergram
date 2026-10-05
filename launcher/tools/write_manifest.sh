#!/usr/bin/env bash
# Writes <game_dir>/installed_manifest.json: the per-file list ({path,size,sha256,group})
# the launcher uses as the baseline for delta updates (W15-UPD). The installers
# call it so the first update after an install is already per file.
# Usage: write_manifest.sh <game_dir>     Needs: jq, sha256sum.
set -euo pipefail
[[ $# -eq 1 && -d "$1" ]] || { echo "usage: $0 <game_dir>" >&2; exit 2; }
cd "$1"
find . -type f ! -name installed_manifest.json ! -name installed_version.txt -printf '%P\n' | LC_ALL=C sort | while IFS= read -r p; do
  g=core
  [[ "$p" =~ ^packs/([^/]+)\.pck$ ]] && g="${BASH_REMATCH[1]}"
  printf '%s\t%s\t%s\t%s\n' "$p" "$(stat -c%s "$p")" "$(sha256sum "$p" | cut -d' ' -f1)" "$g"
done | jq -R -s -c '{files: (split("\n") | map(select(length>0) | split("\t") | {path:.[0], size:(.[1]|tonumber), sha256:.[2], group:.[3]}))}' > installed_manifest.json
