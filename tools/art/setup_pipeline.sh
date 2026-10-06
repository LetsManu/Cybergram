#!/usr/bin/env bash
# Model pipeline setup (docs/model-pipeline.md): Blender 5.0 as a Python module
# (bpy) in a venv, plus the CMU mocap BVHs the heroes use. Idempotent: an
# existing venv with the pinned bpy is kept. World assets (tools/art/world/)
# need only the venv.
#   tools/art/setup_pipeline.sh            # venv at $CYBERGRAM_VENV (default /tmp/venv)
#   tools/art/setup_pipeline.sh --mocap    # also fetch the BVHs (heroes only)
# Prints the venv's python path on the last line.
set -euo pipefail
VENV="${CYBERGRAM_VENV:-/tmp/venv}"
BPY_VERSION="5.0.1"
here="$(cd "$(dirname "$0")" && pwd)"
py="$VENV/bin/python"
if ! "$py" -c "import bpy, sys; sys.exit(0 if bpy.app.version_string.startswith('${BPY_VERSION%.*}') else 1)" 2>/dev/null; then
  command -v python3.11 >/dev/null || { echo "setup_pipeline: python3.11 is required (bpy $BPY_VERSION wheels are cp311)" >&2; exit 1; }
  python3.11 -m venv "$VENV"
  "$VENV/bin/pip" install -q "bpy==$BPY_VERSION" pillow numpy
fi
"$py" -c "import bpy, numpy, PIL" || { echo "setup_pipeline: bpy/numpy/pillow import failed" >&2; exit 1; }
if [[ "${1:-}" == "--mocap" ]]; then
  "$here/fetch_mocap.sh"
fi
echo "$py"
