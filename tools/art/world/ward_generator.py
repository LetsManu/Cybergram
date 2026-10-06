#!/usr/bin/env python3
"""Ward Generator on the hero pipeline (design brief: docs/assets/ward_generator.md;
design/art-bible.md §3.1 triangles = breach, §6.3; match-flow-and-map.md §3.4
Breach). The Breach hardpoint's machine: attackers shoot it once its shield
drops; at 0 HP the hardpoint is breached.

Fits the map's collision (GeneratorCore: hexagonal column, radius 1.2 m,
2.4 m high, floor at 0): every solid part stays inside that column except the
low plinth (0.3 m, walkable lip) and the spike crown above 2.4 m.

Pieces (one mesh node each, toggled by HardpointView from the replicated HP):
  main      plinth, iron housing, stone plates, spike crown, emitter rings
  core      the glowing team crystal seen through the housing windows
  crack_1   first cracks on the plates (HP < 75 %)
  crack_2   more cracks + a split plate (HP < 50 %)
  crack_3   the housing torn open, exposed glowing seams (HP < 25 %)
  wreck     fallen plates and broken spikes on the plinth (breached)

Blender space: Z up, origin = the floor centre.
Run:  /tmp/venv/bin/python tools/art/world/ward_generator.py [--notex]
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import world_kit  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

PALETTE = {
    "stone": "#B9B2A6", "stone_dark": "#8A8292", "iron": "#3B4052", "iron_dark": "#2C3040",
    "chrome": "#C9D4E2", "brass": "#BFA68A", "scorch": "#3A3030", "neon": "#F4F7FF",
    "team": "#2E86FF",
}
R = 1.2          # collision column radius (hex circumradius)
H = 2.4          # collision column height
HOUSING_R = 1.08 # housing stays inside the column
APART = 6.0      # optional pieces are baked this far apart (world_kit.piece)


def hexpt(i, r, z, phase=0.0):
    a = phase + i * math.pi / 3
    return Vector((math.cos(a) * r, math.sin(a) * r, z))


def face_frame(i, r, z):
    """Matrix at the middle of hex face i (between corners i and i+1), X = outward."""
    a = (i + 0.5) * math.pi / 3
    n = Vector((math.cos(a), math.sin(a), 0))
    m = Matrix.Rotation(a, 4, "Z")
    m.translation = n * r * math.cos(math.pi / 6) + Vector((0, 0, z))
    return m


def plate(a, i, z, h, color="stone", w=None, inset=0.0, tilt=0.0):
    """Stone cladding plate on hex face i, centred at height z."""
    w = w if w is not None else HOUSING_R * 0.82
    m = face_frame(i, HOUSING_R + 0.02 - inset, z) @ Matrix.Rotation(tilt, 4, "Y")
    a.box("Root", None, (0.08, w, h), color, bevel=0.25, mat=m)


def crack(a, i, z, length, ang, width=0.035, glow=True, out=0.075):
    """A jagged crack on face i: dark scorched groove with a team glow inside."""
    m = face_frame(i, HOUSING_R + out, z) @ Matrix.Rotation(ang, 4, "X")
    segs = 3
    for k in range(segs):
        off = (k - (segs - 1) / 2) * length / segs
        j = Matrix.Rotation(math.radians((-1) ** k * 18), 4, "X")
        mk = m @ Matrix.Translation(Vector((0, 0, off))) @ j
        a.box("Root", None, (0.03, width * 2.2, length / segs * 1.08), "scorch", bevel=0.2, mat=mk)
        if glow:
            a.box("Root", None, (0.036, width * 0.8, length / segs * 0.9), "neon", "team_emit", bevel=0.3, mat=mk)


def build(rnd):
    a = world_kit.WorldAsset("ward_generator", PALETTE, tex=1024, texel_m=0.006, paint={"edge": 0.7, "grit": 0.07})
    # plinth: two hex steps (low lip, walkable), team neon inlay ring
    a.prism((0, 0, 0.08), R + 0.75, 0.16, 6, "stone_dark", bevel=0.04, rot_deg=30)
    a.prism((0, 0, 0.22), R + 0.4, 0.12, 6, "stone", bevel=0.03, rot_deg=30)
    for i in range(6):
        p0, p1 = hexpt(i, R + 0.58, 0.165, math.pi / 6), hexpt(i + 1, R + 0.58, 0.165, math.pi / 6)
        c = (p0 + p1) / 2
        d = (p1 - p0)
        m = Matrix.Rotation(math.atan2(d.y, d.x), 4, "Z")
        m.translation = c
        a.box("Root", None, (d.length * 0.8, 0.08, 0.03), "neon", "team_emit", bevel=0.3, mat=m)
    # housing: iron hex column inside the collision, chrome corner ribs
    a.prism((0, 0, 0.28 + 1.0), HOUSING_R, 2.0, 6, "iron", bevel=0.03, taper=0.92)
    for i in range(6):
        c = hexpt(i, HOUSING_R + 0.01, 0)
        a.cyl("Root", c + Vector((0, 0, 0.28)), c * 0.93 + Vector((0, 0, 2.3)), 0.07, 0.06, "chrome", "chrome", seg=8)
    # stone plates: lower band all round, upper band with a window gap (core shows)
    for i in range(6):
        plate(a, i, 0.75, 0.75)
        plate(a, i, 1.95, 0.5, w=HOUSING_R * 0.6)
        # window frame (brass) around the gap where the core glows through
        m = face_frame(i, HOUSING_R + 0.03, 1.38)
        for s in (1, -1):
            a.box("Root", None, (0.05, 0.06, 0.42), "brass", "chrome", bevel=0.3,
                  mat=m @ Matrix.Translation(Vector((0, s * HOUSING_R * 0.3, 0))))
        a.box("Root", None, (0.04, HOUSING_R * 0.62, 0.05), "brass", "chrome", bevel=0.3,
              mat=m @ Matrix.Translation(Vector((0, 0, -0.22))))
    # spike crown: six triangular blades leaning out (art bible: triangles = breach)
    a.prism((0, 0, 2.33), HOUSING_R * 0.98, 0.14, 6, "brass", "chrome", bevel=0.02)
    for i in range(6):
        base = hexpt(i, HOUSING_R * 0.82, 2.38)
        tip = hexpt(i, HOUSING_R * 1.15, 3.35)
        out = Vector((base.x, base.y, 0)).normalized()
        m = Matrix((out, Vector((0, 0, 1)).cross(out), (tip - base).normalized())).transposed().to_4x4()
        m.translation = (base + tip) / 2
        a.box("Root", None, (0.08, 0.34, (tip - base).length), "chrome", "chrome", bevel=0.2, taper=(0.15, 0.6), mat=m)
        a.box("Root", None, (0.09, 0.06, (tip - base).length * 0.7), "neon", "team_emit", bevel=0.3, taper=(0.2, 0.6),
              mat=m @ Matrix.Translation(Vector((0.01, 0, -0.08))))
    # emitter: rings above the crown that project the shield
    a.torus("Root", (0, 0, 2.5), (0, 0, 1), 0.7, 0.06, "chrome", "chrome", seg=(30, 6))
    a.torus("Root", (0, 0, 2.62), (0, 0, 1), 0.52, 0.035, "neon", "team_emit", seg=(30, 4))
    a.cyl("Root", (0, 0, 2.4), (0, 0, 2.85), 0.16, 0.08, "iron_dark", seg=10)
    a.sphere("Root", (0, 0, 2.92), (0.12, 0.12, 0.12), "neon", "team_emit", seg=(10, 6))
    # cables from the plinth into the housing
    for i in (0, 2, 4):
        p = hexpt(i, R + 0.45, 0.32, math.pi / 6)
        a.cyl("Root", p, p * 0.72 + Vector((0, 0, 0.55)), 0.06, 0.05, "iron_dark", seg=8)
    # core: a tall team crystal inside the housing (visible through the windows)
    with a.piece("core"):
        a.prism((0, 0, 1.35), 0.42, 1.5, 6, "neon", "team_emit", bevel=0.02, rot_deg=30, taper=0.75)
        a.prism((0, 0, 2.25), 0.31, 0.3, 6, "neon", "team_emit", rot_deg=30, taper=0.05)
        a.prism((0, 0, 0.5), 0.3, 0.2, 6, "neon", "team_emit", rot_deg=30, taper=1.4)
    # crack stages (overlays on the plates)
    with a.piece("crack_1", apart=(APART, 0, 0)):
        for i, z, ang in ((0, 0.8, 0.5), (3, 0.6, -0.4), (4, 1.95, 0.9)):
            crack(a, i, z, 0.55, ang)
    with a.piece("crack_2", apart=(-APART, 0, 0)):
        for i, z, ang in ((1, 0.7, -0.6), (2, 0.9, 0.3), (5, 0.75, 0.2), (0, 1.95, -0.7)):
            crack(a, i, z, 0.7, ang)
        # a plate split in two, the lower half slipped
        plate(a, 2, 0.48, 0.3, color="stone_dark", inset=-0.04, tilt=0.12)
    with a.piece("crack_3", apart=(0, APART, 0)):
        for i in range(6):
            crack(a, i, 1.1 + (i % 2) * 0.5, 0.95, 0.15 * (-1) ** i, width=0.05)
            # exposed glowing seam where the plates parted
            m = face_frame(i, HOUSING_R + 0.065, 1.38)
            a.box("Root", None, (0.03, 0.05, 1.6), "neon", "team_emit", bevel=0.3,
                  mat=m @ Matrix.Translation(Vector((0, HOUSING_R * 0.38, 0))))
    # wreck: fallen plates and two snapped spikes on the plinth (breached)
    with a.piece("wreck", apart=(0, -APART, 0)):
        for k, i in enumerate((0, 2, 3, 5)):
            p = hexpt(i, R + 0.55, 0.32, 0.3)
            m = Matrix.Rotation(rnd.uniform(0, math.pi), 4, "Z") @ Matrix.Rotation(1.35 + 0.1 * k, 4, "Y")
            m.translation = p
            a.box("Root", None, (0.08, 0.7, 0.55), "stone_dark", bevel=0.25, mat=m)
        for i in (1, 4):
            p = hexpt(i, R + 0.6, 0.36, 0.5)
            m = Matrix.Rotation(i * 1.1, 4, "Z") @ Matrix.Rotation(math.pi / 2, 4, "Y")
            m.translation = p
            a.box("Root", None, (0.08, 0.3, 0.7), "chrome", "chrome", bevel=0.2, taper=(0.2, 0.6), mat=m)
        for i in range(5):
            p = hexpt(i, R + 0.2 + 0.25 * (i % 2), 0.3, 1.0)
            a.box("Root", p, (0.18, 0.14, 0.1), "scorch", bevel=0.3)
    return a


if __name__ == "__main__":
    a = build(random.Random(4101))
    a.lap("parts")
    a.finish(bevel_m=0.012, drop_floor=True)
    dst = world_kit.out_dir("ward_generator")
    sizes = a.bake(dst) if "--notex" not in sys.argv else {}
    a.export(dst, sizes)
