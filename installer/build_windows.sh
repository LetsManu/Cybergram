#!/usr/bin/env bash
# Builds CybergramSetup-<version>.exe with makensis (apt install nsis).
# Usage: installer/build_windows.sh <version> <launcher_windows_dir> <game_windows_dir> <out_dir>
set -euo pipefail
[[ $# -eq 4 ]] || { echo "usage: $0 <version> <launcher_dir> <game_dir> <out_dir>" >&2; exit 2; }
ver="${1#v}"; launcher="$(cd "$2" && pwd)"; game="$(cd "$3" && pwd)"; mkdir -p "$4"; out="$(cd "$4" && pwd)"
num="$(echo "$ver" | sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+).*/\1/')"
[[ "$num" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || num="0.0.0"
here="$(cd "$(dirname "$0")" && pwd)"
(cd "$here/windows" && makensis -V2 -DVERSION="$ver" -DVERSION_NUM="$num" -DLAUNCHER_DIR="$launcher" \
  -DGAME_DIR="$game" -DOUTFILE="$out/CybergramSetup-$ver.exe" cybergram.nsi)
test -s "$out/CybergramSetup-$ver.exe"
ls -la "$out/CybergramSetup-$ver.exe"
