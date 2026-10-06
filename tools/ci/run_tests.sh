#!/usr/bin/env bash
# Imports the project and runs the gdUnit4 suite headless.
# Exit code: 0 pass; gdUnit4 uses 100/101/105 for failures; 124 = the run hung
# and was stopped after RUN_TESTS_TIMEOUT seconds (default 900).
# Optional args are passed as gdUnit -a paths (default: res://tests).
set -euo pipefail
godot="${GODOT:-godot}"
limit="${RUN_TESTS_TIMEOUT:-900}"
timeout 600 "$godot" --headless --path . --import >/dev/null 2>&1 || true
paths=("$@"); [[ ${#paths[@]} -eq 0 ]] && paths=(res://tests)
args=(); for p in "${paths[@]}"; do args+=(-a "$p"); done
rc=0
timeout --kill-after=30 "$limit" "$godot" --headless --path . -s -d res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  "${args[@]}" --ignoreHeadlessMode -c || rc=$?
if [[ $rc -eq 124 || $rc -eq 137 ]]; then
  echo "::error::test run did not finish within ${limit}s (a test or script error hung the run)" >&2
fi
exit $rc
