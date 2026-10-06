#!/usr/bin/env python3
"""Mana Uplink frame on the hero pipeline (design brief: docs/assets/uplink.md;
design/art-bible.md §6.5).

Builds the SOLID structure of the 45 m spire: stepped plinth, collar and six
pylons, three legs with cross braces and neon channels, the crystal claws, the
mast and the emitter head, plus five rings as separate pieces (ring_0..ring_4)
so UplinkModel keeps spinning / juddering them. The crystal, the rune bands,
the beam and the crack lines stay in UplinkModel (holo / crystal shaders).

Blender space: Z up, origin = Uplink floor centre (the game's hq.uplink).
Run:  /tmp/venv/bin/python tools/art/world/uplink.py [--notex] [--out <dir>]
Out:  assets/models/world/uplink/uplink.glb + uplink_albedo/_normal/_mask.png
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import world_kit  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

KEY = "uplink"
SEED = 1701
CORE_Z = 7.3           # UplinkModel.core_y (gameplay core)
HEIGHT = 45.0          # UplinkModel.HEIGHT_M
RING_Z = [3.2, 12.5, 19.0, 26.0, 33.0]   # UplinkModel.RING_Y
RING_R = [4.4, 3.1, 2.6, 2.0, 1.6]
PLINTH = (4.6, 3.6, 1.5)  # bottom radius, top radius, height (map collision: 4.5 / 3.5 / 1.5)

PALETTE = {
    "stone": "#B9B2A6",      # halcyra_stone: plinth, plates
    "stone_dark": "#8A8292",
    "iron": "#3B4052",       # structural beams (mid-dark, saturated: art bible value rule)
    "chrome": "#C9D4E2",     # chrome_cool (matcap channel)
    "brass": "#BFA68A",      # chrome_warm trim
    "panel": "#5A5370",      # recessed panels / vents
    "neon": "#F4F7FF",       # white neon (emit)
    "team": "#2E86FF",       # team zone (replaced at runtime by team_color)
}


def beam(a, p0, p1, w, d, color, ch="flat", out=None, bevel=0.2, taper=(1.0, 1.0)):
    """Box from p0 to p1 (centre line), cross-section w x d, X facing `out`."""
    p0, p1 = Vector(p0), Vector(p1)
    z = (p1 - p0).normalized()
    o = Vector(out) if out is not None else Vector((1, 0, 0))
    x = (o - z * o.dot(z))
    x = x.normalized() if x.length > 1e-6 else Vector((1, 0, 0))
    y = z.cross(x)
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = (p0 + p1) / 2
    a.box("Root", None, ((w, d, (p1 - p0).length)), color, ch, bevel=bevel, taper=taper, mat=m)


def plinth(a, rnd):
    r0, r1, h = PLINTH
    # footing ring that grounds the plinth in the plaza floor
    a.prism((0, 0, 0.09), r0 + 0.55, 0.18, 8, "stone_dark", bevel=0.05, rot_deg=22.5)
    # main stepped body: lower drum with inset panels, upper cap
    a.prism((0, 0, h * 0.42), r0, h * 0.84, 8, "stone", bevel=0.06, rot_deg=22.5, taper=0.86, inset=(0.05, 0.16))
    a.prism((0, 0, h * 0.92), r1 + 0.15, h * 0.16, 8, "brass", "chrome", bevel=0.03, rot_deg=22.5)
    a.prism((0, 0, h + 0.06), r1 - 0.05, 0.12, 8, "stone_dark", bevel=0.03, rot_deg=22.5)
    # conduit housings on the 8 faces, with a team-neon strip each
    def housing(i, ang, x, y):
        out = Vector((math.cos(ang), math.sin(ang), 0))
        c = out * (r0 * 0.93)
        a.box("Root", None, (0.9, 0.5, 0.8), "iron", bevel=0.25,
              mat=Matrix.Translation(c + Vector((0, 0, 0.55))) @ Matrix.Rotation(ang + math.pi / 2, 4, "Z"))
        a.box("Root", None, (0.62, 0.08, 0.12), "neon", "team_emit", bevel=0.2,
              mat=Matrix.Translation(c + out * 0.26 + Vector((0, 0, 0.62))) @ Matrix.Rotation(ang + math.pi / 2, 4, "Z"))
        # pipe from the housing into the collar
        a.cyl("Root", c + out * 0.05 + Vector((0, 0, 0.95)), out * (r1 * 0.9) + Vector((0, 0, h + 0.15)),
              0.11, 0.11, "chrome", "chrome", seg=8)
    a.ring_of(8, 0, 0, housing, phase=math.radians(22.5))
    # rivet rows along the brass band, slightly irregular
    def rivet(i, ang, x, y):
        j = rnd.uniform(-0.02, 0.02)
        a.box("Root", (x, y, PLINTH[2] * 0.92 + j), (0.09, 0.09, 0.05), "chrome", "chrome", bevel=0.4,
              rot=(0, 0, math.degrees(ang)))
    a.ring_of(32, r1 + 0.23, 0, rivet)


def collar(a, rnd):
    a.torus("Root", (0, 0, 1.75), (0, 0, 1), 3.6, 0.3, "chrome", "chrome", seg=(48, 8))
    a.torus("Root", (0, 0, 1.92), (0, 0, 1), 3.35, 0.06, "neon", "team_emit", seg=(48, 4))
    def pylon(i, ang, x, y):
        rot = (0, 0, math.degrees(ang))
        a.box("Root", (x, y, 3.0), (0.8, 0.8, 2.6), "stone", bevel=0.18, taper=(0.82, 0.82), rot=rot)
        a.box("Root", (x, y, 4.4), (0.95, 0.95, 0.26), "brass", "chrome", bevel=0.3, rot=rot)
        a.box("Root", (x, y, 4.62), (0.55, 0.55, 0.2), "iron", bevel=0.3, taper=(0.6, 0.6), rot=rot)
        o = Vector((math.cos(ang), math.sin(ang), 0))
        # recessed vent + neon slit facing out
        a.box("Root", Vector((x, y, 3.0)) + o * 0.39, (0.42, 0.06, 1.5), "panel", bevel=0.3, rot=rot)
        a.box("Root", Vector((x, y, 3.0)) + o * 0.43, (0.1, 0.04, 1.2), "neon", "team_emit", bevel=0.3, rot=rot)
        for k in range(3):
            a.box("Root", Vector((x, y, 2.1 + k * 0.9)) + o * 0.42 + Vector((0, 0, 0)) + o.cross(Vector((0, 0, 1))) * 0.3,
                  (0.07, 0.07, 0.07), "chrome", "chrome", bevel=0.4, rot=rot)
    a.ring_of(6, 3.6, 0, pylon)


def legs(a, rnd):
    tops = []
    for k in range(3):
        ang = 2 * math.pi * k / 3 + 0.5
        o = Vector((math.cos(ang), math.sin(ang), 0))
        p0 = o * 3.0 + Vector((0, 0, 1.5))
        p1 = o * 0.9 + Vector((0, 0, 36.0))
        tops.append((p0, p1, o))
        beam(a, p0, p1, 1.0, 1.3, "iron", out=o, bevel=0.16)
        # outer armour plates in stone, staggered, with chrome edges
        L = (p1 - p0).length
        d = (p1 - p0).normalized()
        n = 7
        for j in range(n):
            t0 = 0.06 + j * (0.88 / n)
            t1 = t0 + 0.88 / n * 0.86
            q0, q1 = p0 + d * (L * t0), p0 + d * (L * t1)
            off = o * 0.42
            beam(a, q0 + off, q1 + off, 0.72, 0.5, "stone" if j % 2 == 0 else "stone_dark", out=o, bevel=0.22,
                 taper=(0.92, 1.0))
        # team-neon channel running up the inner face
        beam(a, p0 - o * 0.5 + d * 1.2, p1 - o * 0.5 - d * 0.6, 0.2, 0.16, "neon", "team_emit", out=o, bevel=0.3)
        # foot: housing + two hydraulic pistons
        a.box("Root", p0 + Vector((0, 0, 0.8)), (1.5, 1.8, 2.2), "stone", bevel=0.2, taper=(0.85, 0.85),
              rot=(0, 0, math.degrees(ang)))
        a.box("Root", p0 + Vector((0, 0, 2.0)), (1.6, 1.9, 0.25), "brass", "chrome", bevel=0.35,
              rot=(0, 0, math.degrees(ang)))
        side = o.cross(Vector((0, 0, 1)))
        for s in (-1, 1):
            b0 = p0 + side * (0.75 * s) + Vector((0, 0, 0.4))
            b1 = p0 + d * 4.5 + side * (0.6 * s)
            a.cyl("Root", b0, b0.lerp(b1, 0.55), 0.13, 0.13, "chrome", "chrome", seg=10)
            a.cyl("Root", b0.lerp(b1, 0.5), b1, 0.08, 0.08, "iron", seg=8)
    # cross braces between the legs (3 levels), with gusset plates
    for z in (10.0, 17.5, 24.5, 30.5):
        pts = []
        for p0, p1, o in tops:
            t = (z - p0.z) / (p1.z - p0.z)
            pts.append(p0.lerp(p1, t))
        for k in range(3):
            q0, q1 = pts[k], pts[(k + 1) % 3]
            mid = (q0 + q1) / 2
            out = mid.copy()
            out.z = 0
            beam(a, q0, q1, 0.36, 0.42, "iron", out=out, bevel=0.25)
            beam(a, q0.lerp(q1, 0.42), q0.lerp(q1, 0.58), 0.5, 0.55, "brass", "chrome", out=out, bevel=0.3)


def claws(a, rnd):
    for k in range(3):
        ang = 2 * math.pi * k / 3
        o = Vector((math.cos(ang), math.sin(ang), 0))
        for s in (-1, 1):  # lower claw grips from below, upper from above
            base = o * 1.75 + Vector((0, 0, CORE_Z + s * 3.7))
            mid = o * 2.05 + Vector((0, 0, CORE_Z + s * 2.2))
            tip = o * 1.55 + Vector((0, 0, CORE_Z + s * 0.9))
            beam(a, base, mid, 0.42, 0.42, "chrome", "chrome", out=o, bevel=0.3)
            beam(a, mid, tip, 0.34, 0.36, "chrome", "chrome", out=o, bevel=0.3, taper=(0.7, 0.8))
            a.sphere("Root", mid, (0.3, 0.3, 0.3), "brass", "chrome", seg=(12, 8))  # knuckle
            a.box("Root", tip - o * 0.12, (0.18, 0.18, 0.22), "neon", "team_emit", bevel=0.3,
                  rot=(0, 0, math.degrees(ang)))
            # claw anchor to the nearest leg line
            a.cyl("Root", base, o * 2.85 + Vector((0, 0, CORE_Z + s * 3.9)), 0.16, 0.16, "iron", seg=8)


def mast(a, rnd):
    a.cyl("Root", (0, 0, 31.0), (0, 0, 44.0), 0.75, 0.38, "iron", seg=12)
    for k in range(6):  # chrome bands up the mast
        z = 32.0 + k * 2.0
        r = 0.75 - (z - 31.0) / 13.0 * 0.37
        a.torus("Root", (0, 0, z), (0, 0, 1), r + 0.04, 0.07, "chrome", "chrome", seg=(20, 5))
    a.cyl("Root", (0, 0, 31.0), (0, 0, 44.0), 0.12, 0.12, "neon", "team_emit", seg=6)  # inner light line
    # emitter head: flared dish, six fins, the signal sphere
    a.cyl("Root", (0, 0, 43.6), (0, 0, 44.9), 0.45, 1.5, "stone", seg=16)
    a.torus("Root", (0, 0, 44.9), (0, 0, 1), 1.45, 0.1, "brass", "chrome", seg=(24, 5))
    def fin(i, ang, x, y):
        o = Vector((math.cos(ang), math.sin(ang), 0))
        beam(a, o * 0.5 + Vector((0, 0, 42.6)), o * 1.35 + Vector((0, 0, 45.3)), 0.12, 0.5, "iron", out=o, bevel=0.3)
    a.ring_of(6, 0, 0, fin)
    a.sphere("Root", (0, 0, 45.2), (0.75, 0.75, 0.75), "neon", "team_emit", seg=(16, 10))


def rings(a, rnd):
    for i, (z, r) in enumerate(zip(RING_Z, RING_R)):
        with a.piece("ring_%d" % i):
            t = 0.16 + 0.04 * r
            a.torus("Root", (0, 0, z), (0, 0, 1), r - t, t, "iron", seg=(max(28, int(r * 12)), 8))
            a.torus("Root", (0, 0, z + t * 0.6), (0, 0, 1), r - t * 1.7, 0.045, "neon", "team_emit",
                    seg=(max(28, int(r * 12)), 4))
            n = 12 if r > 2.5 else 8
            def plate(k, ang, x, y):
                a.box("Root", (x, y, z), (0.55 * r / 3.0 + 0.25, t * 2.3, t * 2.6), "stone", bevel=0.3,
                      rot=(0, 0, math.degrees(ang) + 90))
            a.ring_of(n, r - t, z, plate)
            def tooth(k, ang, x, y):
                a.box("Root", (x, y, z), (0.24, 0.18, 0.36), "neon", "team_emit", bevel=0.3,
                      rot=(0, 0, math.degrees(ang)))
            a.ring_of(6, r + 0.02, z, tooth, phase=math.pi / n)


def build():
    rnd = random.Random(SEED)
    tex = int(os.environ.get("WORLD_TEX", "1024"))
    a = world_kit.WorldAsset(KEY, PALETTE, tex=tex, texel_m=0.028 * 1024 / tex,
                             paint={"key_dir": (0.3, 0.55, 1.0), "edge": 0.65, "grit": 0.07})
    plinth(a, rnd)
    collar(a, rnd)
    legs(a, rnd)
    claws(a, rnd)
    mast(a, rnd)
    rings(a, rnd)
    a.lap("parts")
    a.finish(bevel_m=0.025)
    dst = world_kit.out_dir(KEY)
    sizes = a.bake(dst) if "--notex" not in sys.argv else {}
    a.export(dst, sizes, centred=tuple("ring_%d" % i for i in range(len(RING_Z))))


if __name__ == "__main__":
    build()
