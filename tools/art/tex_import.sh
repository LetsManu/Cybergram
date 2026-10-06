#!/usr/bin/env bash
# W14: VRAM-compressed, mipmapped import settings for the baked hero texture sets
# (design/art/hero-art-bible.md §8). Run after the first `godot --import` created the
# .import files, then import again.
set -euo pipefail
cd "$(dirname "$0")/../.."
# P7: + the floor trim sheet (assets/textures/world/floor). The decal atlas is an
# "image" import (cut into decal textures at runtime), so it is not listed here.
for f in assets/models/heroes/*/*_{albedo,normal,mask}.png.import assets/models/world/*/*_{albedo,normal,mask}.png.import \
    assets/textures/world/floor/*_{albedo,normal,mask,height}.png.import; do
  [ -f "$f" ] || continue
  sed -i 's/^compress\/mode=.*/compress\/mode=2/; s/^mipmaps\/generate=.*/mipmaps\/generate=true/' "$f"
  sed -i "s/^process\/fix_alpha_border=.*/process\/fix_alpha_border=false/" "$f"
  case "$f" in
    *_normal.png.import) sed -i 's/^compress\/normal_map=.*/compress\/normal_map=1/' "$f" ;;
    *) sed -i 's/^compress\/normal_map=.*/compress\/normal_map=2/' "$f" ;;
  esac
done
echo "hero + world texture imports set: $(ls assets/models/{heroes,world}/*/*_{albedo,normal,mask}.png.import assets/textures/world/floor/*_{albedo,normal,mask,height}.png.import 2>/dev/null | wc -l) files"
