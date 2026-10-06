#!/usr/bin/env python3
"""Armory stall on the hero pipeline (design/art-bible.md §6.5 "a neon gun shop:
weapon racks, a holo display wall of crystals and chips, and a workbench";
brief: docs/assets/armory.md).

Owner decision 2026-10-06: the Armory is the LoL shop at the spawn. The stall
stands at the Sanctum's edge facing the spawn (HqDef.armory); the whole Sanctum
is the buy zone (EconomyRulesDef.shop_in_sanctum). Visual only (no collision),
so the navmesh is unchanged. ArmoryMarkerView adds the "ARMORY" text, the
floor ring and the beacon.

Blender space: Z up, front (customer side) = +Y, origin = floor centre of the
counter footprint.
Run:  /tmp/venv/bin/python tools/art/world/armory_stall.py [--notex] [--out <dir>]
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import world_kit  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

KEY = "armory_stall"
SEED = 4401
W = 5.0          # counter width
ROOF_Z = 3.6

PALETTE = {
    "stone": "#B9B2A6", "stone_dark": "#8A8292", "iron": "#3B4052", "iron_dark": "#2C3040",
    "chrome": "#C9D4E2", "brass": "#BFA68A", "panel": "#5A5370", "ink": "#1B1E2E",
    "wood": "#8C6A4E", "neon": "#F4F7FF", "team": "#2E86FF", "crystal": "#C77DFF",
}


def gun(a, c, length, rot_z=0.0, scale=1.0):
    """A rifle silhouette lying along X (rack display)."""
    m = Matrix.Translation(Vector(c)) @ Matrix.Rotation(math.radians(rot_z), 4, "Y")
    L = length * scale
    a.box("Root", None, (L * 0.5, 0.08 * scale, 0.14 * scale), "iron", bevel=0.3, mat=m)                   # receiver
    a.box("Root", None, (L * 0.45, 0.05 * scale, 0.05 * scale), "chrome", "chrome", bevel=0.3,
          mat=m @ Matrix.Translation((L * 0.45, 0, 0.03 * scale)))                                         # barrel
    a.box("Root", None, (L * 0.25, 0.07 * scale, 0.12 * scale), "wood", bevel=0.3, taper=(1.0, 0.7),
          mat=m @ Matrix.Translation((-L * 0.36, 0, -0.02 * scale)))                                       # stock
    a.box("Root", None, (0.05 * scale, 0.06 * scale, 0.14 * scale), "iron_dark", bevel=0.3,
          mat=m @ Matrix.Translation((-0.02 * L, 0, -0.12 * scale)))                                       # grip
    a.box("Root", None, (L * 0.18, 0.03 * scale, 0.03 * scale), "neon", "team_emit", bevel=0.3,
          mat=m @ Matrix.Translation((0.05 * L, 0.045 * scale, 0.02 * scale)))                              # mana strip


def build():
    rnd = random.Random(SEED)
    a = world_kit.WorldAsset(KEY, PALETTE, tex=1024, texel_m=0.008, paint={"edge": 0.65, "grit": 0.07})
    # platform + step
    a.box("Root", (0, -0.2, 0.08), (W + 0.6, 3.2, 0.16), "stone_dark", bevel=0.2)
    a.box("Root", (0, 1.45, 0.05), (W - 0.4, 0.5, 0.1), "stone", bevel=0.25)
    # counter: iron body, brass top, glass display with crystals and chips, team strip
    a.box("Root", (0, 0.7, 0.16 + 0.5), (W - 0.2, 0.75, 1.0), "iron", bevel=0.15)
    a.box("Root", (0, 0.7, 1.21), (W, 0.9, 0.1), "brass", "chrome", bevel=0.25)
    a.box("Root", (0, 1.08, 1.08), (W - 0.3, 0.04, 0.06), "neon", "team_emit", bevel=0.3)
    for k in range(4):
        x = -1.65 + k * 1.1
        a.box("Root", (x, 1.075, 0.62), (0.9, 0.03, 0.5), "ink", bevel=0.2)                       # display window
        for j in range(3):
            if (k + j) % 2:
                a.cyl("Root", (x - 0.25 + j * 0.25, 0.95, 0.42), (x - 0.25 + j * 0.25, 0.95, 0.68), 0.06, 0.0,
                      "crystal", "emit", seg=6)                                                          # crystal
            else:
                a.box("Root", (x - 0.25 + j * 0.25, 0.95, 0.5), (0.16, 0.02, 0.22), "team", "team_emit", bevel=0.3)  # chip
    # cash terminal + holo price tag on the counter
    a.box("Root", None, (0.5, 0.35, 0.25), "iron_dark", bevel=0.3, taper=(1.0, 0.6),
          mat=Matrix.Translation((1.6, 0.6, 1.39)) @ Matrix.Rotation(math.radians(-15), 4, "X"))
    a.box("Root", None, (0.36, 0.02, 0.18), "neon", "team_emit", bevel=0.3,
          mat=Matrix.Translation((1.6, 0.72, 1.45)) @ Matrix.Rotation(math.radians(-60), 4, "X"))
    gun(a, (-1.2, 0.6, 1.33), 1.0)
    # back wall with weapon racks and the holo display wall
    a.box("Root", (0, -1.45, 1.8), (W, 0.25, 3.3), "panel", bevel=0.1)
    a.box("Root", (0, -1.3, 0.35), (W, 0.1, 0.5), "iron", bevel=0.2)
    for row, z in enumerate((1.55, 2.35)):
        for side in (-1, 1):
            a.box("Root", (side * 1.6, -1.27, z - 0.12), (1.5, 0.12, 0.05), "brass", "chrome", bevel=0.3)      # rack shelf
            for k in range(2):
                gun(a, (side * 1.6 + (k - 0.5) * 0.7, -1.22, z + 0.05), 0.9, rot_z=rnd.uniform(-6, 6), scale=0.85)
    a.box("Root", (0, -1.3, 1.95), (1.4, 0.06, 1.6), "ink", bevel=0.2)                                        # holo wall
    for i in range(4):
        for j in range(3):
            c = (-0.48 + j * 0.48, -1.26, 1.4 + i * 0.36)
            if (i + j) % 3 == 0:
                a.cyl("Root", (c[0], c[1], c[2] - 0.12), (c[0], c[1], c[2] + 0.12), 0.07, 0.0, "crystal", "emit", seg=6)
            else:
                a.box("Root", c, (0.3, 0.02, 0.22), "team", "team_emit", bevel=0.3)
    # corner posts and the canopy with a team neon fringe
    for s in (-1, 1):
        a.box("Root", (s * (W / 2 - 0.1), 1.0, ROOF_Z / 2), (0.24, 0.24, ROOF_Z), "iron", bevel=0.25)
        a.box("Root", (s * (W / 2 - 0.1), 1.13, ROOF_Z * 0.45), (0.06, 0.02, ROOF_Z * 0.7), "neon", "team_emit", bevel=0.3)
        a.box("Root", (s * (W / 2 - 0.1), -1.45, ROOF_Z / 2), (0.3, 0.3, ROOF_Z), "iron", bevel=0.25)
    a.box("Root", None, (W + 0.5, 3.2, 0.18), "iron_dark", bevel=0.2,
          mat=Matrix.Translation((0, -0.2, ROOF_Z + 0.1)) @ Matrix.Rotation(math.radians(-5), 4, "X"))
    a.box("Root", (0, 1.38, ROOF_Z - 0.02), (W + 0.5, 0.08, 0.1), "neon", "team_emit", bevel=0.3)
    # sign frame (the text is ArmoryMarkerView's Label3D) on struts above the canopy
    for s in (-1, 1):
        a.box("Root", (s * 1.3, 1.1, ROOF_Z + 0.5), (0.12, 0.12, 0.7), "chrome", "chrome", bevel=0.3)
    a.box("Root", (0, 1.15, ROOF_Z + 0.95), (3.4, 0.14, 0.8), "ink", bevel=0.15)
    for (dx, dz, sx, sz) in ((0, 0.4, 3.5, 0.06), (0, -0.4, 3.5, 0.06), (1.72, 0, 0.06, 0.86), (-1.72, 0, 0.06, 0.86)):
        a.box("Root", (dx, 1.23, ROOF_Z + 0.95 + dz), (sx, 0.05, sz), "neon", "team_emit", bevel=0.3)
    # workbench at the side: vice with a gun being socketed, lamp, crates
    a.box("Root", (W / 2 + 0.9, 0.0, 0.5), (1.2, 0.8, 0.08), "wood", bevel=0.3)
    for sx in (-1, 1):
        for sy in (-1, 1):
            a.box("Root", (W / 2 + 0.9 + sx * 0.5, sy * 0.3, 0.24), (0.08, 0.08, 0.48), "iron", bevel=0.3)
    a.box("Root", (W / 2 + 0.75, 0.0, 0.62), (0.2, 0.16, 0.16), "iron_dark", bevel=0.3)
    gun(a, (W / 2 + 0.95, 0.0, 0.66), 0.9, rot_z=0, scale=0.9)
    a.cyl("Root", (W / 2 + 1.35, -0.25, 0.54), (W / 2 + 1.35, -0.25, 1.1), 0.02, 0.02, "chrome", "chrome", seg=6)
    a.cyl("Root", (W / 2 + 1.35, -0.25, 1.1), (W / 2 + 1.15, -0.1, 1.05), 0.07, 0.11, "brass", "chrome", seg=8)
    for (x, y, s) in ((-W / 2 - 0.7, -0.6, 0.6), (-W / 2 - 0.6, 0.15, 0.45), (-W / 2 - 0.75, -0.55, 0.4)):
        z = s / 2 if s != 0.4 else 0.6 + 0.2
        a.box("Root", (x, y, z), (s * 1.3, s, s), "wood" if s != 0.45 else "iron", bevel=0.2,
              rot=(0, 0, rnd.uniform(-10, 10)))
    a.box("Root", (-W / 2 - 0.6, 0.15, 0.46), (0.3, 0.02, 0.12), "neon", "team_emit", bevel=0.3)  # ammo tag
    a.lap("parts")
    a.finish(bevel_m=0.012, drop_floor=True)
    dst = world_kit.out_dir(KEY)
    sizes = a.bake(dst) if "--notex" not in sys.argv else {}
    a.export(dst, sizes)


if __name__ == "__main__":
    build()
