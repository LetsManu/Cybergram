#!/usr/bin/env bash
# Builds the update feed the server container serves on TCP 8080:
#   <out>/Cybergram-<version>-windows-x86_64.zip
#   <out>/Cybergram-<version>-linux-x86_64.zip
#   <out>/version.json   (version, notes_md, per-platform file/size/sha256/exe and
#                         files = [{path,size,sha256}] of every file inside the zip,
#                         the manifest the launcher verifies an install against)
#   <out>/blobs/<sha256>  every file of both builds, named by its hash (W15-UPD
#                         delta updates: the launcher fetches only changed files;
#                         each files[] entry also carries its pack "group":
#                         packs/<name>.pck -> <name>, everything else -> core)
#   Optional launcher self-update (args 6 and 7):
#   <out>/CybergramLauncher-<version>-{windows,linux}-x86_64.zip and a
#   "launcher":{version,platforms:{windows|linux:{file,size,sha256,exe}}} section.
# Optional (environment, W15-UPD):
#   NEXT_VERSION, NEXT_WIN_DIR, NEXT_LIN_DIR, NEXT_ACTIVATE_AT (ISO UTC, e.g.
#     2026-10-12T18:00:00Z): adds a "next" block the launcher pre-loads and
#     activates at that time; its files go to blobs/ too.
#   APPIMAGE_FILE: the new Cybergram-<v>-x86_64.AppImage; copied to <out> and
#     listed as launcher.platforms.linux.appimage {file,size,sha256} (needs args 6+7).
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
rm -f "$out"/Cybergram-*.zip "$out"/CybergramLauncher-*.zip "$out/version.json" "$out/version.json.sig"

pack() { # <platform> <dir> [prefix]
  local f="${3:-Cybergram}-$tag-$1-x86_64.zip"
  (cd "$2" && zip -q -r -X "$out/$f" .)
  echo "$f"
}
# Per-file manifest of a build dir as a JSON array (paths relative, sorted),
# with the pack group of each file; also stores every file in <out>/blobs.
mkdir -p "$out/blobs"
manifest() { # <dir>
  (cd "$1" && find . -type f -printf '%P\n' | LC_ALL=C sort | while IFS= read -r p; do
    h="$(sha256sum "$p" | cut -d' ' -f1)"
    [[ -f "$out/blobs/$h" ]] || cp "$p" "$out/blobs/$h"
    g=core
    [[ "$p" =~ ^packs/([^/]+)\.pck$ ]] && g="${BASH_REMATCH[1]}"
    printf '%s\t%s\t%s\t%s\n' "$p" "$(stat -c%s "$p")" "$h" "$g"
  done) | jq -R -s -c 'split("\n") | map(select(length>0) | split("\t") | {path:.[0], size:(.[1]|tonumber), sha256:.[2], group:.[3]})'
}
# {group: {size, optional}} of a manifest array.
groups='reduce .[] as $f ({}; .[$f.group].size += $f.size | .[$f.group].optional = ($f.group != "core" and $f.group != "maps"))'
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
  "{version:\$version, notes_md:\$notes, blobs:\"blobs/\", platforms:{
     windows:{file:\$wf,size:\$ws,sha256:\$wh,exe:\"Cybergram.exe\",files:\$wl,groups:(\$wl|$groups)},
     linux:{file:\$lf,size:\$ls,sha256:\$lh,exe:\"Cybergram.x86_64\",files:\$ll,groups:(\$ll|$groups)}}}" > "$out/version.json"
echo "feed written to $out"

# Optional pre-load block (the next patch, activated at NEXT_ACTIVATE_AT).
if [[ -n "${NEXT_VERSION:-}" ]]; then
  [[ -d "${NEXT_WIN_DIR:-}" && -d "${NEXT_LIN_DIR:-}" && "${NEXT_ACTIVATE_AT:-}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}(:[0-9]{2})?Z$ ]] \
    || { echo "NEXT_VERSION needs NEXT_WIN_DIR, NEXT_LIN_DIR and NEXT_ACTIVATE_AT (YYYY-MM-DDTHH:MM:SSZ)" >&2; exit 2; }
  nwl="$(manifest "$NEXT_WIN_DIR")"; nll="$(manifest "$NEXT_LIN_DIR")"
  jq --argjson wl "$nwl" --argjson ll "$nll" --arg v "${NEXT_VERSION#v}" --arg at "$NEXT_ACTIVATE_AT" \
    ".next = {version:\$v, activate_at:\$at, platforms:{
       windows:{exe:\"Cybergram.exe\",files:\$wl,groups:(\$wl|$groups)},
       linux:{exe:\"Cybergram.x86_64\",files:\$ll,groups:(\$ll|$groups)}}}" \
    "$out/version.json" > "$out/version.json.tmp" && mv "$out/version.json.tmp" "$out/version.json"
  echo "next block added (${NEXT_VERSION#v} at $NEXT_ACTIVATE_AT)"
fi

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
  if [[ -n "${APPIMAGE_FILE:-}" ]]; then
    ai="$(basename "$APPIMAGE_FILE")"
    [[ "$ai" == *.AppImage ]] || { echo "APPIMAGE_FILE must end in .AppImage" >&2; exit 2; }
    [[ "$(readlink -f "$APPIMAGE_FILE")" == "$out/$ai" ]] || cp "$APPIMAGE_FILE" "$out/$ai"
    jq --arg f "$ai" --argjson s "$(stat -c%s "$out/$ai")" --arg h "$(sha256sum "$out/$ai" | cut -d' ' -f1)" \
      '.launcher.platforms.linux.appimage = {file:$f,size:$s,sha256:$h}' \
      "$out/version.json" > "$out/version.json.tmp" && mv "$out/version.json.tmp" "$out/version.json"
    echo "AppImage listed ($ai)"
  fi
fi

# Optional signature (W11-Q1 SEC-010): FEED_SIGNING_KEY_FILE = ECDSA P-256
# private key (PEM). Writes version.json.sig = base64(DER ECDSA/SHA-256 over
# the exact bytes of version.json), then checks it with the public half.
if [[ -n "${FEED_SIGNING_KEY_FILE:-}" ]]; then
  openssl dgst -sha256 -sign "$FEED_SIGNING_KEY_FILE" "$out/version.json" | base64 -w0 > "$out/version.json.sig"
  openssl ec -in "$FEED_SIGNING_KEY_FILE" -pubout 2>/dev/null > "$out/.feed_pub.pem"
  base64 -d "$out/version.json.sig" > "$out/.feed_sig.der"
  openssl dgst -sha256 -verify "$out/.feed_pub.pem" -signature "$out/.feed_sig.der" "$out/version.json" >/dev/null \
    || { rm -f "$out/.feed_pub.pem" "$out/.feed_sig.der"; echo "feed signature self-check FAILED" >&2; exit 1; }
  rm -f "$out/.feed_pub.pem" "$out/.feed_sig.der"
  echo "version.json signed (version.json.sig)"
else
  echo "WARNING: FEED_SIGNING_KEY_FILE not set; version.json is unsigned" >&2
fi
