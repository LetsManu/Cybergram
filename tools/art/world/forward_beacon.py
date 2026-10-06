#!/usr/bin/env python3
"""Forward Beacon spawn pad on the hero pipeline (design brief:
docs/assets/forward_beacon.md; design/art-bible.md §6.4; match-flow-and-map.md
§3.5). A held Mid hardpoint becomes a spawn point for its owner after a 15 s
attunement; this pad marks where the owner's heroes appear.

The pad is flush with the floor (0.11 m, a walkable lip): no new collision, no
navmesh change. The tall banner-mast and the spawn halo are hard-light
projections built by ForwardBeaconView (holo, state-driven), not geometry.

Pieces (one mesh node each, toggled by ForwardBeaconView from the replicated
beacon state):
  main          stone disc, iron rim, chrome ring, six dark emitter lenses,
                cable runs, the projector housing in the middle
  lamp_1..6     the six emitter lenses lit in team colour (attunement steps)
  core          the projector lens in the middle (lit while attuning / ready)

Blender space: Z up, origin = pad centre on the floor.
Run:  /tmp/venv/bin/python tools/art/world/forward_beacon.py [--notex]
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import world_kit  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

KEY = "forward_beacon"
SEED = 5303
PALETTE = {
    "stone": "#B9B2A6", "stone_dark": "#8A8292", "iron": "#3B4052", "iron_dark": "#2C3040",
    "chrome": "#C9D4E2", "brass": "#BFA68A", "lens": "#232634", "neon": "#F4F7FF",
    "team": "#2E86FF",
}
R = 1.6          # pad radius
H = 0.11         # pad height (walkable lip)
LAMPS = 6
LAMP_R = 1.18    # lens ring radius


def chevron(a, ang, r, z, color, ch, w=0.22, d=0.16, t=0.02):
    """A flat triangle-ish chevron pointing outward at angle `ang` (two slanted bars)."""
    for s in (1, -1):
        m = Matrix.Rotation(ang + s * 0.5, 4, "Z")
        m.translation = Vector((math.cos(ang) * r, math.sin(ang) * r, z))
        a.box("Root", None, (d, 0.05, t), color, ch, bevel=0.3,
              mat=m @ Matrix.Translation(Vector((-d * 0.35, s * w * 0.18, 0))))


def build(rnd):
    a = world_kit.WorldAsset(KEY, PALETTE, tex=512, texel_m=0.006, paint={"edge": 0.7, "grit": 0.06})
    # disc: stone slab with an iron rim and a chrome ring, low enough to walk over
    a.prism((0, 0, 0.035), R, 0.07, 24, "iron", bevel=0.02, taper=0.97)
    a.prism((0, 0, 0.085), R - 0.12, 0.05, 24, "stone", bevel=0.01, inset=(0.004, 0.04))
    a.torus("Root", (0, 0, 0.075), (0, 0, 1), R - 0.06, 0.03, "chrome", "chrome", seg=(36, 5))
    # brass bolts on the rim
    a.ring_of(12, R - 0.04, 0.07, lambda i, ang, x, y: a.cyl(
        "Root", (x, y, 0.06), (x, y, 0.08), 0.03, 0.025, "brass", "chrome", seg=6), phase=math.pi / 12)
    # six emitter lenses (dark when unlit) in iron collars, with cable grooves to the centre
    for i in range(LAMPS):
        ang = i * 2 * math.pi / LAMPS
        x, y = math.cos(ang) * LAMP_R, math.sin(ang) * LAMP_R
        a.prism((x, y, 0.1), 0.17, 0.03, 6, "iron_dark", bevel=0.005, rot_deg=math.degrees(ang))
        a.prism((x, y, 0.113), 0.12, 0.012, 6, "lens", rot_deg=math.degrees(ang))
        m = Matrix.Rotation(ang, 4, "Z")
        m.translation = Vector((math.cos(ang) * 0.68, math.sin(ang) * 0.68, 0.112))
        a.box("Root", None, (0.62, 0.05, 0.012), "iron_dark", bevel=0.2, mat=m)
        chevron(a, ang, R - 0.27, 0.112, "stone_dark", "flat")
    # projector housing: hex collar with a dark lens
    a.prism((0, 0, 0.1), 0.36, 0.03, 6, "iron", bevel=0.006)
    a.prism((0, 0, 0.115), 0.26, 0.012, 6, "lens")
    for i in range(3):
        ang = i * 2 * math.pi / 3 + math.pi / 6
        a.box("Root", Vector((math.cos(ang) * 0.3, math.sin(ang) * 0.3, 0.118)), (0.08, 0.08, 0.016),
              "brass", "chrome", bevel=0.3)
    # scuffs: a few darker stone flecks
    for _ in range(6):
        ang, rr = rnd.uniform(0, 2 * math.pi), rnd.uniform(0.45, 1.3)
        a.box("Root", Vector((math.cos(ang) * rr, math.sin(ang) * rr, 0.111)),
              (rnd.uniform(0.08, 0.16), rnd.uniform(0.05, 0.1), 0.004), "stone_dark", bevel=0.3)
    # lit lenses (team glow), one piece each so attunement lights them one by one
    for i in range(LAMPS):
        ang = i * 2 * math.pi / LAMPS
        x, y = math.cos(ang) * LAMP_R, math.sin(ang) * LAMP_R
        with a.piece("lamp_%d" % (i + 1)):
            a.prism((x, y, 0.119), 0.115, 0.008, 6, "neon", "team_emit", rot_deg=math.degrees(ang))
            chevron(a, ang, R - 0.27, 0.12, "neon", "team_emit")
    with a.piece("core"):
        a.prism((0, 0, 0.121), 0.25, 0.01, 6, "neon", "team_emit")
    return a


if __name__ == "__main__":
    a = build(random.Random(SEED))
    a.lap("parts")
    a.finish(bevel_m=0.004, drop_floor=True)
    dst = world_kit.out_dir(KEY)
    sizes = a.bake(dst) if "--notex" not in sys.argv else {}
    a.export(dst, sizes)
