#!/usr/bin/env python3
"""Holdstone, the Hold hardpoint's machine, on the hero pipeline
(design brief: docs/assets/holdstone.md; design/art-bible.md §6.3).

A chrome-ring plinth around a dormant mana crystal on a stone dais. The
footprint matches the map's collision exactly (tools/maps/build_shardline_front.gd
HOLD: Dais r 8.0 -> 7.0, 0.3 m; Plinth r 2.8 -> 2.4, 1.8 m on top of it), so the
greybox meshes can be hidden while their collision stays. The 12 m light pillar
and the 12 progress segments are HardpointView's (holo, state-driven).

Pieces: main (dais, plinth, collar, claws, rubble), crystal (team-glow cluster).
Blender space: Z up, origin = hardpoint centre on the pad floor.
Run:  /tmp/venv/bin/python tools/art/world/holdstone.py [--notex] [--out <dir>]
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import world_kit  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

KEY = "holdstone"
SEED = 2207
DAIS = (8.0, 7.0, 0.3)     # bottom r, top r, height (map collision)
PLINTH = (2.8, 2.4, 1.8)   # bottom r, top r, height, standing on the dais
PZ = DAIS[2]               # plinth base

PALETTE = {
    "stone": "#B9B2A6", "stone_dark": "#8A8292", "stone_deep": "#6E6779",
    "iron": "#3B4052", "chrome": "#C9D4E2", "brass": "#BFA68A", "panel": "#5A5370",
    "neon": "#F4F7FF", "team": "#2E86FF",
}


def dais(a, rnd):
    r0, r1, h = DAIS
    a.prism((0, 0, h * 0.5), r0, h, 24, "stone", bevel=0.04, taper=r1 / r0)
    a.prism((0, 0, h + 0.02), r1 - 0.3, 0.04, 24, "stone_dark", bevel=0.01)   # inner floor slab
    # brass inlay ring + 12 radial seams (one per progress segment of HardpointView)
    def inlay(i, ang, x, y):
        a.box("Root", (x, y, h + 0.045), (1.35, 0.16, 0.03), "brass", "chrome", bevel=0.3,
              rot=(0, 0, math.degrees(ang) + 90))
    a.ring_of(24, 5.6, 0, inlay)
    def seam(i, ang, x, y):
        o = Vector((math.cos(ang), math.sin(ang), 0))
        c = o * 4.6
        a.box("Root", (c.x, c.y, h + 0.04), (2.0, 0.07, 0.025), "stone_deep", bevel=0.2,
              rot=(0, 0, math.degrees(ang)))
        # team-neon floor emitter at the seam's outer end
        e = o * 6.55
        a.box("Root", (e.x, e.y, h + 0.05), (0.42, 0.22, 0.05), "neon", "team_emit", bevel=0.35,
              rot=(0, 0, math.degrees(ang)))
    a.ring_of(12, 0, 0, seam, phase=math.pi / 12)
    # step blocks on the dais rim (worn stone, seeded sizes)
    def step(i, ang, x, y):
        w = 1.5 + rnd.uniform(-0.15, 0.15)
        a.box("Root", (x, y, h * 0.5), (w, 0.55, h * 1.02), "stone_dark" if i % 3 else "stone", bevel=0.3,
              rot=(0, 0, math.degrees(ang) + 90 + rnd.uniform(-2, 2)))
    a.ring_of(30, r0 - 0.15, 0, step)
    # rubble at the dais edge: grounds it in the plaza floor
    for _ in range(14):
        ang = rnd.uniform(0, 2 * math.pi)
        rr = r0 + rnd.uniform(0.2, 0.9)
        s = rnd.uniform(0.18, 0.45)
        a.box("Root", (math.cos(ang) * rr, math.sin(ang) * rr, s * 0.35), (s * 1.3, s, s * 0.8),
              rnd.choice(["stone", "stone_dark", "stone_deep"]), bevel=0.35,
              rot=(rnd.uniform(-12, 12), rnd.uniform(-12, 12), rnd.uniform(0, 180)))


def plinth(a, rnd):
    r0, r1, h = PLINTH
    z0 = PZ
    # lower band, body with inset panels, upper band
    a.prism((0, 0, z0 + 0.25), r0, 0.5, 12, "stone", bevel=0.05, rot_deg=15)
    a.prism((0, 0, z0 + 0.5 + 0.55), r0 - 0.12, 1.1, 12, "stone_dark", bevel=0.04, rot_deg=15,
            taper=(r1 + 0.05) / (r0 - 0.12), inset=(0.04, 0.14))
    a.prism((0, 0, z0 + h - 0.1), r1 + 0.08, 0.2, 12, "brass", "chrome", bevel=0.03, rot_deg=15)
    a.prism((0, 0, z0 + h + 0.06), r1 - 0.2, 0.12, 12, "stone", bevel=0.03, rot_deg=15)
    # four chrome ribs with neon slits and bolts
    for k in range(4):
        ang = math.pi / 4 + k * math.pi / 2
        o = Vector((math.cos(ang), math.sin(ang), 0))
        rot = (0, 0, math.degrees(ang))
        a.box("Root", Vector((0, 0, z0 + 0.95)) + o * (r0 - 0.05), (0.32, 0.5, 1.45), "chrome", "chrome",
              bevel=0.35, taper=(0.85, 0.85), rot=rot)
        a.box("Root", Vector((0, 0, z0 + 0.95)) + o * (r0 + 0.2), (0.07, 0.08, 1.0), "neon", "team_emit",
              bevel=0.3, rot=rot)
        for j in range(3):
            a.box("Root", Vector((0, 0, z0 + 0.45 + j * 0.5)) + o * (r0 + 0.05) + o.cross(Vector((0, 0, 1))) * 0.2,
                  (0.06, 0.06, 0.06), "brass", "chrome", bevel=0.4, rot=rot)
    # vents between the ribs
    for k in range(4):
        ang = k * math.pi / 2
        o = Vector((math.cos(ang), math.sin(ang), 0))
        rot = (0, 0, math.degrees(ang))
        a.box("Root", Vector((0, 0, z0 + 1.05)) + o * (r0 - 0.22), (0.12, 0.9, 0.42), "panel", bevel=0.3, rot=rot)
        for j in range(4):
            a.box("Root", Vector((0, 0, z0 + 0.9 + j * 0.1)) + o * (r0 - 0.17), (0.06, 0.8, 0.03), "iron",
                  bevel=0.3, rot=rot)


def collar_and_claws(a, rnd):
    top = PZ + PLINTH[2] + 0.12
    a.torus("Root", (0, 0, top + 0.12), (0, 0, 1), 1.75, 0.16, "chrome", "chrome", seg=(40, 8))
    a.torus("Root", (0, 0, top + 0.26), (0, 0, 1), 1.55, 0.04, "neon", "team_emit", seg=(40, 4))
    for k in range(5):  # claws curling up around the crystal
        ang = 2 * math.pi * k / 5 + 0.3
        o = Vector((math.cos(ang), math.sin(ang), 0))
        b = o * 1.7 + Vector((0, 0, top + 0.15))
        m = o * 1.45 + Vector((0, 0, top + 1.1))
        t = o * 0.95 + Vector((0, 0, top + 1.75))
        for p0, p1, w in ((b, m, 0.26), (m, t, 0.2)):
            d = (p1 - p0)
            z = d.normalized()
            x = (o - z * o.dot(z)).normalized()
            mat = Matrix((x, z.cross(x), z)).transposed().to_4x4()
            mat.translation = (p0 + p1) / 2
            a.box("Root", None, (w, w * 1.1, d.length), "chrome", "chrome", bevel=0.35, taper=(0.8, 0.8), mat=mat)
        a.sphere("Root", m, (0.17, 0.17, 0.17), "brass", "chrome", seg=(10, 6))
        a.box("Root", t + Vector((0, 0, 0.12)), (0.12, 0.12, 0.18), "neon", "team_emit", bevel=0.3)


def crystal(a, rnd):
    top = PZ + PLINTH[2] + 0.2
    with a.piece("crystal"):
        for (dx, dy, tilt, r, shaft, tip) in ((0, 0, 0, 0.62, 1.5, 0.8), (0.55, 0.2, 22, 0.32, 0.8, 0.45),
                                            (-0.45, -0.35, -26, 0.3, 0.7, 0.4), (0.1, -0.55, 14, 0.24, 0.55, 0.3)):
            c = Vector((dx, dy, top + shaft * 0.5 + 0.1))
            rot = Matrix.Rotation(math.radians(tilt), 4, "X") @ Matrix.Rotation(rnd.uniform(0, 1.0), 4, "Z")
            for (z0, z1, ra, rb) in ((-shaft / 2, shaft / 2, r, r * 0.9), (shaft / 2, shaft / 2 + tip, r * 0.9, 0.0),
                                     (-shaft / 2 - tip * 0.6, -shaft / 2, 0.0, r)):
                p0 = c + (rot @ Vector((0, 0, z0)))
                p1 = c + (rot @ Vector((0, 0, z1)))
                a.cyl("Root", p0, p1, ra, rb, "neon", "team_emit", seg=6)


def build():
    rnd = random.Random(SEED)
    tex = int(os.environ.get("WORLD_TEX", "1024"))
    a = world_kit.WorldAsset(KEY, PALETTE, tex=tex, texel_m=0.02 * 1024 / tex,
                             paint={"edge": 0.65, "grit": 0.08})
    dais(a, rnd)
    plinth(a, rnd)
    collar_and_claws(a, rnd)
    crystal(a, rnd)
    a.lap("parts")
    a.finish(bevel_m=0.015)
    dst = world_kit.out_dir(KEY)
    sizes = a.bake(dst) if "--notex" not in sys.argv else {}
    a.export(dst, sizes)


if __name__ == "__main__":
    build()
