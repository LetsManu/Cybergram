#!/usr/bin/env bash
# Downloads the pinned Godot editor build (headless-capable) and prints its path.
# Usage: GODOT_VERSION=4.7-stable tools/ci/install_godot.sh [install_dir]
set -euo pipefail
version="${GODOT_VERSION:-4.7-stable}"
dir="${1:-$HOME/godot}"
bin="$dir/Godot_v${version}_linux.x86_64"
if [[ ! -x "$bin" ]]; then
  mkdir -p "$dir"
  url="https://github.com/godotengine/godot/releases/download/${version}/Godot_v${version}_linux.x86_64.zip"
  curl -sSL --retry 4 -o "$dir/godot.zip" "$url"
  unzip -oq "$dir/godot.zip" -d "$dir"
  chmod +x "$bin"
fi
echo "$bin"
