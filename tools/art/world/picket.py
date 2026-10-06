#!/usr/bin/env python3
"""Picket Wardling on the hero pipeline (design brief: docs/assets/picket.md;
design/art-bible.md §5.3-5.4, §10.6: 4k tris, one 1024 atlas, faction swap).

A 0.9 m hover-biped toy soldier: rounded shell, single holo-LED visor eye, a
team mana core in a chrome cage (front and back), stubby arms with an emitter,
a back fin with tier pips, two short legs. Faction skins are two bakes of the
same geometry: `picket_c` (Concord: white porcelain + gold, printed serial) and
`picket_s` (Syndicate: black iron + brass rivets, sprayed crew tag).

Pieces (WardlingModel shows / swaps them; meshes are shared by every Wardling):
  body            shell, core, visor, arms, fin, tier I pip
  tier2, tier3    the tier's silhouette additions (tier3 includes tier2's)
  leg_l, leg_r    rebased to the hip, so the runtime swings them
  sash, sash_own  owner band (personal squad); _own adds the knot + ground ring
  pennant         Vanguard pole and flag + shoulder stripe
  elite           Vesper's Elite: gold threads + floating spindle

Blender space: Z up, front = +Y (Godot -Z), origin = between the feet.
Run:  /tmp/venv/bin/python tools/art/world/picket.py [--only picket_c|picket_s] [--notex] [--out <dir>]
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import world_kit  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

HIP = 0.25            # WardlingModel leg pivot height
HIP_X = 0.11
CORE_Z = 0.46

FACTIONS = {
    "picket_c": {"shell": "#F1ECE4", "shell_dark": "#C9C2B8", "trim": "#D6B25E", "gun": "#3B4052",
                 "ink": "#1B1E2E", "tag": "#6E7488", "chrome": "#C9D4E2", "neon": "#F4F7FF",
                 "gold_glow": "#FFD36B", "team": "#2E86FF"},
    "picket_s": {"shell": "#34323B", "shell_dark": "#24232A", "trim": "#B48A52", "gun": "#4C464C",
                 "ink": "#120E10", "tag": "#E2DACB", "chrome": "#D5C8B4", "neon": "#F4F7FF",
                 "gold_glow": "#FFD36B", "team": "#FF5A1F"},
}


def beam(a, p0, p1, w, d, color, ch="flat", out=None, bevel=0.3, taper=(1.0, 1.0)):
    p0, p1 = Vector(p0), Vector(p1)
    z = (p1 - p0).normalized()
    o = Vector(out) if out is not None else Vector((1, 0, 0))
    x = o - z * o.dot(z)
    x = x.normalized() if x.length > 1e-6 else Vector((1, 0, 0))
    m = Matrix((x, z.cross(x), z)).transposed().to_4x4()
    m.translation = (p0 + p1) / 2
    a.box("Root", None, (w, d, (p1 - p0).length), color, ch, bevel=bevel, taper=taper, mat=m)


def rx(deg):
    return Matrix.Rotation(math.radians(deg), 4, "X")


def body(a, syn):
    # shell: upper dome + lower bowl with a seam, back armour plate
    a.sphere("Root", (0, 0, 0.55), (0.27, 0.25, 0.29), "shell", seg=(16, 10), clip=[((0, 0, -0.18), (0, 0, -1))])
    a.sphere("Root", (0, 0, 0.5), (0.255, 0.235, 0.16), "shell_dark", seg=(16, 6), clip=[((0, 0, 0.05), (0, 0, 1))])
    a.torus("Root", (0, 0, 0.5), (0, 0, 1), 0.262, 0.016, "gun", seg=(20, 3))
    a.box("Root", None, (0.3, 0.05, 0.26), "shell_dark", bevel=0.4, mat=Matrix.Translation((0, -0.235, 0.58)) @ rx(12))
    for j in range(3):  # back vents
        a.box("Root", (0, -0.262, 0.53 + j * 0.05), (0.18, 0.02, 0.022), "gun", bevel=0.0)
    # waist ring (trim) with rivets (Syndicate) or a pinstripe (Concord)
    a.torus("Root", (0, 0, 0.4), (0, 0, 1), 0.248, 0.028, "trim", "chrome", seg=(20, 5))
    if syn:
        for k in range(10):
            ang = 2 * math.pi * (k + 0.5) / 10
            a.box("Root", (math.cos(ang) * 0.272, math.sin(ang) * 0.252, 0.4), (0.022, 0.022, 0.022), "trim", "chrome",
                  bevel=0.0, rot=(0, 0, math.degrees(ang)))
    else:
        a.torus("Root", (0, 0, 0.66), (0, 0, 1), 0.245, 0.007, "trim", "chrome", seg=(20, 3))
    # hip block and joint discs
    a.box("Root", (0, 0, 0.29), (0.3, 0.2, 0.1), "gun", bevel=0.4, taper=(0.85, 0.85))
    for s in (1, -1):
        a.cyl("Root", (s * 0.1, 0, HIP + 0.02), (s * 0.165, 0, HIP + 0.02), 0.055, 0.05, "trim", "chrome", seg=8)
    # visor band + single holo-LED eye, brass frame
    a.box("Root", None, (0.32, 0.07, 0.1), "ink", bevel=0.4, mat=Matrix.Translation((0, 0.205, 0.68)) @ rx(8))
    a.box("Root", None, (0.34, 0.05, 0.016), "trim", "chrome", bevel=0.3, mat=Matrix.Translation((0, 0.21, 0.735)) @ rx(8))
    a.sphere("Root", (0, 0.245, 0.68), (0.05, 0.022, 0.026), "neon", "emit", seg=(8, 5))
    for s in (1, -1):  # visor bolts
        a.cyl("Root", (s * 0.17, 0.17, 0.68), (s * 0.19, 0.17, 0.68), 0.022, 0.022, "chrome", "chrome", seg=8)
    # mana core front + back in chrome cages (the team signal)
    for s in (1, -1):
        y = s * 0.215
        a.sphere("Root", (0, y, CORE_Z), (0.07, 0.04, 0.07), "team", "team_emit", seg=(12, 8))
        a.torus("Root", (0, y + s * 0.012, CORE_Z), (0, 1, 0), 0.078, 0.013, "chrome", "chrome", seg=(12, 4))
        for k in (-1, 0, 1):
            a.box("Root", (k * 0.035, y + s * 0.035, CORE_Z), (0.011, 0.011, 0.14), "chrome", "chrome", bevel=0.0)
    # printed serial (Concord) / sprayed crew tag (Syndicate) on the right of the shell
    if syn:
        for k, (w, h) in enumerate(((0.07, 0.022), (0.04, 0.018), (0.06, 0.016))):
            a.box("Root", None, (w, 0.008, h), "tag", bevel=0.2,
                  mat=Matrix.Translation((0.15 + 0.01 * k, 0.17, 0.6 - k * 0.03)) @ Matrix.Rotation(math.radians(38), 4, "Z")
                  @ Matrix.Rotation(math.radians(k * 9 - 9), 4, "Y"))
    else:
        for k in range(4):
            a.box("Root", None, (0.016, 0.008, 0.024), "tag", bevel=0.2,
                  mat=Matrix.Translation((0.12 + k * 0.022, 0.19 - k * 0.008, 0.6)) @ Matrix.Rotation(math.radians(38), 4, "Z"))
    # shoulders: joint balls, stubby arms, gunmetal hands, emitter on the right
    for s in (1, -1):
        sh = Vector((s * 0.27, 0.0, 0.5))
        el = Vector((s * 0.31, 0.07, 0.37))
        a.sphere("Root", sh, (0.06, 0.06, 0.06), "trim", "chrome", seg=(10, 6))
        a.cyl("Root", sh, el, 0.05, 0.045, "shell", seg=8)
        a.sphere("Root", el + Vector((0, 0.01, -0.02)), (0.052, 0.052, 0.05), "gun", seg=(10, 6))
    a.cyl("Root", (0.31, 0.1, 0.35), (0.31, 0.2, 0.35), 0.024, 0.03, "chrome", "chrome", seg=8)
    a.cyl("Root", (0.31, 0.2, 0.35), (0.31, 0.215, 0.35), 0.02, 0.02, "team", "team_emit", seg=8)
    # back fin + tier I pip
    a.box("Root", None, (0.04, 0.2, 0.24), "shell", bevel=0.3, taper=(0.8, 0.4),
          mat=Matrix.Translation((0, -0.13, 0.8)) @ rx(-35))
    pip(a, 0)


def pip(a, k):
    a.box("Root", None, (0.046, 0.024, 0.024), "trim", "chrome", bevel=0.3,
          mat=Matrix.Translation((0, -0.25, 0.66 + k * 0.05)) @ rx(-35))


def tier2_parts(a):
    for s in (1, -1):  # shoulder armour plates
        a.box("Root", None, (0.17, 0.19, 0.06), "trim", "chrome", bevel=0.35,
              mat=Matrix.Translation((s * 0.27, 0.0, 0.6)) @ Matrix.Rotation(math.radians(-28 * s), 4, "Y"))
        a.box("Root", None, (0.12, 0.02, 0.02), "shell_dark", bevel=0.3,
              mat=Matrix.Translation((s * 0.28, 0.1, 0.6)) @ Matrix.Rotation(math.radians(-28 * s), 4, "Y"))
    a.box("Root", None, (0.05, 0.26, 0.12), "trim", "chrome", bevel=0.35, taper=(0.6, 0.5),
          mat=Matrix.Translation((0, 0.0, 0.86)))
    for s in (1, -1):  # outer core ring
        a.torus("Root", (0, s * 0.235, CORE_Z), (0, 1, 0), 0.1, 0.008, "team", "team_emit", seg=(16, 3))
    pip(a, 1)


def tier3_parts(a):
    tier2_parts(a)
    for k in range(3):  # crown: three crystal shards in chrome claws
        ang = math.radians(-35.0 + 35.0 * k)
        p = Vector((math.sin(ang) * 0.13, -0.01, 0.97 - abs(math.sin(ang)) * 0.05))
        tilt = Matrix.Rotation(-ang * 0.6, 4, "Y")
        a.cyl("Root", p + Vector((0, 0, -0.08)), p + Vector((0, 0, -0.03)), 0.034, 0.024, "chrome", "chrome", seg=6)
        tip = p + (tilt @ Vector((0, 0, 0.09)))
        a.cyl("Root", p - (tilt @ Vector((0, 0, 0.03))), tip, 0.03, 0.0, "team", "team_emit", seg=6)
    beam(a, (0, -0.27, 0.72), (0, -0.4, 0.5), 0.05, 0.01, "team", "team_emit", out=(1, 0, 0))  # mana ribbon
    pip(a, 2)


def leg(a, s):
    hip = Vector((s * HIP_X, 0, HIP))
    a.sphere("Root", hip, (0.05, 0.05, 0.05), "gun", seg=(10, 6))
    a.cyl("Root", hip, hip + Vector((0, 0.01, -0.15)), 0.06, 0.05, "shell", seg=10)
    a.box("Root", hip + Vector((0, 0.03, -0.2)), (0.12, 0.17, 0.06), "gun", bevel=0.4, taper=(0.9, 0.85))
    a.box("Root", hip + Vector((0, 0.1, -0.19)), (0.1, 0.03, 0.045), "trim", "chrome", bevel=0.4)
    a.box("Root", hip + Vector((0, 0.03, -0.236)), (0.09, 0.12, 0.012), "neon", "emit", bevel=0.3)  # hover pad


def sash(a, own):
    m = Matrix.Translation((0, 0, 0.42)) @ Matrix.Rotation(math.radians(-18), 4, "Y") @ Matrix.Diagonal((1.0, 0.92, 1.4, 1)).to_4x4()
    c = m @ Vector((0, 0, 0))
    a.torus("Root", c, (0, 0, 1), 0.285, 0.022, "team", "team", seg=(26, 4))
    a.box("Root", (0.2, 0.2, 0.32), (0.06, 0.02, 0.16), "team", "team", bevel=0.3)
    a.box("Root", (0.21, 0.21, 0.32), (0.015, 0.01, 0.12), "neon", "team_emit", bevel=0.3)
    if own:  # owner-only: gold knot + ground ring
        a.sphere("Root", (-0.25, 0.16, 0.36), (0.04, 0.04, 0.04), "gold_glow", "emit", seg=(8, 6))
        a.torus("Root", (0, 0, 0.012), (0, 0, 1), 0.53, 0.025, "team", "team_emit", seg=(32, 3))


def pennant(a):
    a.cyl("Root", (0.0, -0.24, 0.52), (0.0, -0.24, 1.38), 0.013, 0.011, "chrome", "chrome", seg=6)
    a.sphere("Root", (0.0, -0.24, 1.39), (0.022, 0.022, 0.022), "trim", "chrome", seg=(8, 4))
    flag = Matrix.Translation((0.1, -0.36, 1.2)) @ Matrix.Rotation(math.radians(40), 4, "Z")
    a.box("Root", None, (0.02, 0.34, 0.24), "team", "team", bevel=0.2, mat=flag)
    a.box("Root", None, (0.026, 0.11, 0.11), "trim", "chrome", bevel=0.3, mat=flag @ rx(45))  # faction glyph
    a.box("Root", None, (0.05, 0.25, 0.05), "team", "team", bevel=0.3,
          mat=Matrix.Translation((0.26, 0.0, 0.63)) @ Matrix.Rotation(math.radians(20), 4, "Y"))  # shoulder stripe


def elite(a):
    for k in range(3):
        a.torus("Root", (0, 0, 0.42 + k * 0.13), (0, 0, 1), 0.275 - k * 0.03, 0.006, "gold_glow", "emit", seg=(22, 3))
    a.box("Root", (0, 0, 1.12), (0.02, 0.02, 0.24), "chrome", "chrome", bevel=0.3)
    a.cyl("Root", (0, 0, 0.99), (0, 0, 1.01), 0.03, 0.03, "trim", "chrome", seg=8)
    a.sphere("Root", (0, 0, 1.27), (0.032, 0.032, 0.064), "gold_glow", "emit", seg=(8, 6))


def build(key):
    syn = key == "picket_s"
    a = world_kit.WorldAsset(key, FACTIONS[key], tex=1024, texel_m=0.0012, paint={"edge": 0.75, "grit": 0.03 if not syn else 0.08})
    with a.piece("body"):
        body(a, syn)
    with a.piece("tier2", apart=(2, 0, 0)):
        tier2_parts(a)
    with a.piece("tier3", apart=(4, 0, 0)):
        tier3_parts(a)
    for s, n in ((1, "leg_r"), (-1, "leg_l")):
        with a.piece(n):
            leg(a, s)
    with a.piece("sash", apart=(6, 0, 0)):
        sash(a, False)
    with a.piece("sash_own", apart=(8, 0, 0)):
        sash(a, True)
    with a.piece("pennant", apart=(10, 0, 0)):
        pennant(a)
    with a.piece("elite", apart=(12, 0, 0)):
        elite(a)
    a.lap("parts")
    a.finish(bevel_m=0.0, smooth_deg=45)
    dst = world_kit.out_dir(key)
    sizes = a.bake(dst) if "--notex" not in sys.argv else {}
    a.export(dst, sizes, rebase={"leg_r": (HIP_X, 0, HIP), "leg_l": (-HIP_X, 0, HIP)})


if __name__ == "__main__":
    keys = [sys.argv[sys.argv.index("--only") + 1]] if "--only" in sys.argv else list(FACTIONS)
    for k in keys:
        build(k)
