#!/usr/bin/env bash
# Captures a model showcase mode to a PNG (last of N frames) at a given size.
# Usage: tools/models/capture_showcase.sh <mode> <out.png> [frames] [WxH] [extra user args...]
set -euo pipefail
godot="${GODOT:-godot}"
mode="$1"; out="$2"; frames="${3:-30}"; res="${4:-1920x1080}"
shift $(( $# < 4 ? $# : 4 ))
tmp="$(mktemp -d)"
w="${res%x*}"; h="${res#*x}"
xvfb-run -a -s "-screen 0 ${w}x${h}x24" "$godot" --path . --resolution "$res" \
  --write-movie "$tmp/frame.png" --quit-after "$frames" \
  res://src/gameplay/views/models/model_showcase.tscn -- --showcase "$mode" "$@" 2>&1 | grep -E "ERROR|SCRIPT|PERF" | head -20 || true
mkdir -p "$(dirname "$out")"
cp "$(ls "$tmp"/frame*.png | sort | tail -n 1)" "$out"
rm -rf "$tmp"
echo "captured $out"
