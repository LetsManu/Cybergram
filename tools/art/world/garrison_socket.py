#!/usr/bin/env python3
"""Garrison socket on the hero pipeline (design brief: docs/assets/garrison.md;
design/art-bible.md §6.4: "Garrison Sentinels: placed on raised sockets at the
hardpoint's corners; their sockets stay visible (empty, dim) while a Sentinel
respawns"; wardlings-and-economy.md §11).

A low hex socket (r 0.7 m, 0.14 m: a walkable lip, no collider) a Sentinel
stands on. Pieces:
  main   stone hex base, iron rim, brass studs, a dark lens ring
  ring   the lens ring lit in team colour (bright while its Sentinel stands,
         dim while it respawns, off while nobody holds the hardpoint)

Blender space: Z up, origin = floor centre. Run:
  /tmp/venv/bin/python tools/art/world/garrison_socket.py [--notex]
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import world_kit  # noqa: E402
from mathutils import Vector  # noqa: E402

KEY = "garrison_socket"
SEED = 7331
PALETTE = {
    "stone": "#B9B2A6", "stone_dark": "#8A8292", "iron": "#3B4052", "iron_dark": "#2C3040",
    "brass": "#BFA68A", "lens": "#232634", "neon": "#F4F7FF", "team": "#2E86FF",
}
R = 0.7
H = 0.14


def build(rnd):
    a = world_kit.WorldAsset(KEY, PALETTE, tex=256, texel_m=0.006, paint={"edge": 0.7, "grit": 0.06})
    a.prism((0, 0, H * 0.35), R, H * 0.7, 6, "iron", bevel=0.02, taper=0.94)
    a.prism((0, 0, H * 0.82), R * 0.86, H * 0.36, 6, "stone", bevel=0.012, rot_deg=0, inset=(0.004, 0.05))
    a.prism((0, 0, H + 0.004), R * 0.62, 0.012, 6, "lens", rot_deg=30)
    a.prism((0, 0, H + 0.008), R * 0.42, 0.012, 6, "stone_dark", rot_deg=30)
    for i in range(6):
        ang = i * math.pi / 3
        p = Vector((math.cos(ang) * R * 0.78, math.sin(ang) * R * 0.78, H + 0.01))
        a.cyl("Root", p - Vector((0, 0, 0.01)), p + Vector((0, 0, 0.015)), 0.035, 0.028, "brass", "chrome", seg=6)
    with a.piece("ring"):
        for i in range(6):
            ang = i * math.pi / 3 + math.pi / 6
            c = Vector((math.cos(ang) * R * 0.52, math.sin(ang) * R * 0.52, H + 0.014))
            a.box("Root", c, (0.07, 0.24, 0.008), "neon", "team_emit", bevel=0.3,
                  rot=(0, 0, math.degrees(ang)))
    return a


if __name__ == "__main__":
    a = build(random.Random(SEED))
    a.lap("parts")
    a.finish(bevel_m=0.004, drop_floor=True)
    dst = world_kit.out_dir(KEY)
    sizes = a.bake(dst) if "--notex" not in sys.argv else {}
    a.export(dst, sizes)
