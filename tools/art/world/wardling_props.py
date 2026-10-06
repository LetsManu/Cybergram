#!/usr/bin/env python3
"""Wardling v2 props (brief: docs/assets/wardling.md; art bible §5.3-5.4): the tier,
class and Elite pieces that WardlingModel attaches to the rig's bones, so one rigged
body (tools/art/hero_defs_wardling.py) serves every tier and class.

Pieces (each built around its own attachment point, which is its local origin):
  plate_l, plate_r  tier II+: heavy shoulder armour over the pauldrons (Clavicle bones)
  crest             tier II+: helmet crest fin (Head, top of the helmet)
  crown             tier III: three team crystal shards in chrome claws (Head)
  sash, sash_own    personal squad: team owner band across the chest (UpperChest);
                    _own adds the gold knot (your own squad)
  ring_own          own squad: ground ring (model root)
  pennant           Vanguard: pole and team flag off the back reactor (UpperChest)
  elite             Vesper's Elite: gold halo and floating spindle over the helmet (Head)
Neutral colours with team channels, so one bake serves both teams.

Blender space: Z up, front = +Y (Godot -Z).
Run:  /tmp/venv/bin/python tools/art/world/wardling_props.py [--notex] [--out <dir>]
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import world_kit  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

KEY = "wardling_props"
PALETTE = {"shell": "#E8E3DA", "shell_dk": "#9C97A3", "trim": "#D2AE5E", "gun": "#3B4052", "chrome": "#C9D4E2",
           "gold_glow": "#FFD36B", "neon": "#F4F7FF", "team": "#2E86FF"}


def beam(a, p0, p1, w, d, color, ch="flat", out=None, bevel=0.3, taper=(1.0, 1.0)):
    p0, p1 = Vector(p0), Vector(p1)
    z = (p1 - p0).normalized()
    o = Vector(out) if out is not None else Vector((1, 0, 0))
    x = o - z * o.dot(z)
    x = x.normalized() if x.length > 1e-6 else Vector((1, 0, 0))
    m = Matrix((x, z.cross(x), z)).transposed().to_4x4()
    m.translation = (p0 + p1) / 2
    a.box("Root", None, (w, d, (p1 - p0).length), color, ch, bevel=bevel, taper=taper, mat=m)


def plate(a, sx):
    """Layered shoulder plate: three overlapping lames, trim rim, team stripe, rivets."""
    for i, (w, d, z) in enumerate(((0.17, 0.19, 0.03), (0.15, 0.17, 0.0), (0.13, 0.15, -0.03))):
        a.box("Root", None, (w, d, 0.035), "shell" if i != 1 else "shell_dk", bevel=0.4,
              mat=Matrix.Translation((sx * (0.015 + i * 0.025), 0, z)) @ Matrix.Rotation(math.radians(-24 * sx), 4, "Y"))
    a.box("Root", None, (0.16, 0.025, 0.03), "team", "team", bevel=0.3,
          mat=Matrix.Translation((sx * 0.02, 0.09, 0.03)) @ Matrix.Rotation(math.radians(-24 * sx), 4, "Y"))
    a.box("Root", None, (0.175, 0.2, 0.012), "trim", "chrome", bevel=0.3,
          mat=Matrix.Translation((sx * 0.012, 0, 0.05)) @ Matrix.Rotation(math.radians(-24 * sx), 4, "Y"))
    for y in (-0.06, 0.06):
        a.sphere("Root", (sx * 0.06, y, 0.055), (0.012, 0.012, 0.01), "chrome", "chrome", seg=(8, 4))


def build():
    a = world_kit.WorldAsset(KEY, PALETTE, tex=512, texel_m=0.0015, paint={"edge": 0.75, "grit": 0.04})
    x = 0.0

    def nxt():
        nonlocal x
        x += 1.5
        return (x, 0, 0)
    with a.piece("plate_l", apart=nxt()):
        plate(a, -1)
    with a.piece("plate_r", apart=nxt()):
        plate(a, 1)
    with a.piece("crest", apart=nxt()):
        a.box("Root", (0, -0.02, 0.04), (0.035, 0.24, 0.09), "trim", "chrome", bevel=0.35, taper=(0.6, 0.5))
        a.box("Root", (0, -0.02, 0.09), (0.02, 0.2, 0.02), "team", "team_emit", bevel=0.3)
        for y in (-0.08, 0.04):
            a.sphere("Root", (0.0, y, 0.0), (0.03, 0.03, 0.02), "chrome", "chrome", seg=(10, 5))
    with a.piece("crown", apart=nxt()):
        for k in range(3):
            ang = math.radians(-32 + 32 * k)
            base = Vector((math.sin(ang) * 0.08, -0.01, 0.0))
            tilt = Matrix.Rotation(-ang * 0.7, 3, "Y")
            a.cyl("Root", base, base + tilt @ Vector((0, 0, 0.04)), 0.028, 0.02, "chrome", "chrome", seg=8)
            a.cyl("Root", base + tilt @ Vector((0, 0, 0.02)), base + tilt @ Vector((0, 0, 0.15 if k == 1 else 0.11)),
                  0.026, 0.0, "team", "team_emit", seg=6)
        a.torus("Root", (0, -0.01, 0.0), (0, 0, 1), 0.1, 0.012, "trim", "chrome", seg=(20, 4))
    for name, own in (("sash", False), ("sash_own", True)):
        with a.piece(name, apart=nxt()):
            m = Matrix.Rotation(math.radians(-28), 4, "Y")
            a.torus("Root", m @ Vector((0, 0, 0)), m.to_3x3() @ Vector((0, 0, 1)), 0.2, 0.024, "team", "team", seg=(26, 4))
            a.box("Root", (0.12, 0.16, -0.08), (0.05, 0.015, 0.14), "team", "team", bevel=0.3)
            a.box("Root", (0.125, 0.17, -0.08), (0.012, 0.01, 0.1), "neon", "team_emit", bevel=0.3)
            if own:
                a.sphere("Root", (-0.13, 0.15, 0.06), (0.035, 0.03, 0.035), "gold_glow", "emit", seg=(10, 6))
    with a.piece("ring_own", apart=nxt()):
        a.torus("Root", (0, 0, 0.01), (0, 0, 1), 0.55, 0.02, "team", "team_emit", seg=(40, 3))
    with a.piece("pennant", apart=nxt()):
        a.cyl("Root", (0, 0, 0), (0, 0, 0.62), 0.012, 0.01, "chrome", "chrome", seg=6)
        a.sphere("Root", (0, 0, 0.63), (0.02, 0.02, 0.02), "trim", "chrome", seg=(8, 4))
        flag = Matrix.Translation((0.0, -0.12, 0.5))
        a.box("Root", None, (0.015, 0.24, 0.16), "team", "team", bevel=0.2, mat=flag)
        a.box("Root", None, (0.02, 0.07, 0.07), "trim", "chrome", bevel=0.3,
              mat=flag @ Matrix.Rotation(math.radians(45), 4, "X"))
    with a.piece("elite", apart=nxt()):
        a.torus("Root", (0, 0, 0.0), (0, 0, 1), 0.12, 0.008, "gold_glow", "emit", seg=(24, 4))
        a.box("Root", (0, 0, 0.09), (0.014, 0.014, 0.14), "chrome", "chrome", bevel=0.3)
        a.sphere("Root", (0, 0, 0.19), (0.025, 0.025, 0.05), "gold_glow", "emit", seg=(8, 6))
    a.lap("parts")
    a.finish(bevel_m=0.0)
    dst = world_kit.out_dir(KEY)
    sizes = a.bake(dst) if "--notex" not in sys.argv else {}
    a.export(dst, sizes)


if __name__ == "__main__":
    build()
