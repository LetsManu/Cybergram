#!/usr/bin/env bash
# Builds the update feed the server container serves on TCP 8080:
#   <out>/Cybergram-<version>-windows-x86_64.zip
#   <out>/Cybergram-<version>-linux-x86_64.zip
#   <out>/version.json   (version, notes_md, per-platform file/size/sha256/exe and
#                         files = [{path,size,sha256}] of every file inside the zip,
#                         the manifest the launcher verifies an install against)
#   Optional launcher self-update (args 6 and 7):
#   <out>/CybergramLauncher-<version>-{windows,linux}-x86_64.zip and a
#   "launcher":{version,platforms:{windows|linux:{file,size,sha256,exe}}} section.
# Usage: make_update_feed.sh <version> <windows_dir> <linux_dir> <notes.md> <out_dir> [<launcher_windows_dir> <launcher_linux_dir>]
# Needs: zip, jq, sha256sum. Used by the release workflow and the e2e test.
set -euo pipefail
if [[ $# -ne 5 && $# -ne 7 ]]; then
  echo "usage: $0 <version> <windows_dir> <linux_dir> <notes.md> <out_dir> [<launcher_windows_dir> <launcher_linux_dir>]" >&2
  exit 2
fi
tag="$1"; win="$2"; lin="$3"; notes="$4"; out="$5"
ver="${tag#v}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
rm -f "$out"/Cybergram-*.zip "$out"/CybergramLauncher-*.zip "$out/version.json"

pack() { # <platform> <dir> [prefix]
  local f="${3:-Cybergram}-$tag-$1-x86_64.zip"
  (cd "$2" && zip -q -r -X "$out/$f" .)
  echo "$f"
}
# Per-file manifest of a build dir as a JSON array (paths relative, sorted).
manifest() { # <dir>
  (cd "$1" && find . -type f -printf '%P\n' | LC_ALL=C sort | while IFS= read -r p; do
    printf '%s\t%s\t%s\n' "$p" "$(stat -c%s "$p")" "$(sha256sum "$p" | cut -d' ' -f1)"
  done) | jq -R -s -c 'split("\n") | map(select(length>0) | split("\t") | {path:.[0], size:(.[1]|tonumber), sha256:.[2]})'
}
wf="$(pack windows "$win")"
lf="$(pack linux "$lin")"
notes_text=""
[[ -f "$notes" ]] && notes_text="$(cat "$notes")" || notes_text="Cybergram $tag"

wl="$(manifest "$win")"; ll="$(manifest "$lin")"

jq -n \
  --argjson wl "$wl" --argjson ll "$ll" \
  --arg version "$ver" --arg notes "$notes_text" \
  --arg wf "$wf" --argjson ws "$(stat -c%s "$out/$wf")" --arg wh "$(sha256sum "$out/$wf" | cut -d' ' -f1)" \
  --arg lf "$lf" --argjson ls "$(stat -c%s "$out/$lf")" --arg lh "$(sha256sum "$out/$lf" | cut -d' ' -f1)" \
  '{version:$version, notes_md:$notes, platforms:{
     windows:{file:$wf,size:$ws,sha256:$wh,exe:"Cybergram.exe",files:$wl},
     linux:{file:$lf,size:$ls,sha256:$lh,exe:"Cybergram.x86_64",files:$ll}}}' > "$out/version.json"
echo "feed written to $out"

# Optional launcher section (self-update).
if [[ $# -eq 7 ]]; then
  lw="$(pack windows "$6" CybergramLauncher)"
  ln="$(pack linux "$7" CybergramLauncher)"
  jq --arg v "$ver" \
    --arg wf "$lw" --argjson ws "$(stat -c%s "$out/$lw")" --arg wh "$(sha256sum "$out/$lw" | cut -d' ' -f1)" \
    --arg lf "$ln" --argjson ls "$(stat -c%s "$out/$ln")" --arg lh "$(sha256sum "$out/$ln" | cut -d' ' -f1)" \
    '.launcher = {version:$v, platforms:{
       windows:{file:$wf,size:$ws,sha256:$wh,exe:"CybergramLauncher.exe"},
       linux:{file:$lf,size:$ls,sha256:$lh,exe:"CybergramLauncher.x86_64"}}}' \
    "$out/version.json" > "$out/version.json.tmp" && mv "$out/version.json.tmp" "$out/version.json"
  echo "launcher section added ($lw, $ln)"
fi
