#!/usr/bin/env python3
"""World prop kit on the hero pipeline (brief + review: docs/assets/props.md;
design/art-bible.md §6.1-6.2 lane dressing, §4.6 neon policy, §10.6 budgets).

One asset, `world_props`: 16 separately placeable pieces on one shared painted
atlas, so the whole kit is one material per team (WorldModel.material). The
runtime (src/gameplay/views/world_props.gd) scatters them along walls, rails
and on roofs of Shardline Front; they carry no collision.

Pieces (each built apart so the bake does not shade it against the others,
exported with its own origin = floor centre of its footprint):
  crate, crate_stack, barrel, debris, puddle      ground clutter (neutral)
  ac_unit, cable_run, pipe_cluster                 wall-mounted service kit (neutral)
  barrier, bench, planter                          street furniture (neutral)
  street_lamp, holo_sign                           tall pieces: the light / neon sits
                                                   above 4 m (§4.6 rule 3)
  antenna, roof_vent                               roof-only skyline dressing
  kiosk, cargo                                     HQ-only: team / team_emit accents
                                                   (team colour only where ownership is true)

Orientation contract (WorldProps relies on it): Blender Z up; the BACK of every
piece is its -Y side and sits on the footprint's back edge, the front faces +Y
(Godot -Z after the Y-up export). Wall pieces put their back on the wall.
City neon uses only sign_teal / sign_pink / holo_white (§4.6 rule 2), never
amber, never in the team hue bands.

Run:  /tmp/venv/bin/python tools/art/world/props_kit.py [--notex] [--out <dir>]
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import world_kit  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

KEY = "world_props"
SEED = 7301
GAP = 5.0  # spacing of the pieces while baking (apart)

PALETTE = {
    "stone": "#B9B2A6", "stone_dark": "#8A8292", "stone_deep": "#6E6779",
    "iron": "#3B4052", "iron_dark": "#2C3040", "chrome": "#C9D4E2", "brass": "#BFA68A",
    "panel": "#5A5370", "ink": "#141726",
    "olive": "#6F7A5C", "olive_dark": "#525A45", "plum": "#6E4F7A", "slate": "#4F5B6E",
    "foliage": "#3F6B66", "foliage_lt": "#5E8F86", "soil": "#4A3F48",
    "puddle": "#3A3558",
    "teal": "#34D8C4", "pink": "#E255B5", "holo": "#E6F7FF",
    "neon": "#F4F7FF", "team": "#2E86FF",
}


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


def cyl(a, p0, p1, r0, r1, color, ch="flat", seg=10, max_len=0.8):
    """a.cyl split into sections no longer than `max_len`: one long tube unwraps to a
    single sliver island that the packer lays across the atlas diagonal (the first
    bake lost half the atlas that way)."""
    p0, p1 = Vector(p0), Vector(p1)
    n = max(1, int(math.ceil((p1 - p0).length / max_len)))
    for i in range(n):
        t0, t1 = i / n, (i + 1) / n
        a.cyl("Root", p0.lerp(p1, t0), p0.lerp(p1, t1), r0 + (r1 - r0) * t0, r0 + (r1 - r0) * t1, color, ch, seg=seg)


def post(a, c, size, color, ch="flat", bevel=0.25, max_len=0.9):
    """Tall box split into stacked sections (same reason as cyl)."""
    c = Vector(c)
    n = max(1, int(math.ceil(size[2] / max_len)))
    h = size[2] / n
    for i in range(n):
        a.box("Root", (c.x, c.y, c.z - size[2] / 2 + h * (i + 0.5)), (size[0], size[1], h), color, ch, bevel=bevel)


# ------------------------------------------------------------------ ground clutter
def crate_at(a, c, s, color="olive", rot=0.0, team=False):
    """Ribbed cargo crate of edge `s` standing at floor point c."""
    c = Vector(c)
    m = Matrix.Translation(c + Vector((0, 0, s / 2))) @ Matrix.Rotation(math.radians(rot), 4, "Z")
    a.box("Root", None, (s, s, s), color, bevel=0.12, mat=m)
    # chrome corner posts
    for sx in (-1, 1):
        for sy in (-1, 1):
            a.box("Root", None, (0.07, 0.07, s + 0.02), "chrome", "chrome", bevel=0.3,
                  mat=m @ Matrix.Translation((sx * (s / 2 - 0.02), sy * (s / 2 - 0.02), 0)))
    # horizontal ribs on the front (the back faces a wall), stencil band
    for sy in (1,):
        for z in (-s * 0.28, s * 0.28):
            a.box("Root", None, (s * 0.86, 0.04, 0.05), "olive_dark" if color == "olive" else "iron", bevel=0.3,
                  mat=m @ Matrix.Translation((0, sy * (s / 2 + 0.01), z)))
    band = "team" if team else "stone"
    a.box("Root", None, (s * 0.5, 0.02, s * 0.16), band, "team" if team else "flat", bevel=0.3,
          mat=m @ Matrix.Translation((0, s / 2 + 0.02, 0)))
    if team:
        a.box("Root", None, (s * 0.2, 0.02, 0.05), "neon", "team_emit", bevel=0.3,
              mat=m @ Matrix.Translation((s * 0.3, s / 2 + 0.035, s * 0.36)))
    # lid handles
    a.box("Root", None, (s * 0.3, 0.06, 0.04), "iron", bevel=0.3, mat=m @ Matrix.Translation((0, 0, s / 2 + 0.02)))


def crate(a, rnd):
    crate_at(a, (0, 0, 0), 0.9)


def crate_stack(a, rnd):
    crate_at(a, (-0.48, 0, 0), 0.9)
    crate_at(a, (0.5, 0.02, 0), 0.85, color="slate", rot=4)
    crate_at(a, (-0.4, -0.02, 0.9), 0.7, color="plum", rot=-7)
    # a strap over the bottom pair
    a.box("Root", (0.0, 0.45, 0.45), (1.9, 0.02, 0.06), "iron_dark", bevel=0.3)


def barrel(a, rnd):
    r, h = 0.3, 0.92
    a.cyl("Root", (0, 0, 0), (0, 0, h), r, r, "slate", seg=14)
    for z in (0.12, 0.46, 0.8):
        a.torus("Root", (0, 0, z), (0, 0, 1), r + 0.005, 0.022, "iron", seg=(18, 4))
    a.cyl("Root", (0, 0, h), (0, 0, h + 0.03), r * 0.92, r * 0.88, "iron", seg=14)
    a.cyl("Root", (0.12, 0.05, h + 0.03), (0.12, 0.05, h + 0.07), 0.05, 0.05, "brass", "chrome", seg=8)
    # hazard label (teal, not amber: §6.2 South), non-emissive
    a.box("Root", None, (0.22, 0.02, 0.2), "teal", bevel=0.3,
          mat=Matrix.Translation((0, r + 0.005, 0.62)))


def debris(a, rnd):
    # stone chunks broken off a ruin edge, a bent iron beam and loose bolts
    for i in range(7):
        ang = rnd.uniform(0, 2 * math.pi)
        rr = rnd.uniform(0.0, 0.45)
        s = rnd.uniform(0.18, 0.38)
        c = Vector((math.cos(ang) * rr * 1.2, math.sin(ang) * rr * 0.7, s * 0.4))
        a.box("Root", c, (s * 1.3, s, s * 0.8), rnd.choice(["stone", "stone_dark", "stone_deep"]), bevel=0.25,
              rot=(rnd.uniform(-15, 15), rnd.uniform(-15, 15), rnd.uniform(0, 180)), taper=(0.7, 0.8))
    beam(a, (-0.55, -0.15, 0.05), (0.1, 0.0, 0.32), 0.12, 0.08, "iron", out=(0, 0, 1))
    beam(a, (0.1, 0.0, 0.32), (0.55, 0.2, 0.12), 0.12, 0.08, "iron", out=(0, 0, 1))
    for _ in range(4):
        p = Vector((rnd.uniform(-0.55, 0.55), rnd.uniform(0.2, 0.4), 0.03))
        a.box("Root", p, (0.07, 0.04, 0.04), rnd.choice(["iron", "brass"]), bevel=0.4, rot=(0, 0, rnd.uniform(0, 180)))


def puddle(a, rnd):
    # flat drain: a grate against the kerb and an irregular puddle (2 cm), walkable over
    a.box("Root", (0, -0.3, 0.015), (0.6, 0.3, 0.03), "iron_dark", bevel=0.3)
    for k in range(5):
        a.box("Root", (-0.22 + k * 0.11, -0.3, 0.032), (0.04, 0.24, 0.012), "iron", bevel=0.2)
    a.prism((0, 0.05, 0.008), 0.5, 0.016, 14, "puddle", "chrome", bevel=0.0)
    a.box("Root", None, (0.7, 0.4, 0.016), "puddle", "chrome", bevel=0.0,
          mat=Matrix.Translation((0.35, 0.0, 0.009)) @ Matrix.Rotation(math.radians(20), 4, "Z"))


# ------------------------------------------------------------------ wall service kit
def ac_unit(a, rnd):
    w, d, h = 1.1, 0.62, 0.8
    z0 = 0.25
    # stand legs + the box
    for sx in (-1, 1):
        a.box("Root", (sx * 0.42, 0, z0 / 2), (0.08, d * 0.9, z0), "iron", bevel=0.3)
    a.box("Root", (0, 0, z0 + h / 2), (w, d, h), "stone_dark", bevel=0.1)
    a.box("Root", (0, 0, z0 + h + 0.02), (w + 0.04, d + 0.04, 0.05), "iron", bevel=0.3)
    # fan grille on the front
    fc = Vector((-0.15, d / 2 + 0.01, z0 + h / 2))
    a.cyl("Root", fc - Vector((0, 0.02, 0)), fc + Vector((0, 0.02, 0)), 0.3, 0.3, "iron_dark", seg=16)
    a.torus("Root", fc + Vector((0, 0.03, 0)), (0, 1, 0), 0.3, 0.025, "chrome", "chrome", seg=(20, 4))
    for k in range(4):
        ang = math.pi / 4 + k * math.pi / 2
        beam(a, fc + Vector((0, 0.04, 0)), fc + Vector((math.cos(ang) * 0.28, 0.04, math.sin(ang) * 0.28)),
             0.03, 0.02, "chrome", "chrome", out=(0, 1, 0))
    a.cyl("Root", fc, fc + Vector((0, 0.06, 0)), 0.06, 0.05, "brass", "chrome", seg=8)
    # louvred side panel and a status LED (Accent tier: tiny, non-team)
    for k in range(5):
        a.box("Root", (0.33, d / 2 + 0.01, z0 + 0.15 + k * 0.12), (0.3, 0.03, 0.04), "iron", bevel=0.3)
    a.box("Root", (0.42, d / 2 + 0.02, z0 + h - 0.08), (0.06, 0.02, 0.03), "teal", "emit", bevel=0.3)
    # pipes into the wall at the back
    for sx in (-0.3, -0.15):
        a.cyl("Root", (sx, -d / 2 + 0.05, z0 + h - 0.15), (sx, -d / 2 - 0.05, z0 + h + 0.25), 0.035, 0.035,
              "brass", "chrome", seg=8)


def cable_run(a, rnd):
    # conduits clamped flat to a wall: 3 m long, 0.3 m deep, with a junction box
    L = 3.0
    y = -0.15 + 0.07
    for i, (z, r, col) in enumerate(((2.4, 0.05, "iron_dark"), (2.25, 0.04, "slate"), (2.12, 0.03, "plum"))):
        cyl(a, (-L / 2, y + i * 0.02, z), (L / 2, y + i * 0.02, z), r, r, col, seg=8)
    for k in range(4):
        x = -L / 2 + 0.3 + k * 0.8
        a.box("Root", (x, y + 0.02, 2.26), (0.06, 0.16, 0.38), "iron", bevel=0.3)
    # drop down to a junction box at 1.0 m and a floor conduit
    cyl(a, (0.7, y, 2.12), (0.7, y, 1.25), 0.04, 0.04, "slate", seg=8)
    a.box("Root", (0.7, -0.15 + 0.12, 1.0), (0.5, 0.2, 0.55), "panel", bevel=0.2)
    a.box("Root", (0.7, -0.15 + 0.225, 1.0), (0.38, 0.02, 0.42), "stone_dark", bevel=0.2)
    a.box("Root", (0.86, -0.15 + 0.24, 1.18), (0.05, 0.02, 0.03), "pink", "emit", bevel=0.3)
    cyl(a, (0.7, y, 0.72), (0.7, y, 0.06), 0.04, 0.04, "slate", seg=8)
    cyl(a, (0.7, y, 0.06), (-L / 2, y, 0.06), 0.05, 0.05, "iron_dark", seg=8)
    # a sagging loose cable between two clamps
    pts = [Vector((-L / 2 + 0.3 + t * 1.6, y + 0.08, 2.05 - math.sin(t * math.pi) * 0.35)) for t in (0, 0.25, 0.5, 0.75, 1)]
    for p0, p1 in zip(pts, pts[1:]):
        a.cyl("Root", p0, p1, 0.025, 0.025, "ink", seg=6)


def pipe_cluster(a, rnd):
    # three risers against the wall, a manifold, valves (South docks' mana pipelines)
    for i, (x, r, col) in enumerate(((-0.5, 0.12, "slate"), (-0.12, 0.09, "iron"), (0.3, 0.14, "plum"))):
        cyl(a, (x, -0.1, 0.0), (x, -0.1, 2.7), r, r, col, seg=10)
        for z in (0.3, 2.4):
            a.torus("Root", (x, -0.1, z), (0, 0, 1), r + 0.01, 0.025, "brass", "chrome", seg=(12, 4))
    cyl(a, (-0.75, 0.05, 1.0), (0.65, 0.05, 1.0), 0.08, 0.08, "iron_dark", seg=10)
    for x in (-0.5, 0.3):
        a.cyl("Root", (x, -0.02, 1.0), (x, 0.14, 1.0), 0.1, 0.1, "chrome", "chrome", seg=10)
    # valve wheel and gauge (holo gauge face, small)
    a.torus("Root", (-0.12, 0.18, 1.55), (0, 1, 0), 0.14, 0.02, "brass", "chrome", seg=(16, 4))
    a.cyl("Root", (-0.12, 0.0, 1.55), (-0.12, 0.18, 1.55), 0.025, 0.025, "iron", seg=6)
    a.cyl("Root", (0.3, 0.05, 1.75), (0.3, 0.12, 1.75), 0.09, 0.09, "chrome", "chrome", seg=12)
    a.cyl("Root", (0.3, 0.12, 1.75), (0.3, 0.13, 1.75), 0.07, 0.07, "teal", "emit", seg=12)
    a.box("Root", (0.0, -0.05, 0.05), (1.6, 0.4, 0.1), "stone_dark", bevel=0.2)


# ------------------------------------------------------------------ street furniture
def barrier(a, rnd):
    # jersey barrier, 2 m, with teal hazard chevrons (not amber, §6.2)
    L, d = 2.0, 0.6
    a.box("Root", (0, 0, 0.12), (L, d, 0.24), "stone", bevel=0.15)
    a.box("Root", (0, 0, 0.24 + 0.3), (L, d * 0.45, 0.6), "stone", bevel=0.2, taper=(1.0, 0.55))
    a.box("Root", (0, 0, 0.86), (L, 0.18, 0.04), "stone_dark", bevel=0.3)
    for sy in (-1, 1):
        for k in range(4):
            a.box("Root", None, (0.14, 0.02, 0.32), "teal" if k % 2 == 0 else "ink", bevel=0.2,
                  mat=Matrix.Translation((-0.6 + k * 0.4, sy * 0.2, 0.45)) @ Matrix.Rotation(math.radians(sy * 14), 4, "X")
                  @ Matrix.Rotation(math.radians(30), 4, "Y"))
    for sx in (-1, 1):
        a.box("Root", (sx * 0.8, 0, 0.05), (0.18, d + 0.02, 0.1), "iron", bevel=0.3)


def bench(a, rnd):
    L = 1.8
    for sx in (-1, 1):
        x = sx * 0.75
        a.box("Root", (x, 0.02, 0.22), (0.08, 0.5, 0.44), "iron", bevel=0.25)
        a.box("Root", (x, -0.22, 0.6), (0.08, 0.06, 0.6), "iron", bevel=0.3)
    for k in range(3):
        a.box("Root", (0, 0.2 - k * 0.15, 0.46), (L, 0.12, 0.05), "plum", bevel=0.3)
    for k in range(2):
        a.box("Root", None, (L, 0.04, 0.12), "plum", bevel=0.3,
              mat=Matrix.Translation((0, -0.22, 0.68 + k * 0.16)) @ Matrix.Rotation(math.radians(-10), 4, "X"))
    a.box("Root", (0.0, 0.0, 0.03), (L - 0.2, 0.3, 0.06), "stone_dark", bevel=0.3)


def planter(a, rnd):
    w, d, h = 1.6, 0.8, 0.5
    a.box("Root", (0, 0, h / 2), (w, d, h), "stone", bevel=0.15)
    a.box("Root", (0, 0, h + 0.02), (w + 0.08, d + 0.08, 0.06), "stone_dark", bevel=0.25)
    a.box("Root", (0, 0, h + 0.03), (w - 0.14, d - 0.14, 0.04), "soil", bevel=0.2)
    # low neon kick strip at 0.1 m (below body height, §4.6)
    a.box("Root", (0, d / 2 + 0.01, 0.1), (w - 0.2, 0.02, 0.04), "teal", "emit", bevel=0.3)
    # neon-city plants: blade fronds and two shrubs, cool teal foliage (not heal green)
    for i in range(9):
        x = -0.6 + i * 0.15 + rnd.uniform(-0.04, 0.04)
        y = rnd.uniform(-0.2, 0.2)
        hh = rnd.uniform(0.45, 0.85)
        tilt = Vector((rnd.uniform(-0.25, 0.25), rnd.uniform(-0.2, 0.2), 1)).normalized()
        a.cyl("Root", (x, y, h + 0.02), Vector((x, y, h + 0.02)) + tilt * hh, 0.05, 0.0,
              rnd.choice(["foliage", "foliage_lt"]), seg=5)
    for x in (-0.35, 0.4):
        a.sphere("Root", (x, 0.05, h + 0.3), (0.28, 0.24, 0.26), "foliage", seg=(10, 6))
        a.sphere("Root", (x + 0.08, 0.1, h + 0.45), (0.16, 0.14, 0.14), "foliage_lt", seg=(8, 5))


def kiosk(a, rnd):
    # HQ info terminal: team holo screen and trim (team colour only in HQs, §4.6 rule 1)
    a.box("Root", (0, 0, 0.08), (0.9, 0.7, 0.16), "stone_dark", bevel=0.2)
    a.box("Root", (0, -0.05, 0.16 + 0.95), (0.7, 0.5, 1.9), "panel", bevel=0.15, taper=(1.0, 0.85))
    a.box("Root", None, (0.56, 0.04, 0.7), "ink", bevel=0.2,
          mat=Matrix.Translation((0, 0.2, 1.45)) @ Matrix.Rotation(math.radians(-8), 4, "X"))
    a.box("Root", None, (0.48, 0.02, 0.6), "neon", "team_emit", bevel=0.2,
          mat=Matrix.Translation((0, 0.225, 1.45)) @ Matrix.Rotation(math.radians(-8), 4, "X"))
    a.box("Root", None, (0.6, 0.35, 0.06), "chrome", "chrome", bevel=0.3,
          mat=Matrix.Translation((0, 0.3, 0.98)) @ Matrix.Rotation(math.radians(20), 4, "X"))
    for k in range(3):
        a.box("Root", (-0.18 + k * 0.18, 0.42, 1.01), (0.1, 0.06, 0.03), "iron", bevel=0.3)
    for sx in (-1, 1):
        a.box("Root", (sx * 0.37, 0.18, 1.1), (0.04, 0.03, 1.7), "team", "team", bevel=0.3)
    a.box("Root", (0, -0.05, 2.12), (0.8, 0.6, 0.06), "chrome", "chrome", bevel=0.3)
    a.box("Root", (0, 0.24, 2.0), (0.5, 0.02, 0.12), "neon", "team_emit", bevel=0.3)


def cargo(a, rnd):
    # HQ supply pile: team-banded crates and a barrel-sized canister
    crate_at(a, (-0.5, 0, 0), 0.9, color="slate", team=True)
    crate_at(a, (0.45, 0.05, 0), 0.8, color="olive", rot=-5, team=True)
    crate_at(a, (-0.45, 0.0, 0.9), 0.72, color="slate", rot=6, team=True)
    a.cyl("Root", (0.55, -0.05, 0.8), (0.55, -0.05, 1.3), 0.18, 0.18, "chrome", "chrome", seg=8)
    a.torus("Root", (0.55, -0.05, 1.05), (0, 0, 1), 0.185, 0.02, "neon", "team_emit", seg=(10, 4))


# ------------------------------------------------------------------ tall pieces
def street_lamp(a, rnd):
    H = 4.6
    a.prism((0, 0, 0.15), 0.25, 0.3, 8, "stone_dark", bevel=0.02, rot_deg=22.5)
    a.cyl("Root", (0, 0, 0.3), (0, 0, 0.5), 0.12, 0.09, "brass", "chrome", seg=10)
    cyl(a, (0, 0, 0.5), (0, 0, H), 0.075, 0.06, "iron", seg=10)
    for z in (1.2, 2.6):
        a.torus("Root", (0, 0, z), (0, 0, 1), 0.075, 0.018, "chrome", "chrome", seg=(12, 4))
    # curved arm reaching over the walkway (+Y), lamp head above 4 m (§4.6)
    pts = [Vector((0, 0, H)), Vector((0, 0.35, H + 0.25)), Vector((0, 0.8, H + 0.3)), Vector((0, 1.15, H + 0.18))]
    for p0, p1 in zip(pts, pts[1:]):
        a.cyl("Root", p0, p1, 0.05, 0.045, "iron", seg=8)
    hc = Vector((0, 1.2, H + 0.05))
    a.box("Root", hc + Vector((0, 0, 0.08)), (0.32, 0.5, 0.12), "iron_dark", bevel=0.25, taper=(0.7, 0.8))
    a.box("Root", hc - Vector((0, 0, 0.02)), (0.24, 0.4, 0.06), "holo", "emit", bevel=0.3)
    # a small teal holo tag on the pole at 4.2 m
    a.box("Root", (0.0, 0.08, 4.15), (0.12, 0.03, 0.4), "teal", "emit", bevel=0.3)
    # service hatch and cable at the foot
    a.box("Root", (0, 0.1, 0.75), (0.1, 0.03, 0.26), "panel", bevel=0.3)


def holo_sign(a, rnd):
    # street holo-sign: post, ink backplate with a neon frame and glyphs at 4.2-5.6 m
    a.box("Root", (0, 0, 0.1), (0.5, 0.5, 0.2), "stone_dark", bevel=0.2)
    post(a, (0, 0, 0.2 + 2.1), (0.16, 0.16, 4.2), "iron")
    post(a, (0, 0.09, 2.0), (0.06, 0.02, 3.2), "slate", bevel=0.3)
    z = 4.9
    a.box("Root", (0, 0.0, z), (1.6, 0.12, 1.3), "ink", bevel=0.15)
    for (dx, dz, sx, sz) in ((0, 0.62, 1.64, 0.06), (0, -0.62, 1.64, 0.06), (0.8, 0, 0.06, 1.3), (-0.8, 0, 0.06, 1.3)):
        a.box("Root", (dx, 0.08, z + dz), (sx, 0.04, sz), "pink", "emit", bevel=0.3)
    # original glyph strokes (no real script), teal
    for k in range(3):
        a.box("Root", (-0.45 + k * 0.45, 0.08, z + 0.15), (0.08, 0.02, 0.5), "teal", "emit", bevel=0.3)
        a.box("Root", (-0.45 + k * 0.45 + 0.1, 0.08, z - 0.15), (0.26, 0.02, 0.07), "teal", "emit", bevel=0.3)
    a.box("Root", (0, 0.08, z - 0.4), (1.1, 0.02, 0.05), "holo", "emit", bevel=0.3)
    for sx in (-1, 1):
        beam(a, (0, 0, 3.6), (sx * 0.6, 0, z - 0.65), 0.06, 0.06, "iron", out=(0, 1, 0))


def antenna(a, rnd):
    # roof-only mast: plate, guyed lattice mast, two dishes, pink beacon on top
    a.box("Root", (0, 0, 0.06), (1.0, 1.0, 0.12), "iron_dark", bevel=0.2)
    H = 6.0
    for k in range(3):
        ang = k * 2 * math.pi / 3
        o = Vector((math.cos(ang), math.sin(ang), 0)) * 0.16
        cyl(a, o + Vector((0, 0, 0.12)), o * 0.4 + Vector((0, 0, H)), 0.03, 0.025, "chrome", "chrome", seg=6, max_len=1.0)
        cyl(a, o * 3.0 + Vector((0, 0, 0.12)), o * 0.6 + Vector((0, 0, H * 0.6)), 0.012, 0.012, "ink", seg=4, max_len=2.5)
    for z in (1.0, 2.0, 3.0, 4.0, 5.0):
        a.torus("Root", (0, 0, z), (0, 0, 1), 0.16 * (1 - z / H * 0.6), 0.02, "iron", seg=(10, 4))
    for z, ang, r in ((3.2, 30, 0.45), (4.4, 200, 0.32)):
        d = Vector((math.cos(math.radians(ang)), math.sin(math.radians(ang)), 0.3)).normalized()
        c = Vector((0, 0, z)) + d * 0.25
        a.cyl("Root", (0, 0, z), c, 0.03, 0.03, "iron", seg=6)
        a.cyl("Root", c, c + d * 0.12, r, r * 0.4, "stone", seg=14)
        a.cyl("Root", c + d * 0.1, c + d * 0.4, 0.02, 0.02, "chrome", "chrome", seg=6)
    a.sphere("Root", (0, 0, H + 0.08), (0.08, 0.08, 0.1), "pink", "emit", seg=(10, 6))


def roof_vent(a, rnd):
    # roof extractor: housing, fan cowl, duct bend, and a teal status strip
    a.box("Root", (0, 0, 0.08), (1.5, 1.2, 0.16), "iron_dark", bevel=0.2)
    a.box("Root", (-0.25, 0, 0.16 + 0.4), (0.95, 1.0, 0.8), "stone_dark", bevel=0.12)
    a.cyl("Root", (-0.25, 0, 0.96), (-0.25, 0, 1.15), 0.42, 0.38, "iron", seg=16)
    a.torus("Root", (-0.25, 0, 1.15), (0, 0, 1), 0.38, 0.03, "chrome", "chrome", seg=(20, 4))
    for k in range(5):
        ang = k * 2 * math.pi / 5
        beam(a, (-0.25, 0, 1.12), (-0.25 + math.cos(ang) * 0.34, math.sin(ang) * 0.34, 1.12), 0.1, 0.02,
             "iron_dark", out=(0, 0, 1))
    a.cyl("Root", (0.45, 0.2, 0.16), (0.45, 0.2, 0.9), 0.17, 0.17, "slate", seg=12)
    a.cyl("Root", (0.45, 0.2, 0.9), (0.25, 0.2, 1.05), 0.17, 0.17, "slate", seg=12)
    a.box("Root", (-0.25, 0.51, 0.7), (0.6, 0.02, 0.05), "teal", "emit", bevel=0.3)
    for k in range(4):
        a.box("Root", (-0.25, 0.51, 0.3 + k * 0.08), (0.7, 0.03, 0.03), "iron", bevel=0.3)


PIECES = [
    ("crate", crate), ("crate_stack", crate_stack), ("barrel", barrel), ("debris", debris), ("puddle", puddle),
    ("ac_unit", ac_unit), ("cable_run", cable_run), ("pipe_cluster", pipe_cluster),
    ("barrier", barrier), ("bench", bench), ("planter", planter),
    ("street_lamp", street_lamp), ("holo_sign", holo_sign), ("antenna", antenna), ("roof_vent", roof_vent),
    ("kiosk", kiosk), ("cargo", cargo),
]


def build():
    rnd = random.Random(SEED)
    a = world_kit.WorldAsset(KEY, PALETTE, tex=2048, texel_m=0.005, paint={"edge": 0.65, "grit": 0.07})
    for i, (name, fn) in enumerate(PIECES):
        # everything lives in a piece; a 4 x 5 grid keeps the bake's AO apart
        with a.piece(name, apart=((i % 5) * GAP, (i // 5) * GAP, 0.0)):
            fn(a, rnd)
    a.lap("parts")
    a.finish(bevel_m=0.01, drop_floor=True)
    dst = world_kit.out_dir(KEY)
    sizes = a.bake(dst) if "--notex" not in sys.argv else {}
    a.export(dst, sizes)


if __name__ == "__main__":
    build()
