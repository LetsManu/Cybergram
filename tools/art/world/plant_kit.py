#!/usr/bin/env python3
"""Plant task kit on the hero pipeline (design brief: docs/assets/plant.md;
design/art-bible.md §6.3; match-flow-and-map.md §3.4 Plant).

Three assets, one per run of `--only <key>` (default: all three in turn):

  cell_cradle    the pickup station a team takes its Mana Cell from (map
                 CellCradle_* pads, E14). Square plate with team corner
                 brackets and inward chevrons, a chrome clamp cradle that holds
                 the Cell at 1.0 m (HardpointView lift at CRADLE state).
  mana_cell      the Cell itself: a glowing capsule in a chrome cage (art bible
                 §6.3). Pivot at its centre: HardpointView moves and spins it.
  charge_cradle  the Plant hardpoint's machine: a tuning-fork "Y" pylon whose
                 socket takes the Cell at 2.9 m. The stem matches the map's
                 collision box (PylonStem 0.9 x 2.2 x 0.9). Piece `bracket` is
                 one L corner of the square pad (pivot at the corner); the
                 runtime places four at the zone's half-width.

Blender space: Z up, origin = the object's floor centre.
Run:  /tmp/venv/bin/python tools/art/world/plant_kit.py [--only <key>] [--notex] [--out <dir>]
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
    "chrome": "#C9D4E2", "brass": "#BFA68A", "panel": "#5A5370", "neon": "#F4F7FF",
    "team": "#2E86FF",
}
CELL_Z = 1.0          # HardpointView: Cell centre above the Cradle point
SOCKET_Z = 2.9        # HardpointView: planted Cell centre above the hardpoint
STEM = (0.9, 2.2)     # map PylonStem (collision): width, height
BRACKET_AT = Vector((9.0, 0.0, 0.0))   # built apart from the pylon (bake), rebased to the corner


def beam(a, p0, p1, w, d, color, ch="flat", out=None, bevel=0.3, taper=(1.0, 1.0)):
    """Box from p0 to p1, cross-section w x d, its X axis facing `out`."""
    p0, p1 = Vector(p0), Vector(p1)
    z = (p1 - p0).normalized()
    o = Vector(out) if out is not None else Vector((1, 0, 0))
    x = o - z * o.dot(z)
    x = x.normalized() if x.length > 1e-6 else Vector((1, 0, 0))
    m = Matrix((x, z.cross(x), z)).transposed().to_4x4()
    m.translation = (p0 + p1) / 2
    a.box("Root", None, (w, d, (p1 - p0).length), color, ch, bevel=bevel, taper=taper, mat=m)


def chevron(a, c, ang, size, z):
    """Team-neon chevron on the floor pointing along `ang` (radians)."""
    for s in (1, -1):
        rot = ang + s * math.radians(135)
        o = Vector((math.cos(rot), math.sin(rot), 0)) * size * 0.35
        a.box("Root", None, (size * 0.7, size * 0.16, 0.03), "neon", "team_emit", bevel=0.3,
              mat=Matrix.Translation(Vector(c) + o + Vector((0, 0, z))) @ Matrix.Rotation(rot, 4, "Z"))


# ------------------------------------------------------------------ cell_cradle
def cell_cradle(rnd):
    a = world_kit.WorldAsset("cell_cradle", PALETTE, tex=1024, texel_m=0.006, paint={"edge": 0.7, "grit": 0.06})
    w = 2.0
    # plate: stone slab on an iron skirt, brass trim, inset service panels
    a.box("Root", (0, 0, 0.06), (w + 0.12, w + 0.12, 0.12), "iron_dark", bevel=0.2)
    a.box("Root", (0, 0, 0.15), (w, w, 0.1), "stone", bevel=0.25)
    a.box("Root", (0, 0, 0.205), (w * 0.62, w * 0.62, 0.02), "stone_dark", bevel=0.2)
    for k in range(4):
        ang = k * math.pi / 2
        o = Vector((math.cos(ang), math.sin(ang), 0))
        side = o.cross(Vector((0, 0, 1)))
        # brass edge trim with rivets
        a.box("Root", None, (w * 0.8, 0.06, 0.04), "brass", "chrome", bevel=0.3,
              mat=Matrix.Translation(o * (w * 0.5 - 0.04) + Vector((0, 0, 0.21))) @ Matrix.Rotation(ang + math.pi / 2, 4, "Z"))
        for j in range(5):
            p = o * (w * 0.5 - 0.1) + side * (-0.7 + j * 0.35) + Vector((0, 0, 0.205))
            a.box("Root", p, (0.05, 0.05, 0.03), "chrome", "chrome", bevel=0.4)
        # inward team chevron: "take it here"
        chevron(a, o * 0.72, ang + math.pi, 0.32, 0.215)
        # L corner bracket (team), raised: the Plant floor language (art bible §6.3)
        cang = ang + math.pi / 4
        co = Vector((math.cos(cang), math.sin(cang), 0)) * (w * 0.5 * math.sqrt(2) - 0.12)
        for t in (0, 1):
            leg_dir = Vector((-math.cos(ang), -math.sin(ang), 0)) if t == 0 else Vector((-math.cos(ang + math.pi / 2), -math.sin(ang + math.pi / 2), 0))
            beam(a, co + Vector((0, 0, 0.2)), co + leg_dir * 0.55 + Vector((0, 0, 0.2)), 0.14, 0.22, "team", "team",
                 out=Vector((0, 0, 1)), bevel=0.3)
        a.box("Root", co + Vector((0, 0, 0.36)), (0.16, 0.16, 0.06), "neon", "team_emit", bevel=0.3)
    # pedestal: hex collar on a stepped iron drum, vents
    a.prism((0, 0, 0.3), 0.5, 0.2, 6, "iron", bevel=0.03, rot_deg=30)
    a.prism((0, 0, 0.47), 0.42, 0.16, 6, "panel", bevel=0.03, rot_deg=30, inset=(0.015, 0.2))
    a.prism((0, 0, 0.58), 0.46, 0.07, 6, "brass", "chrome", bevel=0.03, rot_deg=30)
    a.torus("Root", (0, 0, 0.63), (0, 0, 1), 0.34, 0.025, "neon", "team_emit", seg=(24, 4))
    # four clamp arms that cradle the Cell (centre at CELL_Z): knuckle, curl, team tips
    for k in range(4):
        ang = math.pi / 4 + k * math.pi / 2
        o = Vector((math.cos(ang), math.sin(ang), 0))
        b = o * 0.36 + Vector((0, 0, 0.62))
        m = o * 0.42 + Vector((0, 0, CELL_Z - 0.05))
        t = o * 0.27 + Vector((0, 0, CELL_Z + 0.42))
        beam(a, b, m, 0.11, 0.09, "chrome", "chrome", out=o, taper=(0.85, 0.85))
        beam(a, m, t, 0.09, 0.08, "chrome", "chrome", out=o, taper=(0.75, 0.75))
        a.sphere("Root", m, (0.07, 0.07, 0.07), "brass", "chrome", seg=(10, 6))
        a.box("Root", t + Vector((0, 0, 0.04)), (0.06, 0.06, 0.08), "neon", "team_emit", bevel=0.3)
        # hydraulic piston behind each arm
        a.cyl("Root", o * 0.47 + Vector((0, 0, 0.5)), o * 0.5 + Vector((0, 0, 0.8)), 0.03, 0.03, "iron", seg=8)
    # side console: the cradle's charger with a status strip and a cable to the drum
    c = Vector((0.0, -0.78, 0.2))
    a.box("Root", c + Vector((0, 0, 0.18)), (0.5, 0.22, 0.36), "iron", bevel=0.25, taper=(1.0, 0.8))
    a.box("Root", c + Vector((0, -0.08, 0.26)), (0.34, 0.04, 0.08), "neon", "team_emit", bevel=0.3)
    for j in range(3):
        a.box("Root", c + Vector((-0.12 + j * 0.12, -0.11, 0.12)), (0.07, 0.02, 0.07), "panel", bevel=0.3)
    a.cyl("Root", c + Vector((0, 0.1, 0.12)), Vector((0, -0.42, 0.32)), 0.035, 0.035, "iron_dark", seg=8)
    # loose bolts / a dropped spanner at the plate edge (grounding detail)
    for _ in range(4):
        ang = rnd.uniform(0, 2 * math.pi)
        p = Vector((math.cos(ang), math.sin(ang), 0)) * rnd.uniform(1.15, 1.35)
        a.box("Root", p + Vector((0, 0, 0.03)), (0.08, 0.05, 0.05), rnd.choice(["iron", "brass"]), bevel=0.4,
              rot=(0, 0, rnd.uniform(0, 180)))
    return a, {}


# ------------------------------------------------------------------ mana_cell
def mana_cell(rnd):
    a = world_kit.WorldAsset("mana_cell", PALETTE, tex=512, texel_m=0.0025, paint={"edge": 0.7, "grit": 0.03})
    L, r = 0.42, 0.15
    # glowing capsule core (team)
    a.cyl("Root", (0, 0, -L / 2), (0, 0, L / 2), r, r, "neon", "team_emit", seg=12)
    for s in (1, -1):
        a.sphere("Root", (0, 0, s * L / 2), (r, r, r * 0.8), "neon", "team_emit", seg=(12, 6),
                 clip=[((0, 0, 0), (0, 0, -s))])
        # chrome end caps with a brass ring and a contact pin
        a.cyl("Root", (0, 0, s * (L / 2 + 0.06)), (0, 0, s * (L / 2 + 0.14)), 0.2, 0.17, "chrome", "chrome", seg=10)
        a.torus("Root", (0, 0, s * (L / 2 + 0.07)), (0, 0, 1), 0.2, 0.022, "brass", "chrome", seg=(18, 4))
        a.cyl("Root", (0, 0, s * (L / 2 + 0.14)), (0, 0, s * (L / 2 + 0.2)), 0.05, 0.035, "iron", seg=8)
    # cage bars and a mid band with a rune tag
    for k in range(4):
        ang = math.pi / 4 + k * math.pi / 2
        o = Vector((math.cos(ang), math.sin(ang), 0))
        beam(a, o * 0.185 + Vector((0, 0, -L / 2 - 0.08)), o * 0.185 + Vector((0, 0, L / 2 + 0.08)), 0.045, 0.035,
             "chrome", "chrome", out=o)
    a.torus("Root", (0, 0, 0), (0, 0, 1), 0.19, 0.02, "iron", seg=(18, 4))
    a.box("Root", (0.0, -0.205, 0.0), (0.09, 0.02, 0.06), "brass", "chrome", bevel=0.3)
    return a, {}


# ------------------------------------------------------------------ charge_cradle
def charge_cradle(rnd):
    a = world_kit.WorldAsset("charge_cradle", PALETTE, tex=1024, texel_m=0.008, paint={"edge": 0.65, "grit": 0.07})
    sw, sh = STEM
    # footing: square stepped base, stone with brass edge and team corner lamps
    a.box("Root", (0, 0, 0.1), (2.6, 2.6, 0.2), "stone_dark", bevel=0.15)
    a.box("Root", (0, 0, 0.27), (2.0, 2.0, 0.16), "stone", bevel=0.2)
    for k in range(4):
        ang = k * math.pi / 2 + math.pi / 4
        o = Vector((math.cos(ang), math.sin(ang), 0))
        a.box("Root", o * 1.25 + Vector((0, 0, 0.24)), (0.22, 0.22, 0.08), "neon", "team_emit", bevel=0.3)
        chevron(a, o * 0.93 * 1.0 + Vector((0, 0, 0)), ang + math.pi, 0.3, 0.355)
    # stem: matches the collision box, iron core with stone cladding plates and a team channel
    a.box("Root", (0, 0, 0.35 + (sh - 0.35) / 2), (sw * 0.86, sw * 0.86, sh - 0.35), "iron", bevel=0.2, taper=(0.9, 0.9))
    for k in range(4):
        ang = k * math.pi / 2
        o = Vector((math.cos(ang), math.sin(ang), 0))
        rot = Matrix.Rotation(ang, 4, "Z")
        a.box("Root", None, (0.06, sw * 0.7, 1.1), "stone", bevel=0.3,
              mat=Matrix.Translation(o * (sw * 0.45) + Vector((0, 0, 0.95))) @ rot)
        a.box("Root", None, (0.04, 0.1, 1.3), "neon", "team_emit", bevel=0.3,
              mat=Matrix.Translation(o * (sw * 0.47) + Vector((0, 0, 1.0))) @ rot)
        for j in range(3):
            side = o.cross(Vector((0, 0, 1)))
            a.box("Root", o * (sw * 0.48) + side * 0.25 + Vector((0, 0, 0.5 + j * 0.45)), (0.05, 0.05, 0.05),
                  "chrome", "chrome", bevel=0.4)
    a.box("Root", (0, 0, sh - 0.05), (sw + 0.1, sw + 0.1, 0.16), "brass", "chrome", bevel=0.25)
    # socket cup that takes the Cell (centre at SOCKET_Z)
    a.cyl("Root", (0, 0, sh + 0.03), (0, 0, SOCKET_Z - 0.35), 0.34, 0.3, "iron", seg=12)
    a.torus("Root", (0, 0, SOCKET_Z - 0.38), (0, 0, 1), 0.3, 0.05, "chrome", "chrome", seg=(24, 6))
    a.torus("Root", (0, 0, SOCKET_Z - 0.3), (0, 0, 1), 0.24, 0.025, "neon", "team_emit", seg=(24, 4))
    # the two prongs of the "Y": brass knuckle, chrome arm with a team channel, tip lamp
    for s in (1, -1):
        b = Vector((s * 0.32, 0, sh - 0.05))
        m = Vector((s * 0.62, 0, SOCKET_Z - 0.1))
        t = Vector((s * 0.9, 0, SOCKET_Z + 1.05))
        out = Vector((s, 0, 0))
        beam(a, b, m, 0.32, 0.36, "chrome", "chrome", out=out, taper=(0.9, 0.9))
        beam(a, m, t, 0.26, 0.3, "chrome", "chrome", out=out, taper=(0.7, 0.8))
        a.sphere("Root", m, (0.22, 0.22, 0.22), "brass", "chrome", seg=(12, 8))
        # inner team channel (lights from base to tip as the Cell charges: design §6.3)
        beam(a, m + Vector((-s * 0.14, 0, 0.1)), t + Vector((-s * 0.1, 0, -0.08)), 0.05, 0.12, "neon", "team_emit",
             out=out)
        a.box("Root", t + Vector((0, 0, 0.12)), (0.2, 0.24, 0.18), "neon", "team_emit", bevel=0.3)
        # hydraulic brace from the stem to the knuckle
        a.cyl("Root", Vector((s * 0.36, 0.22, 1.4)), m + Vector((0, 0.2, -0.05)), 0.05, 0.05, "iron", seg=8)
        a.cyl("Root", Vector((s * 0.36, -0.22, 1.4)), m + Vector((0, -0.2, -0.05)), 0.05, 0.05, "iron", seg=8)
    # cables from the base into the stem
    for s in (1, -1):
        a.cyl("Root", Vector((s * 0.85, 0.6, 0.36)), Vector((s * 0.42, 0.35, 0.8)), 0.06, 0.06, "iron_dark", seg=8)
    # one L corner bracket of the square pad, built apart and rebased to its corner:
    # legs along Blender -X and +Y (Godot -X and -Z), 3 m each, 0.5 m high (map greybox).
    with a.piece("bracket"):
        c = BRACKET_AT
        for d in (Vector((-1, 0, 0)), Vector((0, 1, 0))):
            beam(a, c + Vector((0, 0, 0.22)), c + d * 3.0 + Vector((0, 0, 0.22)), 0.4, 0.44, "stone", out=Vector((0, 0, 1)),
                 bevel=0.2)
            beam(a, c + d * 0.2 + Vector((0, 0, 0.47)), c + d * 2.9 + Vector((0, 0, 0.47)), 0.3, 0.06, "team", "team",
                 out=Vector((0, 0, 1)), bevel=0.3)
            for j in range(4):
                p = c + d * (0.5 + j * 0.75)
                n = Vector((d.y, -d.x, 0))
                a.box("Root", p + n * 0.21 + Vector((0, 0, 0.24)), (0.18 if d.x else 0.04, 0.04 if d.x else 0.18, 0.24),
                      "neon", "team_emit", bevel=0.3)
        a.box("Root", c + Vector((0, 0, 0.3)), (0.6, 0.6, 0.6), "stone_dark", bevel=0.2)
        a.box("Root", c + Vector((0, 0, 0.64)), (0.34, 0.34, 0.1), "neon", "team_emit", bevel=0.3)
    return a, {"bracket": tuple(BRACKET_AT)}


BUILDERS = {"cell_cradle": (cell_cradle, 3101), "mana_cell": (mana_cell, 3102), "charge_cradle": (charge_cradle, 3103)}


def build(key):
    fn, seed = BUILDERS[key]
    a, rebase = fn(random.Random(seed))
    a.lap("parts")
    a.finish(bevel_m=0.006 if key == "mana_cell" else 0.012, drop_floor=key != "mana_cell")
    dst = world_kit.out_dir(key)
    sizes = a.bake(dst) if "--notex" not in sys.argv else {}
    a.export(dst, sizes, rebase=rebase)


if __name__ == "__main__":
    keys = [sys.argv[sys.argv.index("--only") + 1]] if "--only" in sys.argv else list(BUILDERS)
    for k in keys:
        build(k)
