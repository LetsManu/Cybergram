#!/usr/bin/env bash
# Enforces the layer dependency direction from architecture.md §3:
#   core       -> nothing above it
#   gameplay   -> core only (never ui, ai)
#   networking -> core, gameplay (never ui, ai)
# A violation is a path reference to a forbidden layer (preload/load/extends).
set -uo pipefail
fail=0
check() {
  local layer="$1" forbidden="$2"
  [[ -d "src/$layer" ]] || return 0
  local hits
  hits="$(grep -rnE "res://src/($forbidden)/" "src/$layer" --include='*.gd' --include='*.tscn' || true)"
  if [[ -n "$hits" ]]; then
    echo "Layer violation: src/$layer must not reference src/{$forbidden}"
    echo "$hits"
    fail=1
  fi
}
check core "gameplay|networking|ai|ui"
check gameplay "ui|ai"
check networking "ui|ai"
[[ $fail -eq 0 ]] && echo "check_deps: OK"
exit $fail
