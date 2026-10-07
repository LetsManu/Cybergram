#!/usr/bin/env bash
# "Launch and look" evidence capture: renders a scene for N frames under a
# virtual display and keeps the last frame as a PNG.
# Usage: tools/ci/capture_scene.sh <res://scene.tscn|""> <out.png> [frames] [user args...]
# Extra args are passed to the game after "--" (e.g. --map slice). [user args...]
#   Extra args after [frames] reach the game as user args (after "--"), e.g.
#   tools/ci/capture_scene.sh "" out.png 150 --autofire
# RESOLUTION=1920x1080 renders at another size (default 1280x720).
# Without Vulkan (CI, cloud containers) Godot falls back to OpenGL
# (gl_compatibility) automatically; the overlay reports the active renderer.
set -euo pipefail
godot="${GODOT:-godot}"
scene="${1:-}"
out="$2"
frames="${3:-10}"
res="${RESOLUTION:-1280x720}"
tmp="$(mktemp -d)"
args=(--path . --resolution "$res" --write-movie "$tmp/frame.png" --quit-after "$frames")
[[ -n "$scene" ]] && args+=("$scene")
shift $(( $# < 3 ? $# : 3 ))
(( $# > 0 )) && args+=(-- "$@")
if [[ $# -gt 3 ]]; then
  args+=(-- "${@:4}")
fi
xvfb-run -a -s "-screen 0 ${res}x24" "$godot" "${args[@]}" >/dev/null 2>&1
mkdir -p "$(dirname "$out")"
last="$(ls "$tmp"/frame*.png | sort | tail -n 1)"
cp "$last" "$out"
find "$tmp" -type f -delete
rmdir "$tmp"
echo "captured $out"
