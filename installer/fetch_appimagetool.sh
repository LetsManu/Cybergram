#!/usr/bin/env bash
# Downloads the pinned appimagetool into <dir> and verifies its checksum.
# Usage: installer/fetch_appimagetool.sh <dir>   (prints the path)
set -euo pipefail
URL="https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-x86_64.AppImage"
SHA256="ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0"
mkdir -p "$1"; f="$1/appimagetool-x86_64.AppImage"
if [[ ! -f "$f" ]] || ! echo "$SHA256  $f" | sha256sum -c --status; then
  curl -sSL --retry 4 -o "$f" "$URL"
fi
echo "$SHA256  $f" | sha256sum -c --status || { echo "appimagetool checksum mismatch" >&2; exit 1; }
chmod +x "$f"; echo "$f"
