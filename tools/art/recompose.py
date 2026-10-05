#!/usr/bin/env python3
"""Re-runs only the numpy albedo/mask composite from saved Cycles passes (fast look-dev).
Build once with HERO_DEBUG=<dir> to save <key>_passes.npz, then:
    python tools/art/recompose.py <dir>/<key>_passes.npz <key> [size]"""
import os
import sys

import bpy  # noqa: F401  (provides mathutils for hero_defs)
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hero_defs  # noqa: E402
import hero_hd  # noqa: E402

npz, key = sys.argv[1], sys.argv[2]
size = int(sys.argv[3]) if len(sys.argv) > 3 else 1024
d = np.load(npz)
root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
out = os.path.join(root, "assets", "models", "heroes", key)
print(hero_hd.composite(hero_defs.HEROES[key], out, size, *(d[k] for k in ("col", "mat", "et", "aoe", "P", "N", "nrm"))))
