#!/usr/bin/env bash
# Renders the launcher key-art loops (W15-UX): one `showcase` idle loop per
# hero from the game's rigged models, then encodes Ogg Theora into
# launcher/assets/keyart/<hero>.ogv (portrait crop, 540 px tall, black
# background; the launcher blends them additively).
# Needs: godot, xvfb-run, ffmpeg with libtheora. Usage: tools/art/make_keyart_loops.sh [hero ...]
set -euo pipefail
godot="${GODOT:-godot}"
here="$(cd "$(dirname "$0")/../.." && pwd)"
heroes=("$@"); [[ ${#heroes[@]} -eq 0 ]] && heroes=(brannoc sable vesper_loom)
out="$here/launcher/assets/keyart"
mkdir -p "$out"
for h in "${heroes[@]}"; do
  tmp="$(mktemp -d)"
  xvfb-run -a -s "-screen 0 1280x720x24" timeout 300 "$godot" --path "$here" --rendering-driver opengl3 --resolution 1280x720 \
    --fixed-fps 24 --write-movie "$tmp/f.png" --quit-after 125 -s res://tools/art/render_keyart_loop.gd -- --hero "$h" > "$tmp/log.txt" 2>&1 || true
  # Frames 2..121 = one 5 s clip at 24 fps.
  ffmpeg -y -loglevel error -framerate 24 -start_number 2 -i "$tmp/f%08d.png" -frames:v 120 \
    -vf "crop=480:700:400:10,scale=-2:540" -c:v libtheora -q:v 7 -pix_fmt yuv420p "$out/$h.ogv"
  echo "$h: $(du -h "$out/$h.ogv" | cut -f1)"
  find "$tmp" -type f -delete
  rmdir "$tmp"
done
