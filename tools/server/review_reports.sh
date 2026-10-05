#!/usr/bin/env bash
# Owner tool: list, resolve and purge post-match reports (W17-MM).
#   tools/server/review_reports.sh list [--all]
#   tools/server/review_reports.sh resolve r12 warned
#   tools/server/review_reports.sh purge
#   tools/server/review_reports.sh --dir /data/reports show r12
# In the container: docker exec cybergram /opt/cybergram/review_reports.sh list
# GODOT selects the binary (default: godot on PATH, from a source checkout).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
godot="${GODOT:-godot}"
exec "$godot" --headless --path "$root" --script res://tools/server/review_reports.gd -- "$@"
