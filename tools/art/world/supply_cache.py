#!/usr/bin/env python3
"""Supply Cache on the hero pipeline (design brief: docs/assets/supply_cache.md;
design/art-bible.md §6.4: "a squat mechanical crate with an ammo-belt icon, brass
trim and a small holo label, always mechanical in style regardless of faction";
match-flow-and-map.md §3.5 C5).

Footprint 1.3 x 1.0 m, 1.0 m high: it stands inside the box collider that
SupplyCacheSystem.add_bodies gives both server and client.

Pieces:
  main    iron-olive ammo crate: ribbed body, brass corner caps and trim, side
          handles, an open top tray with a brass cartridge belt, stencil plate
          with the ammo-belt icon (raised cartridges), feet
  lamps   two team light strips along the lid edge (lit while it serves)
  icon    the cartridge row of the stencil plate, team glow (lit while it serves)

Blender space: Z up, origin = floor centre. Run:
  /tmp/venv/bin/python tools/art/world/supply_cache.py [--notex]
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import world_kit  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

KEY = "supply_cache"
SEED = 6121
PALETTE = {
    "olive": "#5E6650", "olive_dark": "#454B3B", "iron": "#3B4052", "iron_dark": "#2C3040",
    "brass": "#BFA68A", "brass_dark": "#8E7A63", "stencil": "#D9D2BF", "neon": "#F4F7FF",
    "team": "#2E86FF",
}
W, D, H = 1.2, 0.9, 0.78   # body (x, y, z)


def build(rnd):
    a = world_kit.WorldAsset(KEY, PALETTE, tex=512, texel_m=0.004, paint={"edge": 0.75, "grit": 0.09})
    z0 = 0.08
    # feet: two iron skids
    for s in (1, -1):
        a.box("Root", Vector((0, s * (D * 0.5 - 0.1), z0 * 0.5)), (W + 0.04, 0.12, z0), "iron_dark", bevel=0.25)
    # body: olive box with horizontal ribs
    a.box("Root", Vector((0, 0, z0 + H * 0.5)), (W, D, H), "olive", bevel=0.08)
    for zf in (0.25, 0.55):
        for s in (1, -1):
            a.box("Root", Vector((0, s * (D * 0.5 + 0.01), z0 + H * zf)), (W - 0.12, 0.03, 0.05), "olive_dark", bevel=0.3)
    # brass corner caps and lid trim
    for sx in (1, -1):
        for sy in (1, -1):
            for zz in (z0 + 0.05, z0 + H - 0.05):
                a.box("Root", Vector((sx * (W * 0.5 - 0.03), sy * (D * 0.5 - 0.03), zz)), (0.1, 0.1, 0.1),
                      "brass", "chrome", bevel=0.3)
    a.box("Root", Vector((0, 0, z0 + H + 0.02)), (W + 0.04, D + 0.04, 0.05), "brass_dark", "chrome", bevel=0.3)
    # open tray on top with a cartridge belt
    a.box("Root", Vector((0, 0, z0 + H + 0.06)), (W - 0.16, D - 0.2, 0.05), "iron_dark", bevel=0.2)
    for row in range(3):
        y = (row - 1) * 0.18
        for i in range(9):
            x = (i - 4) * 0.105
            a.cyl("Root", (x, y, z0 + H + 0.08), (x, y + 0.0, z0 + H + 0.2), 0.03, 0.022, "brass", "chrome", seg=8)
        a.box("Root", Vector((0, y, z0 + H + 0.09)), (0.98, 0.07, 0.02), "olive_dark", bevel=0.2)
    # side handles
    for s in (1, -1):
        a.box("Root", Vector((s * (W * 0.5 + 0.04), 0, z0 + H * 0.6)), (0.04, 0.34, 0.05), "iron", bevel=0.3)
        for t in (1, -1):
            a.box("Root", Vector((s * (W * 0.5 + 0.02), t * 0.16, z0 + H * 0.6)), (0.05, 0.04, 0.05), "iron", bevel=0.3)
    # stencil plate on the +Y face with the ammo-belt icon frame
    plate_y = D * 0.5 + 0.025
    a.box("Root", Vector((0, plate_y, z0 + H * 0.42)), (0.62, 0.02, 0.3), "stencil", bevel=0.2)
    a.box("Root", Vector((0, plate_y + 0.012, z0 + H * 0.42)), (0.56, 0.01, 0.025), "iron_dark", bevel=0.2)
    # lamps: team light strips along both long lid edges
    with a.piece("lamps"):
        for s in (1, -1):
            a.box("Root", Vector((0, s * (D * 0.5 + 0.025), z0 + H - 0.02)), (W - 0.2, 0.02, 0.04), "neon", "team_emit",
                  bevel=0.3)
    # icon: a cartridge row on the plate (the ammo-belt icon), team glow
    with a.piece("icon"):
        for i in range(5):
            x = (i - 2) * 0.1
            a.box("Root", Vector((x, plate_y + 0.016, z0 + H * 0.42 + 0.06)), (0.045, 0.012, 0.11), "neon", "team_emit",
                  bevel=0.3, taper=(0.6, 1.0))
    # wear: scuffed patches
    for _ in range(5):
        a.box("Root", Vector((rnd.uniform(-0.5, 0.5), -(D * 0.5 + 0.006), z0 + rnd.uniform(0.1, 0.6))),
              (rnd.uniform(0.05, 0.14), 0.004, rnd.uniform(0.03, 0.08)), "olive_dark", bevel=0.3)
    return a


if __name__ == "__main__":
    a = build(random.Random(SEED))
    a.lap("parts")
    a.finish(bevel_m=0.006, drop_floor=True)
    dst = world_kit.out_dir(KEY)
    sizes = a.bake(dst) if "--notex" not in sys.argv else {}
    a.export(dst, sizes)
