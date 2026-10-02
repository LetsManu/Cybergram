#!/usr/bin/env bash
# Imports the project and runs the gdUnit4 suite headless.
# Exit code: 0 pass; gdUnit4 uses 100/101/105 for failures.
set -euo pipefail
godot="${GODOT:-godot}"
"$godot" --headless --path . --import >/dev/null 2>&1 || true
"$godot" --headless --path . -s -d res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  -a res://tests --ignoreHeadlessMode -c
