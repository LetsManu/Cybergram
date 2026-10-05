#!/usr/bin/env bash
# Owner tool: list, resolve and purge post-match reports (W17-MM).
#   tools/server/review_reports.sh list [--all]
#   tools/server/review_reports.sh resolve r12 warned
#   tools/server/review_reports.sh purge
#   tools/server/review_reports.sh --dir /data/reports show r12
# In the container (W17B-OPS): the exported game binary runs the script file
# that sits next to this wrapper, so no source checkout is needed:
#   docker exec cybergram /opt/review_reports.sh list
# From a source checkout: GODOT selects the binary (default: godot on PATH).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
bin=/opt/cybergram/Cybergram.x86_64
if [[ -x "$bin" && -f "$here/review_reports.gd" && "$here" == /opt ]]; then
  cd /opt/cybergram
  exec "$bin" --headless --script "$here/review_reports.gd" -- "$@"
fi
root="$(cd "$here/../.." && pwd)"
godot="${GODOT:-godot}"
exec "$godot" --headless --path "$root" --script res://tools/server/review_reports.gd -- "$@"
