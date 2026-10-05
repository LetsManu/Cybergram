"""W16-HERO-B hero definitions (Liora Vale, Sable, Juniper Quill) for the gen pipeline.

Copied from Vesper's entry in hero_defs_gen.py (the reference hero); every key is
described in tools/art/README-hero-pipeline.md. Registered in hero_defs.py.
Space: Blender metres, X = character right, Y = forward, Z = up, feet at Z = 0.
Masks and helmets are the focal point (owner, W16): sculpted plates, layered lens
rims, vents and rivets, plus painted wear and markings (mask_paint.py) and an
emissive lens or slit.
"""
import math

import numpy as np
from mathutils import Matrix, Vector

import hero_defs
from hero_defs import TEAM, _along, _rx, _wz


# ---------------------------------------------------------------- shared helpers
class Shell:
    """An ellipsoid head shell (helmet, mask): points and normals on its surface."""

    def __init__(self, c, r):
        self.c, self.r = Vector(c), Vector(r)

    def on(self, x, z, out=0.003, back=False):
        c, r = self.c, self.r
        q = 1.0 - ((x - c.x) / r.x) ** 2 - ((z - c.z) / r.z) ** 2
        y = c.y + (-1.0 if back else 1.0) * r.y * math.sqrt(max(q, 0.0))
        n = Vector(((x - c.x) / r.x ** 2, (y - c.y) / r.y ** 2, (z - c.z) / r.z ** 2)).normalized()
        return Vector((x, y, z)) + n * out, n

    def zn(self, z):
        """Normalised (unit sphere) height of world z, for sphere() clip planes."""
        return (z - self.c.z) / self.r.z


def yaw(n):
    return -math.degrees(math.atan2(n.x, n.y))


def pitch(n):
    return math.degrees(math.atan2(n.z, math.hypot(n.x, n.y)))


def band(h, sh, scale, color, ch="flat", z0=-2.0, z1=2.0, y0=None, x_abs=None, seg=(24, 16), bone="Head", back=None):
    """A slab of a scaled copy of the shell: rims, visors, crests (unit-space clip planes)."""
    clip = [((0, 0, z1), (0, 0, 1)), ((0, 0, z0), (0, 0, -1))]
    if y0 is not None:
        clip.append(((0, y0, 0), (0, -1, 0)))
    if back is not None:
        clip.append(((0, back, 0), (0, 1, 0)))
    if x_abs is not None:
        clip += [((x_abs, 0, 0), (1, 0, 0)), ((-x_abs, 0, 0), (-1, 0, 0))]
    h.sphere(bone, sh.c, Vector((sh.r.x * scale, sh.r.y * scale, sh.r.z * scale)), color, ch, seg=seg, clip=clip)


def boots(h, k, sole, cuff, toe=None):
    import hero_hd
    skin = hero_hd.BodySkin(h)
    for s in ("L", "R"):
        blo, bhi = h.bbox("Foot_" + s, 0.4)
        c = (blo + bhi) / 2
        sz = bhi - blo
        h.box("Foot_" + s, (c.x, c.y + 0.006, 0.012 * k), (sz.x + 0.022, sz.y + 0.03, 0.03 * k), sole, bevel=0.35)
        if toe:
            h.box("Foot_" + s, (c.x, bhi.y - 0.03 * k, 0.04 * k), (sz.x * 0.85, 0.05 * k, 0.045 * k), toe, bevel=0.4)
        ax = (h.jt("LowerLeg_" + s) - h.jh("LowerLeg_" + s)).normalized()
        ring = hero_hd.ring(h, h.jl("LowerLeg_" + s, 0.32), ax, ("LowerLeg_" + s,), n=20, off=0.006, reach=0.3)
        hero_hd.strap(h, ring, ax, 0.035 * k, 0.012, cuff, skin)


def _cuts(h, belt_dz=0.02, fore=(0.70, 0.80), boot=0.30):
    cuts = []
    for s in ("L", "R"):
        for t in fore:
            cuts.append(({"LowerArm_" + s, "Hand_" + s}, *h.cut("LowerArm_" + s, t)))
        cuts.append(({"LowerLeg_" + s, "Foot_" + s, "UpperLeg_" + s}, *h.cut("LowerLeg_" + s, boot)))
    cuts.append(({"Neck", "Head", "UpperChest"}, *h.cut("Neck", 0.2)))
    zw = h.jh("Spine").z + belt_dz
    for dz in (-0.035, 0.035):
        cuts.append(({"Hips", "Spine", "Chest"}, Vector((0, 0, zw + dz)), Vector((0, 0, 1))))
    h.waist_z = zw
    return cuts


def _head(h):
    lo, hi = h.bbox("Head")
    hc = (lo + hi) / 2
    hr = (hi - lo) / 2
    eye_z = (h.eye("L").z + h.eye("R").z) / 2
    return lo, hi, hc, hr, eye_z


# ======================================================================== Liora Vale
def liora_cuts(h):
    return _cuts(h, belt_dz=0.03)


def liora_regions(h, c, bone, n):
    if bone in ("Head", "Neck") and h.side("Neck", 0.2, c) > 0:
        return "slate", "flat"
    if bone.startswith("Hand"):
        return "ink", "flat"
    if bone.startswith("LowerArm"):
        if h.side(bone, 0.80, c) > 0:
            return "ink", "flat"
        if h.side(bone, 0.70, c) > 0:
            return "sage", "flat"
        return "slate", "flat"
    if abs(c.z - h.waist_z) < 0.035 and bone in ("Hips", "Spine", "Chest"):
        return "sage", "flat"
    if bone.startswith("Foot") or (bone.startswith("LowerLeg") and h.side(bone, 0.30, c) > 0):
        return "ivory", "flat"
    return "slate", "flat"


def _liora_bodice(h, c, bone, n):
    if bone not in ("Chest", "UpperChest", "Clavicle_L", "Clavicle_R", "Spine", "Neck"):
        return False
    if bone == "Neck" and h.side("Neck", 0.2, c) > 0:
        return False
    return c.z > h.waist_z + 0.035


def _boot_pick(h, c, bone, n):
    return bone.startswith("Foot") or (bone.startswith("LowerLeg") and h.side(bone, 0.30, c) > 0)


def liora_parts(h):
    import hero_hd
    k = h.d["height"] / 1.85
    lo, hi, hc, hr, eye_z = _head(h)
    skin = hero_hd.BodySkin(h)
    # --- medic helmet: smooth ivory shell, sage crest stripe, wraparound visor in three layers
    # (chrome rim, ink socket, team-lit lens), lower face guard with vents and a filter disc,
    # ear discs with sage rings, brow cross, rivets. Painted: sheen, wear to bare metal,
    # side chevrons, scratches (liora_paint).
    sh = Shell((0, hc.y - 0.004, hc.z + 0.012), (hr.x * 1.22, hr.y * 1.16, hr.z * 1.12))
    h.sphere("Head", sh.c, sh.r, "ivory", seg=(24, 16), clip=[((0, 0, -0.62), (0, 0, -1))])
    ze = sh.zn(eye_z + 0.004)
    band(h, sh, 1.03, "sage", x_abs=0.15, z0=ze + 0.3, y0=-0.92)                       # crest stripe
    band(h, sh, 1.036, "chrome", "chrome", z0=ze - 0.24, z1=ze + 0.22, y0=0.05)          # visor rim
    band(h, sh, 1.05, "ink", z0=ze - 0.17, z1=ze + 0.15, y0=0.12)                       # socket
    band(h, sh, 1.064, "team", "team_emit", z0=ze - 0.085, z1=ze + 0.075, y0=0.24)     # lens
    band(h, sh, 1.045, "ivory", z0=-0.62, z1=ze - 0.3, y0=0.22)                         # face guard
    band(h, sh, 1.075, "ivory", z0=ze + 0.2, z1=ze + 0.34, y0=0.3)                      # brow peak
    band(h, sh, 1.05, "sage", z0=-0.66, z1=-0.56, y0=-1.0, seg=(24, 16))              # neck seal rim
    for sx in (-1, 1):
        for i in range(3):                                                             # guard vents
            z = eye_z - (0.045 + i * 0.014) * k
            p, n = sh.on(sx * 0.03 * k, z, 0.004 * k + sh.r.y * 0.045)
            h.box("Head", p, (0.026 * k, 0.006, 0.0055 * k), "ink", rot=(-pitch(n), sx * 10, yaw(n)), bevel=0.4)
        p, n = sh.on(sx * sh.r.x * 0.9, eye_z - 0.006 * k, 0.0)                         # ear disc
        ax = Vector((sx, 0, 0))
        h.cyl("Head", p - ax * 0.004, p + ax * 0.016 * k, 0.034 * k, 0.03 * k, "ivory", seg=16)
        h.torus("Head", p + ax * 0.012 * k, ax, 0.026 * k, 0.0045 * k, "sage", seg=(16, 5))
        h.cyl("Head", p + ax * 0.012 * k, p + ax * 0.022 * k, 0.014 * k, 0.01 * k, "chrome", "chrome", seg=10)
        for zz in (0.18, -0.18):                                                       # visor rivets
            p, n = sh.on(sx * sh.r.x * 0.86, sh.c.z + (ze + zz) * sh.r.z, sh.r.y * 0.04)
            h.sphere("Head", p, Vector((0.0055, 0.0055, 0.0055)) * k, "chrome", "chrome", seg=(8, 5))
    p, n = sh.on(0.0, eye_z - 0.072 * k, sh.r.y * 0.05)                                # filter disc
    h.cyl("Head", p - n * 0.004, p + n * 0.012 * k, 0.022 * k, 0.019 * k, "chrome", "chrome", seg=14)
    h.torus("Head", p + n * 0.012 * k, n, 0.017 * k, 0.004 * k, "sage", seg=(14, 5))
    for i in range(3):
        h.box("Head", p + n * 0.013 * k, (0.026 * k, 0.004, 0.0035 * k), "ink", rot=(-pitch(n), 0, 60 * i), bevel=0.2)
    p, n = sh.on(0.0, eye_z + 0.06 * k, 0.004)                                          # brow cross
    h.box("Head", p, (0.034 * k, 0.008, 0.011 * k), "sage", rot=(-pitch(n), 0, 0), bevel=0.35)
    h.box("Head", p, (0.011 * k, 0.008, 0.034 * k), "sage", rot=(-pitch(n), 0, 0), bevel=0.35)
    h.sphere("Head", p + n * 0.005, Vector((0.005, 0.004, 0.005)) * k, "team", "team_emit", seg=(8, 4))
    h.cyl("Head", sh.c + Vector((sh.r.x * 0.9, -0.01, 0.02)), sh.c + Vector((sh.r.x * 1.05, -0.05, 0.14)) * 1.0,
          0.004 * k, 0.003 * k, "chrome", "chrome", seg=6)                            # comm antenna
    # --- auburn ponytail out of the helmet's back, sage clasp.
    bands = [(hc.z, "Head"), (h.jh("Neck").z, "Neck"), (h.jh("UpperChest").z, "UpperChest"), (h.jh("Chest").z, "Chest")]
    prev, _n = sh.on(0.0, sh.c.z - sh.r.z * 0.15, 0.0, back=True)
    for i in range(6):
        p, n = h.surface(0.0, prev.z - 0.06 * k, -1)
        p = p + n * (0.035 - 0.003 * i) * k
        p.y = min(p.y, prev.y)
        h.sphere(None, (prev + p) / 2, Vector((0.034, 0.03, 0.05)) * k * (1.0 - i * 0.08),
                 "sage" if i == 1 else "hair", seg=(8, 6), weights=lambda co: _wz(h, co.z, bands))
        prev = p
    # --- shoulder pads (ivory, sage rims), medic belt with a team cross buckle, two kit pouches.
    for s, sg in (("L", -1), ("R", 1)):
        shp = h.jh("UpperArm_" + s) + Vector((sg * 0.012, 0, 0.035)) * k
        h.sphere("Clavicle_" + s, shp, Vector((0.068, 0.078, 0.05)) * k, "ivory", seg=(14, 8),
                 clip=[((0, 0, -0.25), (0, 0, -1))])
        h.sphere("Clavicle_" + s, shp + Vector((0, 0, -0.01)) * k, Vector((0.071, 0.081, 0.052)) * k, "sage",
                 seg=(14, 8), clip=[((0, 0, -0.25), (0, 0, -1)), ((0, 0, -0.05), (0, 0, 1))])
        ax = (h.jt("LowerArm_" + s) - h.jh("LowerArm_" + s)).normalized()
        g = hero_hd.ring(h, h.jl("LowerArm_" + s, 0.75), ax, ("LowerArm_" + s, "Hand_" + s), n=20, off=0.008,
                         reach=0.3)
        hero_hd.strap(h, g, ax, 0.05 * k, 0.012, "ivory", skin)
        h.cyl("LowerArm_" + s, h.jl("LowerArm_" + s, 0.1) + Vector((0, 0, 0.03)) * k,
              h.jl("LowerArm_" + s, 0.68) + Vector((0, 0, 0.032)) * k, 0.006 * k, 0.006 * k, "team", "team_emit", seg=5)
    zb = h.waist_z
    pts = hero_hd.ring(h, Vector((0, h.jh("Hips").y, zb)), (0, 0, 1), ("Hips", "Spine", "Chest"), n=32, off=0.02)
    hero_hd.strap(h, pts, (0, 0, 1), 0.06 * k, 0.012, "sage", skin)
    p, d = max(pts, key=lambda pd: pd[1].y)
    M = hero_hd.frame(p + d * 0.012, d, Vector((0, 0, 1)))
    hero_hd.piece(h, M, (0, 0, 0.004), (0.075 * k, 0.07 * k, 0.012), "chrome", skin.fixed(p), "chrome", bevel=0.4)
    hero_hd.piece(h, M, (0, 0, 0.012), (0.045 * k, 0.014 * k, 0.006), "team", skin.fixed(p), "team_emit", bevel=0.3)
    hero_hd.piece(h, M, (0, 0, 0.012), (0.014 * k, 0.045 * k, 0.006), "team", skin.fixed(p), "team_emit", bevel=0.3)
    for ang in (28, -28):  # kit pouches in the coat's open front (never under the coat)
        a = math.radians(ang)
        pp = min(pts, key=lambda pd: abs(math.atan2(pd[0].x, pd[0].y - h.jh("Hips").y) - a))
        Mp = hero_hd.frame(pp[0] + pp[1] * 0.03, pp[1], Vector((0, 0, 1)))
        hero_hd.piece(h, Mp, (0, -0.03 * k, 0), (0.09 * k, 0.07 * k, 0.045 * k), "ivory", skin.fixed(pp[0]),
                      bevel=0.4)
        hero_hd.piece(h, Mp, (0, -0.03 * k, 0.024 * k), (0.03 * k, 0.01 * k, 0.006), "sage", skin.fixed(pp[0]),
                      bevel=0.2)
        hero_hd.piece(h, Mp, (0, -0.03 * k, 0.024 * k), (0.01 * k, 0.03 * k, 0.006), "sage", skin.fixed(pp[0]),
                      bevel=0.2)
    boots(h, k, "ink", "sage", toe="ivory")
    # --- the halo: chrome ring behind the shoulders (team-lit inner band, sage markers, three
    # spokes to a spine plate) with two docked medic drones.
    uc = h.jh("UpperChest")
    p, n = h.surface(0, uc.z + 0.04, -1)
    plate = p + Vector((0, -0.025, 0)) * k
    h.box("UpperChest", plate, Vector((0.08, 0.04, 0.2)) * k, "chrome", "chrome", bevel=0.35)
    h.box("UpperChest", plate + Vector((0, -0.022, 0)) * k, Vector((0.035, 0.01, 0.13)) * k, "sage", bevel=0.3)
    c = plate + Vector((0, -0.13, 0.07)) * k
    R = 0.3 * k
    h.torus("UpperChest", c, (0, 1, 0), R, 0.016 * k, "chrome", "chrome", seg=(36, 6))
    h.torus("UpperChest", c + Vector((0, 0.012, 0)) * k, (0, 1, 0), R, 0.0075 * k, "team", "team_emit", seg=(36, 4))
    for ang in (90, 210, 330):
        a = math.radians(ang)
        tip = c + Vector((math.cos(a), 0, math.sin(a))) * (R - 0.012 * k)
        h.cyl("UpperChest", plate + Vector((0, -0.02, 0.03 * math.sin(a))) * k, tip, 0.008 * k, 0.006 * k, "chrome",
              "chrome", seg=6)
    for ang in (0, 60, 120, 180, 240, 300):
        a = math.radians(ang + 30)
        q = c + Vector((math.cos(a), 0, math.sin(a))) * R
        h.box("UpperChest", q, Vector((0.016, 0.03, 0.03)) * k, "sage", rot=(0, -ang - 30, 0), bevel=0.3)
    for ang in (35, 145):
        a = math.radians(ang)
        d = c + Vector((math.cos(a) * R, -0.01 * k, math.sin(a) * R))
        h.sphere("UpperChest", d, Vector((0.05, 0.042, 0.038)) * k, "ivory", seg=(14, 8))
        h.torus("UpperChest", d, (0, 0, 1), 0.046 * k, 0.007 * k, "sage", seg=(16, 5))
        h.sphere("UpperChest", d + Vector((0, 0.036, -0.008)) * k, Vector((0.018, 0.012, 0.018)) * k, "team",
                 "team_emit", seg=(10, 5))
        for sx in (-1, 1):
            h.box("UpperChest", d + Vector((sx * 0.055, 0, 0.004)) * k, Vector((0.03, 0.022, 0.006)) * k, "chrome",
                  "chrome", rot=(0, sx * 18, 0), bevel=0.3)


def mender(h, W):
    """Liora's Mender: a two-hand medic beam carbine. Ivory receiver with sage panels, a
    team-lit healing vial in a chrome cage, a chrome emitter with sage rings ending in a
    small halo ring, ink grip and foregrip. Weapon space: origin = right grip, +Y barrel,
    +Z up."""
    def wb(c, s, col, ch="flat", **kw):
        h.box("Weapon", None, s, col, ch, mat=W @ Matrix.Translation(Vector(c)) @ _rx(kw.pop("rx", 0)), **kw)

    def cyl(a, b, r0, r1, col, ch="flat", seg=10):
        h.cyl("Weapon", W @ Vector(a), W @ Vector(b), r0, r1, col, ch, seg=seg)

    def ring(c, R, r, col, ch="flat", seg=(14, 5)):
        h.torus("Weapon", W @ Vector(c), W.to_3x3() @ Vector((0, 1, 0)), R, r, col, ch, seg=seg)
    wb((0, -0.01, -0.05), (0.032, 0.045, 0.11), "ink", rx=-16, bevel=0.35)            # grip
    wb((0, 0.07, 0.03), (0.06, 0.3, 0.08), "ivory", bevel=0.45, taper=(0.8, 0.9))      # receiver
    for x in (-0.031, 0.031):
        wb((x, 0.08, 0.03), (0.004, 0.2, 0.045), "sage", bevel=0.2)                   # side panels
    wb((0, -0.15, 0.025), (0.05, 0.16, 0.07), "ivory", bevel=0.45, taper=(0.8, 0.7))   # stock
    wb((0, -0.235, 0.02), (0.056, 0.02, 0.085), "ink", bevel=0.4)                      # butt pad
    cyl((0, 0.02, 0.09), (0, 0.16, 0.09), 0.022, 0.022, "team", "team_emit", seg=10)  # healing vial
    for a in range(4):
        aa = math.pi / 4 + a * math.pi / 2
        wb((math.cos(aa) * 0.024, 0.09, 0.09 + math.sin(aa) * 0.024), (0.005, 0.15, 0.005), "chrome", "chrome",
           bevel=0.0)
    for y in (0.015, 0.165):
        cyl((0, y - 0.006, 0.09), (0, y + 0.006, 0.09), 0.028, 0.028, "chrome", "chrome", seg=12)
    cyl((0, 0.22, 0.035), (0, 0.5, 0.035), 0.02, 0.014, "chrome", "chrome", seg=10)    # emitter
    for y in (0.28, 0.35, 0.42):
        ring((0, y, 0.035), 0.022, 0.0055, "sage")
    ring((0, 0.53, 0.035), 0.036, 0.006, "chrome", "chrome", seg=(18, 5))             # muzzle halo
    ring((0, 0.53, 0.035), 0.036, 0.0025, "team", "team_emit", seg=(18, 4))
    cyl((0, 0.5, 0.035), (0, 0.54, 0.035), 0.01, 0.004, "team", "team_emit", seg=8)
    wb((0, 0.26, -0.03), (0.03, 0.04, 0.07), "ink", rx=8, bevel=0.35)                 # foregrip
    wb((0, 0.03, -0.012), (0.012, 0.06, 0.006), "ink", bevel=0.3)                      # trigger guard
    wb((0, 0.035, -0.02), (0.005, 0.008, 0.02), "chrome", "chrome", bevel=0.3)         # trigger


def liora_idle(p, ph, f):
    """Personal idle: calm medic, weight on the left leg, the right knee soft, a slow sway
    and an easy breath."""
    from hero_anims import legs
    w = math.sin(ph)
    b = math.sin(2 * ph)
    legs(p, 0, 0, 0)
    p.rot("UpperLeg_L", [("y", -2 + 0.8 * w), ("z", -3), ("x", -1)])
    p.rot("UpperLeg_R", [("y", 3 + 1.2 * w), ("z", 7), ("x", 6)])
    p.rot("LowerLeg_R", [("x", -10 - 2 * max(0.0, w))])
    p.rot("LowerLeg_L", [("x", -2)])
    p.rot("Foot_R", [("x", 4), ("z", 6)])
    p.rot("Hips", [("y", -4 - 1.0 * w), ("z", 5)])
    p.hips((-0.026 * p.k - 0.005 * w * p.k, 0, -0.006 * p.k))
    p.rot("Spine", [("y", 3 + 0.6 * w), ("x", -1 + 0.7 * b), ("z", -3)])
    p.rot("Chest", [("x", -3 + 0.6 * b), ("y", 1.5)])


def liora_paint(ctx):
    """Helmet paint: glossy ivory, wear to bare metal on the edges, scratches, sage chevrons
    on both sides with an ink edge, a thin team-coloured stripe under the visor."""
    import mask_paint as mp
    pal = HEROES["liora"]["palette"]
    zmin = 0.86 * 1.85 * ctx["k"]  # above the shoulder pads: the helmet only
    m = mp.Region(ctx, [pal["ivory"]], zmin=zmin)
    if len(m) == 0:
        return
    m.sheen(0.32)
    m.edge_wear(mp.rgb("#9CA7B5"), amount=0.8, freq=60.0, seed=21, spec=0.7)
    m.scratches(mp.rgb("#B9B2A2"), count=26, length=0.16, width=0.012, seed=22, strength=0.5)
    ink, sage = mp.rgb("#1A2230"), mp.rgb(pal["sage"])
    for sx in (-1, 1):
        s = mp.Region(ctx, [pal["ivory"]], zmin=zmin, proj="yz", xmin=sx * 0.03 * ctx["k"])
        if len(s) == 0:
            continue
        for dv in (0.0, -0.22):
            ch = [(0.55, 0.42 + dv), (0.2, 0.18 + dv), (0.55, -0.06 + dv)]
            s.paint(s.line(ch, 0.15), ink, noink=1.0)
            s.paint(s.line(ch, 0.09), sage, noink=1.0)
        s.paint(s.blob(-0.35, 0.3, 0.12, 0.12, sharp=0.2), ink, noink=1.0)          # stencil dot
        s.paint(s.blob(-0.35, 0.3, 0.08, 0.08, sharp=0.2), sage, noink=1.0)


# ============================================================================ Sable
def sable_cuts(h):
    return _cuts(h, belt_dz=0.0, fore=(0.72, 0.80), boot=0.34)


def sable_regions(h, c, bone, n):
    if bone in ("Head", "Neck") and h.side("Neck", 0.2, c) > 0:
        return "deep", "flat"
    if bone.startswith("Hand"):
        return "deep", "flat"
    if bone.startswith("LowerArm"):
        if h.side(bone, 0.80, c) > 0:
            return "deep", "flat"
        if h.side(bone, 0.72, c) > 0:
            return "jade", "flat"
    if abs(c.z - h.waist_z) < 0.035 and bone in ("Hips", "Spine", "Chest"):
        return "deep", "flat"
    if bone.startswith("Foot") or (bone.startswith("LowerLeg") and h.side(bone, 0.34, c) > 0):
        return "deep", "flat"
    return "charcoal", "flat"


def _sable_boot(h, c, bone, n):
    return bone.startswith("Foot") or (bone.startswith("LowerLeg") and h.side(bone, 0.34, c) > 0)


def sable_parts(h):
    import hero_hd
    k = h.d["height"] / 1.85
    lo, hi, hc, hr, eye_z = _head(h)
    skin = hero_hd.BodySkin(h)
    # --- slit mask (light steel, the one light block in her upper third): forehead plate,
    # angled cheek plates with vents, a nose ridge, a chin plate, a recessed ink socket with a
    # thin team-lit slit, chrome rivets. Painted (sable_paint): jade claw marks, edge wear.
    sh = Shell((0, hc.y + hr.y * 0.2, hc.z - 0.016), (hr.x * 1.03, hr.y * 0.96, hr.z * 1.0))
    h.sphere("Head", sh.c, sh.r, "mask", seg=(24, 16), clip=[((0, -0.1, 0), (0, -1, 0))])
    ze = sh.zn(eye_z + 0.002)
    band(h, sh, 1.035, "mask", z0=ze + 0.2, z1=0.92, y0=0.15)                          # forehead plate
    for sx in (-1, 1):                                                                # cheek plates
        h.sphere("Head", sh.c, sh.r * 1.04, "mask", seg=(24, 16),
                 clip=[((0, 0.1, 0), (0, -1, 0)), ((0, 0, ze - 0.17), (0, 0, 1)), ((0, 0, -0.78), (0, 0, -1)),
                       ((sx * 0.14, 0, 0), (-sx, 0, 0))])
        for i in range(4):                                                            # plate seam
            x = sx * (0.014 + 0.012 * i) * k
            p, n = sh.on(x, sh.c.z + (ze - 0.17) * sh.r.z, sh.r.y * 0.042)
            h.box("Head", p, (0.013 * k, 0.005, 0.0028 * k), "deep", rot=(-pitch(n), 0, yaw(n)), bevel=0.2)
        for i in range(3):
            p, n = sh.on(sx * (0.032 + 0.008 * i) * k, eye_z - (0.035 + 0.012 * i) * k, sh.r.y * 0.045)
            h.box("Head", p, (0.02 * k, 0.006, 0.004 * k), "deep", rot=(-pitch(n), sx * 35, yaw(n)), bevel=0.4)
        for z in (eye_z + 0.024 * k, eye_z - 0.075 * k):
            p, n = sh.on(sx * 0.052 * k, z, sh.r.y * 0.04)
            h.sphere("Head", p, Vector((0.0045, 0.0045, 0.0045)) * k, "chrome", "chrome", seg=(8, 5))
    p, n = sh.on(0.0, eye_z - 0.03 * k, sh.r.y * 0.04)                                 # nose ridge
    h.box("Head", p, (0.016 * k, 0.012, 0.05 * k), "mask", rot=(-pitch(n) * 0.5, 0, 0), bevel=0.45,
          taper=(0.6, 1.0))
    band(h, sh, 1.045, "mask", z0=-0.95, z1=-0.62, y0=0.35, x_abs=0.24)               # chin plate
    band(h, sh, 1.048, "deep", z0=ze - 0.1, z1=ze + 0.1, y0=0.12)                      # slit socket
    band(h, sh, 1.058, "team", "team_emit", z0=ze - 0.022, z1=ze + 0.022, y0=0.3)      # the slit
    # --- hood cowl over the mask (charcoal, deep lining, jade edge) with a drooping point.
    hcen = Vector((0, hc.y - 0.004, hc.z + 0.012))
    hood_r = Vector((hr.x * 1.42, hr.y * 1.34, hr.z * 1.26))
    cut = [((0, 0.62, -0.1), (0, 1, -0.3)), ((0, 0, -0.78), (0, 0, -1))]
    h.sphere("Head", hcen, hood_r, "charcoal", seg=(22, 14), clip=cut)
    h.sphere("Head", hcen, hood_r * 0.96, "deep", seg=(22, 14), clip=cut)
    h.sphere("Head", hcen, hood_r * 1.012, "jade", seg=(22, 14),
             clip=cut + [((0, 0.57, -0.1), (0, -1, 0.3))])                            # jade hood edge
    tip0 = hcen + Vector((0, -hood_r.y * 0.75, hood_r.z * 0.55))
    tip1 = hcen + Vector((0, -hood_r.y * 1.55, -hood_r.z * 0.2))
    h.cyl("Head", tip0, tip1, 0.045 * k, 0.006, "charcoal", seg=8)
    # --- harness: crossed straps, a steel sternum plate with the team stripe, one left pauldron.
    uc = h.jh("UpperChest")
    for sx in (-1, 1):
        a, _n = h.surface(sx * 0.11 * k, uc.z + 0.06 * k, 1)
        b, _n = h.surface(-sx * 0.08 * k, h.waist_z + 0.04, 1)
        h.box(None, None, ((a - b).length, 0.034 * k, 0.008), "deep", mat=_along(a, b, Vector((0, 1, 0))) @
              Matrix.Rotation(math.pi / 2, 4, "Z") @ Matrix.Translation((0, 0, 0.006)),
              weights=lambda co: _wz(h, co.z, [(uc.z, "UpperChest"), (h.jh("Chest").z, "Chest"),
                                               (h.waist_z, "Spine")]), bevel=0.2)
    p, n = h.surface(0, uc.z - 0.05 * k, 1)
    h.box("UpperChest", p + n * 0.022 * k, Vector((0.12, 0.024, 0.1)) * k, "mask", bevel=0.4, taper=(0.75, 1.0))
    h.box("UpperChest", p + n * 0.036 * k + Vector((0, 0, -0.025)) * k, Vector((0.09, 0.008, 0.012)) * k, "team",
          "team", bevel=0.0)
    shp = h.jh("UpperArm_L") + Vector((-0.012, 0, 0.03)) * k
    h.sphere("Clavicle_L", shp, Vector((0.07, 0.08, 0.05)) * k, "mask", seg=(12, 8), clip=[((0, 0, -0.2), (0, 0, -1))])
    for i in range(2):
        h.sphere("Clavicle_L", shp + Vector((-0.004, 0, -0.016 - 0.014 * i)) * k, Vector((0.073, 0.083, 0.05)) * k,
                 "charcoal" if i else "jade", seg=(12, 8), clip=[((0, 0, -0.2), (0, 0, -1)), ((0, 0, 0.1), (0, 0, 1))])
    # --- belt, left thigh holster with a knife, forearm blades, boots with calf struts.
    pts = hero_hd.ring(h, Vector((0, h.jh("Hips").y, h.waist_z)), (0, 0, 1), ("Hips", "Spine", "Chest"), n=32,
                       off=0.016)
    hero_hd.strap(h, pts, (0, 0, 1), 0.045 * k, 0.012, "deep", skin)
    p, d = max(pts, key=lambda pd: pd[1].y)
    M = hero_hd.frame(p + d * 0.012, d, Vector((0, 0, 1)))
    hero_hd.piece(h, M, (0, 0, 0.004), (0.06 * k, 0.05 * k, 0.012), "chrome", skin.fixed(p), "chrome", bevel=0.4)
    hero_hd.piece(h, M, (0, 0, 0.011), (0.03 * k, 0.012 * k, 0.005), "jade", skin.fixed(p), "emit", bevel=0.3)
    th = h.jl("UpperLeg_L", 0.45)
    ax = (h.jt("UpperLeg_L") - h.jh("UpperLeg_L")).normalized()
    r = hero_hd.ring(h, th, ax, ("UpperLeg_L",), n=20, off=0.006, reach=0.3)
    hero_hd.strap(h, r, ax, 0.035 * k, 0.01, "deep", skin)
    p, d = min(r, key=lambda pd: pd[1].x)
    h.box("UpperLeg_L", p + d * 0.02 * k, Vector((0.03, 0.06, 0.14)) * k, "deep", bevel=0.35)
    h.box("UpperLeg_L", p + d * 0.02 * k + Vector((0, 0, 0.09)) * k, Vector((0.02, 0.03, 0.05)) * k, "jade", bevel=0.3)
    for s, sg in (("L", -1), ("R", 1)):
        ax = (h.jt("LowerArm_" + s) - h.jh("LowerArm_" + s)).normalized()
        a, b = h.jl("LowerArm_" + s, 0.25), h.jl("LowerArm_" + s, 0.7)
        out = Vector((sg, 0, 0.6)).normalized()
        h.box("LowerArm_" + s, None, (0.012 * k, (b - a).length, 0.03 * k), "chrome", "chrome",
              mat=_along(a + out * 0.045 * k, b + out * 0.05 * k, out), bevel=0.2, taper=(1.0, 0.3))
        a, b = h.jl("LowerLeg_" + s, 0.15), h.jl("LowerLeg_" + s, 0.9)
        h.cyl("LowerLeg_" + s, a + Vector((0, -0.06, 0)) * k, b + Vector((0, -0.05, 0)) * k, 0.012 * k, 0.012 * k,
              "chrome", "chrome", seg=6)
        h.sphere("LowerLeg_" + s, b + Vector((0, -0.05, 0)) * k, Vector((0.016, 0.016, 0.016)) * k, "jade", "emit",
                 seg=(8, 4))
    boots(h, k, "deep", "jade")


def whisperfang(h, W):
    """Sable's Whisperfang: a compact suppressed carbine with an underslung blade. Slim
    charcoal receiver with a steel top rail, a long chrome suppressor with jade vents, a
    chrome fang blade under the barrel, a jade sight line, skeleton stock. Weapon space:
    origin = right grip, +Y barrel, +Z up."""
    def wb(c, s, col, ch="flat", **kw):
        h.box("Weapon", None, s, col, ch, mat=W @ Matrix.Translation(Vector(c)) @ _rx(kw.pop("rx", 0)), **kw)

    def cyl(a, b, r0, r1, col, ch="flat", seg=10):
        h.cyl("Weapon", W @ Vector(a), W @ Vector(b), r0, r1, col, ch, seg=seg)
    wb((0, -0.01, -0.045), (0.028, 0.04, 0.095), "deep", rx=-14, bevel=0.35)          # grip
    wb((0, 0.07, 0.03), (0.042, 0.22, 0.065), "charcoal", bevel=0.4, taper=(0.85, 1.0))
    wb((0, 0.07, 0.068), (0.022, 0.2, 0.012), "mask", bevel=0.3)                       # top rail
    wb((0, 0.13, -0.035), (0.026, 0.035, 0.075), "deep", rx=8, bevel=0.3)              # magazine
    cyl((0, 0.18, 0.035), (0, 0.42, 0.035), 0.022, 0.022, "chrome", "chrome", seg=12)  # suppressor
    for y in (0.24, 0.29, 0.34, 0.39):
        cyl((0, y, 0.035), (0, y + 0.012, 0.035), 0.0235, 0.0235, "jade", "emit", seg=12)
    cyl((0, 0.42, 0.035), (0, 0.43, 0.035), 0.02, 0.012, "deep", seg=12)
    wb((0, 0.3, -0.012), (0.005, 0.26, 0.03), "chrome", "chrome", taper=(1.0, 0.15), bevel=0.0, rx=-90)  # fang
    wb((0, 0.17, -0.01), (0.012, 0.04, 0.02), "deep", bevel=0.3)
    wb((0.023, 0.06, 0.03), (0.004, 0.12, 0.016), "team", "team_emit", bevel=0.0)    # sight line
    wb((0, 0.03, 0.09), (0.018, 0.06, 0.02), "jade", "emit", bevel=0.3)               # optic
    for z in (0.045, 0.0):                                                           # skeleton stock
        wb((0, -0.12, z), (0.012, 0.16, 0.012), "charcoal", bevel=0.3)
    wb((0, -0.2, 0.022), (0.03, 0.014, 0.07), "deep", bevel=0.35)
    wb((0, 0.03, -0.012), (0.012, 0.06, 0.006), "deep", bevel=0.3)
    wb((0, 0.035, -0.02), (0.005, 0.008, 0.02), "chrome", "chrome", bevel=0.3)


def sable_idle(p, ph, f):
    """Personal idle: low ready stance, knees bent, weight forward on the balls of the
    feet, a small predatory sway."""
    from hero_anims import legs
    w = math.sin(ph)
    b = math.sin(2 * ph)
    legs(p, 0, 0, 0, crouch=0.25)
    p.rot("UpperLeg_L", [("x", 24 + 1.0 * w), ("z", -6)])
    p.rot("UpperLeg_R", [("x", 12 - 1.0 * w), ("z", 7), ("y", 4)])
    p.rot("LowerLeg_L", [("x", -38)])
    p.rot("LowerLeg_R", [("x", -30)])
    p.rot("Foot_L", [("x", 10)])
    p.rot("Foot_R", [("x", 14)])
    p.rot("Hips", [("y", 2 * w), ("z", -10), ("x", -8)])
    p.hips((0.006 * w * p.k, 0.0, -0.045 * p.k + 0.004 * b * p.k))
    p.rot("Spine", [("x", -3 + 0.6 * b), ("y", -1.5 * w), ("z", 6)])
    p.rot("Chest", [("x", -2 + 0.5 * b), ("z", 3)])


def sable_paint(ctx):
    """Mask paint: matte steel with a faint sheen, bright edge wear, scratches, three jade
    claw marks across the right cheek and a jade glyph on the forehead (ink edged)."""
    import mask_paint as mp
    pal = HEROES["sable"]["palette"]
    m = mp.Region(ctx, [pal["mask"]], zmin=0.85 * 1.85 * ctx["k"], front=-0.1)
    if len(m) == 0:
        return
    m.sheen(0.14)
    m.edge_wear(mp.rgb("#E8EEF8"), amount=0.9, freq=70.0, seed=31, spec=0.5)
    m.scratches(mp.rgb("#8D97AB"), count=34, length=0.14, width=0.01, seed=32, strength=0.55)
    ink, jade = mp.rgb("#141A28"), mp.rgb(pal["jade"])
    for i in range(3):
        cl = [(0.2 + i * 0.13, 0.05 - i * 0.04), (0.36 + i * 0.13, -0.32 - i * 0.04), (0.42 + i * 0.13, -0.55 - i * 0.04)]
        m.paint(m.line(cl, 0.075), ink, noink=1.0)
        m.paint(m.line(cl, 0.04), jade, noink=1.0)
    g = m.diamond(0.0, 0.62, 0.07, 0.1)
    m.paint(np.clip(m.diamond(0.0, 0.62, 0.11, 0.15) - 0.0, 0, 1), ink, noink=1.0)
    m.paint(g, jade, noink=1.0)


# ========================================================================== Juniper Quill
def juniper_cuts(h):
    return _cuts(h, belt_dz=0.0, fore=(0.62, 0.80), boot=0.42)


def juniper_regions(h, c, bone, n):
    if bone in ("Head", "Neck") and h.side("Neck", 0.2, c) > 0:
        return "rubber", "flat"
    if bone.startswith("Hand"):
        return "rubber", "flat"
    if bone.startswith("LowerArm"):
        if h.side(bone, 0.80, c) > 0:
            return "rubber", "flat"
        if h.side(bone, 0.62, c) > 0:
            return "mustard", "flat"
        return "olive", "flat"
    if bone.startswith("UpperArm") or bone.startswith("Clavicle"):
        return "olive", "flat"
    if abs(c.z - h.waist_z) < 0.035 and bone in ("Hips", "Spine", "Chest"):
        return "mustard", "flat"
    if bone.startswith("Foot") or (bone.startswith("LowerLeg") and h.side(bone, 0.42, c) > 0):
        return "rubber", "flat"
    if bone in ("Hips", "UpperLeg_L", "UpperLeg_R", "LowerLeg_L", "LowerLeg_R"):
        return "trousers", "flat"
    return "olive", "flat"


def _jun_vest(h, c, bone, n):
    if bone not in ("Chest", "UpperChest", "Spine"):
        return False
    return c.z > h.waist_z + 0.035


def _jun_boot(h, c, bone, n):
    return bone.startswith("Foot") or (bone.startswith("LowerLeg") and h.side(bone, 0.42, c) > 0)


def juniper_parts(h):
    import hero_hd
    k = h.d["height"] / 1.85
    lo, hi, hc, hr, eye_z = _head(h)
    skin = hero_hd.BodySkin(h)
    # --- trapper head: olive padded cap with ear flaps and a stitched brow band, big brass
    # goggles (rim, ink bezel, team-lit lens, hood visor, side screws) on a rubber strap,
    # a sculpted rubber rebreather snout with two mustard filter canisters and a hose.
    # Painted (juniper_paint): hazard stripes on the snout, scuffs, cap stitching, brass shine.
    cap = Shell((0, hc.y - 0.006, hc.z + 0.014), (hr.x * 1.2, hr.y * 1.16, hr.z * 1.1))
    h.sphere("Head", cap.c, cap.r, "olive", seg=(22, 14), clip=[((0, 0, -0.1), (0, 0, -1)),
                                                              ((0, 0.72, 0), (0, 1, 0.25))])
    face = Shell((0, hc.y + hr.y * 0.18, hc.z - 0.018), (hr.x * 1.04, hr.y * 0.96, hr.z * 1.0))
    h.sphere("Head", face.c, face.r, "rubber", seg=(20, 14), clip=[((0, -0.1, 0), (0, -1, 0))])
    band(h, cap, 1.03, "mustard", z0=-0.1, z1=0.06, y0=-1.0, seg=(22, 14))             # cap band
    for sx in (-1, 1):                                                                 # ear flaps
        c = cap.c + Vector((sx * cap.r.x * 0.92, -0.01, -cap.r.z * 0.35))
        h.box("Head", c, (0.022 * k, 0.07 * k, 0.09 * k), "olive", rot=(0, sx * 8, 0), bevel=0.45, taper=(1.0, 0.8))
        h.box("Head", c + Vector((sx * 0.012, 0, -0.03)) * k, (0.006 * k, 0.03 * k, 0.012 * k), "brass", bevel=0.3)
    zs = eye_z + 0.006 * k
    band(h, cap, 1.06, "rubber", z0=cap.zn(zs) - 0.1, z1=cap.zn(zs) + 0.1, y0=-1.0, seg=(22, 14))  # strap
    for sx in (-1, 1):
        g = Vector((sx * 0.036 * k, face.c.y + face.r.y * 0.86, zs))
        ax = Vector((sx * 0.22, 1, 0.04)).normalized()
        h.cyl("Head", g - ax * 0.012, g + ax * 0.026 * k, 0.03 * k, 0.028 * k, "brass", seg=16)        # rim
        h.torus("Head", g + ax * 0.026 * k, ax, 0.026 * k, 0.0055 * k, "brass", seg=(16, 5))
        h.cyl("Head", g + ax * 0.024 * k, g + ax * 0.03 * k, 0.022 * k, 0.022 * k, "ink", seg=14)      # bezel
        h.cyl("Head", g + ax * 0.029 * k, g + ax * 0.034 * k, 0.017 * k, 0.017 * k, "team", "team_emit",
              seg=14)                                                                               # lens
        hood = g + ax * 0.03 * k + Vector((0, 0, 0.022)) * k
        h.box("Head", hood, (0.05 * k, 0.022 * k, 0.006 * k), "brass", rot=(-14, 0, -sx * 12), bevel=0.35)
        for a in (40, 140, 220, 320):                                                 # rim screws
            aa = math.radians(a)
            sp = g + ax * 0.02 * k + Vector((math.cos(aa) * 0.031, 0, math.sin(aa) * 0.031)) * k
            h.sphere("Head", sp, Vector((0.004, 0.004, 0.004)) * k, "chrome", "chrome", seg=(6, 4))
        h.box("Head", Vector((sx * cap.r.x * 1.02, cap.c.y + 0.01, zs)), (0.012 * k, 0.024 * k, 0.03 * k), "brass",
              bevel=0.3)                                                               # strap buckle
    h.box("Head", Vector((0, face.c.y + face.r.y * 0.98, zs)), (0.018 * k, 0.012, 0.012 * k), "brass", bevel=0.4)
    # rebreather snout (two stacked tapered blocks) + filters + vent slots + hose
    sn = Vector((0, face.c.y + face.r.y * 0.82, eye_z - 0.058 * k))
    h.box("Head", sn, (0.07 * k, 0.05 * k, 0.06 * k), "rubber", rot=(-12, 0, 0), bevel=0.45, taper=(0.85, 0.85))
    h.box("Head", sn + Vector((0, 0.028, -0.006)) * k, (0.05 * k, 0.03 * k, 0.04 * k), "rubber", rot=(-12, 0, 0),
          bevel=0.45, taper=(0.8, 0.8))
    for i in range(3):
        h.box("Head", sn + Vector((0, 0.045, 0.004 - i * 0.011)) * k, (0.034 * k, 0.006, 0.004 * k), "ink",
              rot=(-12, 0, 0), bevel=0.2)
    for sx in (-1, 1):
        a = sn + Vector((sx * 0.03, 0.012, -0.012)) * k
        b = a + Vector((sx * 0.045, 0.028, -0.018)) * k
        h.cyl("Head", a, b, 0.021 * k, 0.021 * k, "mustard", seg=12)
        d = (b - a).normalized()
        h.cyl("Head", b - d * 0.004, b + d * 0.008 * k, 0.023 * k, 0.019 * k, "brass", seg=12)
        h.torus("Head", a.lerp(b, 0.45), d, 0.021 * k, 0.003 * k, "ink", seg=(12, 4))
        h.cyl("Head", b + d * 0.008 * k, b + d * 0.01 * k, 0.012 * k, 0.012 * k, "ink", seg=10)
    nk = h.jh("UpperChest")
    hose_a = sn + Vector((0.0, 0.0, -0.035)) * k
    hose_b, _n = h.surface(0.05 * k, nk.z + 0.02 * k, 1)
    hose_w = lambda co: _wz(h, co.z, [(hc.z, "Head"), (h.jh("Neck").z, "Neck"), (nk.z, "UpperChest")])
    prev = hose_a
    for i in range(1, 5):
        t = i / 4
        q = hose_a.lerp(hose_b + Vector((0, 0.03, 0)) * k, t) + Vector((0.02 * math.sin(t * math.pi), 0.03 * math.sin(
            t * math.pi), 0)) * k
        h.cyl(None, prev, q, 0.011 * k, 0.011 * k, "ink" if i % 2 else "rubber", seg=8, weights=hose_w)
        prev = q
    # --- messy bun with quill darts sticking out of the cap's back.
    bun = cap.c + Vector((0, -cap.r.y * 0.85, cap.r.z * 0.35))
    h.sphere("Head", bun, Vector((0.045, 0.04, 0.04)) * k, "hair", seg=(10, 6))
    for ang in (-35, 5, 40):
        a = math.radians(ang)
        h.cyl("Head", bun, bun + Vector((math.sin(a) * 0.11, -0.05, math.cos(a) * 0.11)) * k, 0.0035, 0.0015, "brass",
              seg=5)
    # --- giant tool-pack (the silhouette hook), harness straps, trap canister belt, boots.
    uc = h.jh("UpperChest")
    p, n = h.surface(0, uc.z - 0.05, -1)
    pc = p + Vector((0, -0.17, 0.1)) * k

    def pack_w(co):
        return {"UpperChest": 0.85, "Chest": 0.15}
    h.box(None, pc, Vector((0.4, 0.26, 0.6)) * k, "mustard", bevel=0.16, weights=pack_w)
    h.box(None, pc + Vector((0, -0.135, 0.06)) * k, Vector((0.3, 0.025, 0.22)) * k, "olive", bevel=0.25, weights=pack_w)
    h.box(None, pc + Vector((0, -0.15, 0.06)) * k, Vector((0.06, 0.02, 0.05)) * k, "brass", bevel=0.3, weights=pack_w)
    h.box(None, pc + Vector((0, 0, 0.31)) * k, Vector((0.42, 0.28, 0.035)) * k, "olive", bevel=0.3, weights=pack_w)
    for i, (x, z, col) in enumerate(((-0.12, -0.17, "team"), (0.1, -0.2, "bone"), (0.13, 0.22, "bone"))):
        h.box(None, pc + Vector((x, -0.132, z)) * k, Vector((0.07, 0.01, 0.05)) * k, col,
              "team" if col == "team" else "flat", bevel=0.0, weights=pack_w)
    h.cyl(None, pc + Vector((0.2, 0, 0.0)) * k, pc + Vector((0.26, 0, 0.0)) * k, 0.12 * k, 0.12 * k, "rubber",
          seg=16, weights=pack_w)
    h.cyl(None, pc + Vector((0.255, 0, 0.0)) * k, pc + Vector((0.27, 0, 0.0)) * k, 0.06 * k, 0.06 * k, "brass",
          seg=12, weights=pack_w)
    h.cyl(None, pc + Vector((0.268, 0, 0.0)) * k, pc + Vector((0.276, 0, 0.0)) * k, 0.03 * k, 0.03 * k, "team",
          "team_emit", seg=10, weights=pack_w)
    h.box(None, pc + Vector((-0.23, 0.0, 0.1)) * k, Vector((0.05, 0.08, 0.46)) * k, "olive", bevel=0.3, weights=pack_w)
    h.cyl(None, pc + Vector((-0.12, 0.05, 0.32)) * k, pc + Vector((-0.16, 0.08, 0.56)) * k, 0.006 * k, 0.003 * k,
          "chrome", "chrome", seg=6, weights=pack_w)                                    # antenna
    h.sphere(None, pc + Vector((-0.16, 0.08, 0.57)) * k, Vector((0.012, 0.012, 0.012)) * k, "team", "team_emit",
             seg=(8, 4), weights=pack_w)
    for sx in (-1, 1):
        a, b = h.surface(sx * 0.1 * k, uc.z + 0.08, 1)[0], h.surface(sx * 0.1 * k, h.waist_z + 0.05, 1)[0]
        h.box(None, None, ((a - b).length, 0.04 * k, 0.012 * k), "rubber", mat=_along(a, b, Vector((0, 1, 0))) @
              Matrix.Rotation(math.pi / 2, 4, "Z") @ Matrix.Translation((0, 0, 0.008)),
              weights=lambda co: _wz(h, co.z, [(uc.z, "UpperChest"), (h.waist_z, "Spine")]), bevel=0.2)
        h.box(None, a.lerp(b, 0.3) + Vector((0, 0.016, 0)), (0.03 * k, 0.012, 0.03 * k), "brass", bevel=0.3,
              weights=lambda co: _wz(h, co.z, [(uc.z, "UpperChest"), (h.waist_z, "Spine")]))
    pts = hero_hd.ring(h, Vector((0, h.jh("Hips").y, h.waist_z)), (0, 0, 1), ("Hips", "Spine", "Chest"), n=32,
                       off=0.018)
    hero_hd.strap(h, pts, (0, 0, 1), 0.05 * k, 0.012, "rubber", skin)
    for i, ang in enumerate((25, 50, -25, -50)):
        a = math.radians(ang)
        pp = min(pts, key=lambda pd: abs(math.atan2(pd[0].x, pd[0].y - h.jh("Hips").y) - a))
        c = pp[0] + pp[1] * 0.03 * k
        h.cyl("Hips", c - Vector((0, 0, 0.035)) * k, c + Vector((0, 0, 0.035)) * k, 0.021 * k, 0.021 * k, "olive",
              seg=10)
        h.cyl("Hips", c + Vector((0, 0, 0.035)) * k, c + Vector((0, 0, 0.047)) * k, 0.022 * k, 0.018 * k,
              ("team", "mustard", "bone", "team")[i], "team" if i in (0, 3) else "flat", seg=10)
    boots(h, k, "ink", "mustard", toe="rubber")
    for s in ("L", "R"):
        ax = (h.jt("LowerArm_" + s) - h.jh("LowerArm_" + s)).normalized()
        g = hero_hd.ring(h, h.jl("LowerArm_" + s, 0.88), ax, ("LowerArm_" + s, "Hand_" + s), n=20, off=0.008,
                         reach=0.3)
        hero_hd.strap(h, g, ax, 0.045 * k, 0.012, "brass", skin)


def tackhammer(h, W):
    """Juniper's Tackhammer: a two-hand staple launcher. Olive receiver over a wood stock, a
    brass drum magazine on the side, a rubber-wrapped barrel with a mustard muzzle brake,
    a team-lit tension line along the top, a crank on the drum. Weapon space: origin =
    right grip, +Y barrel, +Z up."""
    def wb(c, s, col, ch="flat", **kw):
        h.box("Weapon", None, s, col, ch, mat=W @ Matrix.Translation(Vector(c)) @ _rx(kw.pop("rx", 0)), **kw)

    def cyl(a, b, r0, r1, col, ch="flat", seg=10):
        h.cyl("Weapon", W @ Vector(a), W @ Vector(b), r0, r1, col, ch, seg=seg)
    wb((0, -0.01, -0.045), (0.03, 0.042, 0.1), "wood", rx=-15, bevel=0.35)            # grip
    wb((0, 0.08, 0.03), (0.055, 0.27, 0.075), "olive", bevel=0.35)                     # receiver
    wb((0, 0.08, 0.072), (0.03, 0.22, 0.012), "mustard", bevel=0.3)
    cyl((0, 0.21, 0.035), (0, 0.6, 0.035), 0.016, 0.016, "rubber", seg=10)             # barrel
    for y in (0.3, 0.4, 0.5):
        cyl((0, y, 0.035), (0, y + 0.02, 0.035), 0.019, 0.019, "ink", seg=10)
    cyl((0, 0.6, 0.035), (0, 0.66, 0.035), 0.026, 0.024, "mustard", seg=12)           # muzzle brake
    for z in (0.02, 0.05):
        wb((0, 0.63, z), (0.06, 0.012, 0.006), "ink", bevel=0.0)
    wb((0, 0.33, 0.0), (0.045, 0.2, 0.045), "wood", bevel=0.4)                         # handguard
    cyl((0.032, 0.08, 0.0), (0.075, 0.08, 0.0), 0.05, 0.05, "brass", seg=16)           # drum
    cyl((0.075, 0.08, 0.0), (0.08, 0.08, 0.0), 0.03, 0.03, "ink", seg=12)
    wb((0.088, 0.08, 0.025), (0.008, 0.012, 0.05), "chrome", "chrome", bevel=0.3)      # crank
    wb((0.088, 0.08, 0.05), (0.02, 0.012, 0.012), "rubber", bevel=0.3)
    h.cyl("Weapon", W @ Vector((0, 0.0, 0.085)), W @ Vector((0, 0.58, 0.055)), 0.003, 0.003, "team", "team_emit",
          seg=4, caps=False)
    wb((0, 0.0, 0.085), (0.02, 0.03, 0.03), "brass", bevel=0.3)
    wb((0, -0.17, 0.02), (0.045, 0.2, 0.08), "wood", bevel=0.35, taper=(0.9, 0.75))    # stock
    wb((0, -0.27, 0.02), (0.05, 0.02, 0.09), "rubber", bevel=0.4)
    wb((0, 0.03, -0.012), (0.012, 0.06, 0.006), "ink", bevel=0.3)
    wb((0, 0.035, -0.02), (0.005, 0.008, 0.02), "chrome", "chrome", bevel=0.3)


def juniper_idle(p, ph, f):
    """Personal idle: wide planted stance under the heavy pack, a bouncy weight shift from
    foot to foot and a forward lean (the pack pulls her shoulders back)."""
    from hero_anims import legs
    w = math.sin(ph)
    b = abs(math.sin(ph))
    legs(p, 0, 0, 0)
    p.rot("UpperLeg_L", [("y", 2 + 2 * w), ("z", -8), ("x", 6 + 2 * max(0.0, w))])
    p.rot("UpperLeg_R", [("y", -2 + 2 * w), ("z", 8), ("x", 6 + 2 * max(0.0, -w))])
    p.rot("LowerLeg_L", [("x", -12 - 4 * max(0.0, w))])
    p.rot("LowerLeg_R", [("x", -12 - 4 * max(0.0, -w))])
    p.rot("Foot_L", [("x", 6), ("z", -6)])
    p.rot("Foot_R", [("x", 6), ("z", 6)])
    p.rot("Hips", [("y", 3 * w), ("x", 4)])
    p.hips((0.02 * w * p.k, 0, -0.02 * p.k - 0.008 * b * p.k))
    p.rot("Spine", [("x", 5), ("y", -2 * w)])
    p.rot("Chest", [("x", 3 + 1.0 * b)])


def juniper_paint(ctx):
    """Head paint: worn rubber (lighter scuffs, edge wear), glossy brass goggles, mustard
    hazard stripes on the snout, white stitching on the cap band."""
    import mask_paint as mp
    pal = HEROES["juniper"]["palette"]
    zmin = 0.86 * 1.85 * ctx["k"]
    r = mp.Region(ctx, [pal["rubber"]], zmin=zmin, front=0.0)
    if len(r):
        r.edge_wear(mp.rgb("#8A7462"), amount=0.9, freq=60.0, seed=41)
        r.scratches(mp.rgb("#76624F"), count=30, length=0.14, width=0.014, seed=42, strength=0.6)
        hz = np.clip(np.sin((r.u * 0.9 + r.v) * 9.0) * 4.0, 0, 1) * (r.v < -0.35) * (np.abs(r.u) < 0.4)
        r.paint(hz, mp.rgb(pal["mustard"]), noink=1.0)
        r.sheen(0.08)
    b = mp.Region(ctx, [pal["brass"]], zmin=zmin)
    if len(b):
        b.sheen(0.6)
        b.scratches(mp.rgb("#F6D58A"), count=20, length=0.08, width=0.02, seed=43, strength=0.7)
    m = mp.Region(ctx, [pal["mustard"]], zmin=zmin + 0.06 * ctx["k"], proj="yz")
    if len(m):
        st = np.clip(np.sin(m.u * 46.0) * 3.0, 0, 1) * (np.abs(m.v) < 0.12)
        m.paint(st, mp.rgb(pal["bone"]), noink=1.0)
    o = mp.Region(ctx, [pal["olive"]], zmin=zmin)
    if len(o):
        o.edge_wear(mp.rgb("#A8B86A"), amount=0.7, freq=50.0, seed=44)
        o.scratches(mp.rgb("#5E7230"), count=18, length=0.2, width=0.015, seed=45, strength=0.5)


HEROES = {
    "liora": {
        "key": "liora",
        "pipeline": "gen",
        "legacy": hero_defs.HEROES["liora"],
        "height": 1.78,
        "body": {"leg": 0.97, "torso": 0.54, "shoulder_w": 0.37, "chest_w": 0.31, "chest_d": 0.21,
                 "waist_w": 0.215, "waist_d": 0.165, "hip_w": 0.33, "hip_d": 0.22, "hip_joint_w": 0.185,
                 "neck": 0.075, "neck_r": 0.05, "head_w": 0.15, "head_d": 0.185, "head_h": 0.215,
                 "arm_r": 0.048, "forearm_r": 0.046, "wrist_r": 0.033, "thigh_r": 0.085, "knee_r": 0.057,
                 "calf_r": 0.066, "ankle_r": 0.042, "hand": 1.28, "foot": 1.25, "boot_r": 1.25,
                 "deltoid": 0.8, "pecs": 0.0, "bust": 0.35, "glutes": 0.6, "calves": 0.55, "traps": 0.25,
                 "chest_lift": 0.014, "arm_angle": 50.0},
        "paint": {"hatch_density": 0.5, "hatch_threshold": -0.05, "shader": {"hatch_strength": 0.1},
                  "uv_head": 1.6, "detail": lambda ctx: liora_paint(ctx)},
        "palette": {"ivory": "#F2E8D0", "sage": "#45D38A", "slate": "#3E5F86", "chrome": "#C9D4E2",
                    "hair": "#C0602E", "ink": "#24334A", "team": TEAM, "eye": "#101014"},
        "cuts": liora_cuts,
        "regions": liora_regions,
        "shells": [
            {"pick": _liora_bodice, "offset": 0.016, "paint": ("ivory", "flat"), "rim": ("sage", "flat")},
            {"pick": _boot_pick, "offset": 0.014, "paint": ("ivory", "flat"), "rim": ("sage", "flat")},
        ],
        "parts": liora_parts,
        "weapon": "mender_w16",
        # Layered: a closed slate under-tunic (no leg gap at the front) under an open ivory
        # field coat with a split back. 4 x 2 + 6 x 2 = 20 cloth bones -> 41 total.
        "cloth": [
            {"part": "tunic", "kind": "skirt", "top": 0.06, "hem": 0.6, "offset": 0.012, "flare": 0.05,
             "clear": 0.02, "open_front": 0, "chains": [("F", 0), ("R", 90), ("B", 180), ("L", 270)],
             "bones": 2, "rows": 8, "col_deg": 12, "thick": 0.01, "convex": True,
             "colors": {"outer": "slate", "inner": "ink", "hem": "ivory", "trim": "ivory"}},
            {"part": "coat", "kind": "skirt", "top": 0.09, "hem": 0.36, "offset": 0.044, "flare": 0.15,
             "clear": 0.07, "open_front": 66, "slits": [(180, 0.55)],
             "chains": [("FR", 50), ("R", 95), ("BR", 140), ("BL", 220), ("L", 265), ("FL", 310)],
             "bones": 2, "rows": 10, "col_deg": 10, "thick": 0.014,
             "colors": {"outer": "ivory", "inner": "sage", "hem": "sage", "trim": "sage"}},
        ],
        "stance": {"grip_r": (0.10, 0.22, 1.2), "pivot": (0.14, 0.02, 1.4), "twist": -24, "clav_l": -8,
                   "pole_r": (1, -0.4, -1), "pole_l": (-0.6, -0.2, -1), "two_handed": True,
                   "grip_l": (0, 0.26, -0.01), "hand_r_y": (0, 0.55, -1), "hand_r_n": (-1, 0, 0),
                   "hand_l_y": (1, 0.25, 0.1), "hand_l_n": (0, 0, 1), "mag": (0, 0.09, 0.1),
                   "belt": (-0.2, 0.1, 1.0)},
        "idle": liora_idle,
        "gait": {"run_amp": 36, "lean": 7},
        "casts": [("thrust", []), ("raise", [("x", 6)]), ("plant", [("x", -10)]), ("raise", [("x", 12)])],
    },
}

HEROES["sable"] = {
    "key": "sable",
    "pipeline": "gen",
    "legacy": hero_defs.HEROES["sable"],
    "height": 1.70,
    "body": {"leg": 1.0, "torso": 0.52, "shoulder_w": 0.36, "chest_w": 0.29, "chest_d": 0.2,
             "waist_w": 0.2, "waist_d": 0.155, "hip_w": 0.3, "hip_d": 0.21, "hip_joint_w": 0.18,
             "neck": 0.08, "neck_r": 0.047, "head_w": 0.15, "head_d": 0.185, "head_h": 0.215,
             "arm_r": 0.045, "forearm_r": 0.044, "wrist_r": 0.031, "thigh_r": 0.08, "knee_r": 0.054,
             "calf_r": 0.064, "ankle_r": 0.04, "hand": 1.25, "foot": 1.2, "boot_r": 1.2,
             "deltoid": 0.8, "pecs": 0.0, "bust": 0.25, "glutes": 0.7, "calves": 0.7, "traps": 0.3,
             "chest_lean": 4.0, "arm_angle": 52.0},
    "paint": {"hatch_density": 0.45, "hatch_threshold": -0.08, "shader": {"hatch_strength": 0.1},
              "uv_head": 1.6, "detail": lambda ctx: sable_paint(ctx)},
    # Dark by design, readable by value: the bodysuit is a saturated mid-dark blue (never ink
    # black), the mask is the light block, jade and the team slit are the accents.
    "palette": {"charcoal": "#3C4C72", "deep": "#252F4A", "jade": "#34E3A2", "mask": "#C2CBDD",
                "chrome": "#C9D4E2", "team": TEAM, "eye": "#101014"},
    "cuts": sable_cuts,
    "regions": sable_regions,
    "shells": [{"pick": _sable_boot, "offset": 0.012, "paint": ("deep", "flat"), "rim": ("jade", "flat")}],
    "parts": sable_parts,
    "weapon": "whisperfang_w16",
    # Draped hood mantle over the shoulders (5 x 2) and a split scarf hanging down the back
    # to the knees (2 x 3): 16 cloth bones -> 37 total.
    "cloth": [
        {"part": "hood", "kind": "skirt", "parent": "UpperChest", "top": 0.52, "hem": 1.12, "offset": 0.035,
         "flare": 0.06, "clear": 0.04, "open_front": 210, "chains": [("R", 118), ("BR", 150), ("B", 180),
                                                                       ("BL", 210), ("L", 242)],
         "around": ("Spine", "Chest", "UpperChest", "Neck", "Clavicle_L", "Clavicle_R"),
         "bones": 2, "rows": 7, "col_deg": 9, "thick": 0.012,
         "colors": {"outer": "charcoal", "inner": "deep", "hem": "jade", "trim": "jade"}},
        {"part": "scarf", "kind": "skirt", "parent": "UpperChest", "top": 0.3, "hem": 0.5, "offset": 0.016,
         "flare": 0.07, "clear": 0.03, "open_front": 296, "slits": [(180, 0.9)],
         "chains": [("R", 164), ("L", 196)],
         "around": ("Hips", "Spine", "Chest", "UpperChest", "UpperLeg_L", "UpperLeg_R", "LowerLeg_L",
                    "LowerLeg_R"),
         "bones": 3, "rows": 12, "col_deg": 8, "thick": 0.01, "hem_rows": 1,
         "colors": {"outer": "charcoal", "inner": "jade", "hem": "jade", "trim": "jade"}},
    ],
    "stance": {"grip_r": (0.09, 0.24, 1.08), "pivot": (0.12, 0.04, 1.28), "twist": -22, "clav_l": -8,
               "pole_r": (1, -0.4, -1), "pole_l": (-0.6, -0.2, -1), "two_handed": True,
               "grip_l": (0, 0.16, -0.02), "hand_r_y": (0, 0.55, -1), "hand_r_n": (-1, 0, 0),
               "hand_l_y": (1, 0.25, 0.1), "hand_l_n": (0, 0, 1), "mag": (0, 0.13, -0.06),
               "belt": (-0.18, 0.1, 0.92)},
    "idle": sable_idle,
    "gait": {"run_amp": 42, "lean": 14},
    "casts": [("thrust", [("x", -10)]), ("sweep", [("z", 12)]), ("plant", [("x", -12)]), ("raise", [("x", 6)])],
}

HEROES["juniper"] = {
    "key": "juniper",
    "pipeline": "gen",
    "legacy": hero_defs.HEROES["juniper"],
    "height": 1.72,
    "body": {"leg": 0.9, "torso": 0.56, "shoulder_w": 0.4, "chest_w": 0.34, "chest_d": 0.23,
             "waist_w": 0.25, "waist_d": 0.185, "hip_w": 0.35, "hip_d": 0.235, "hip_joint_w": 0.2,
             "neck": 0.07, "neck_r": 0.053, "head_w": 0.16, "head_d": 0.19, "head_h": 0.22,
             "arm_r": 0.053, "forearm_r": 0.054, "wrist_r": 0.036, "thigh_r": 0.094, "knee_r": 0.064,
             "calf_r": 0.074, "ankle_r": 0.047, "hand": 1.4, "foot": 1.4, "boot_r": 1.35,
             "deltoid": 0.9, "pecs": 0.0, "bust": 0.3, "glutes": 0.6, "calves": 0.7, "forearms": 0.8,
             "traps": 0.4, "arm_angle": 46.0, "stance": 0.03},
    "paint": {"hatch_density": 0.5, "hatch_threshold": -0.05, "shader": {"hatch_strength": 0.1},
              "uv_head": 1.6, "detail": lambda ctx: juniper_paint(ctx)},
    "palette": {"mustard": "#F2B12A", "olive": "#7F9B38", "rubber": "#5A4636", "brass": "#D9A23E",
                "chrome": "#C9D4E2", "bone": "#F3E6C6", "hair": "#B5462A", "wood": "#8A5A34",
                "trousers": "#6E5640", "ink": "#2B2530", "team": TEAM, "eye": "#101014"},
    "cuts": juniper_cuts,
    "regions": juniper_regions,
    "shells": [
        {"pick": _jun_vest, "offset": 0.016, "paint": ("olive", "flat"), "rim": ("mustard", "flat")},
        {"pick": _jun_boot, "offset": 0.014, "paint": ("rubber", "flat"), "rim": ("mustard", "flat")},
    ],
    "parts": juniper_parts,
    "weapon": "tackhammer_w16",
    # Short olive work coat (open front, split back) under the pack: 6 x 2 = 12 cloth bones.
    "cloth": [{"part": "coat", "kind": "skirt", "top": 0.08, "hem": 0.5, "offset": 0.024, "flare": 0.1,
               "clear": 0.04, "open_front": 70, "slits": [(180, 0.6)],
               "chains": [("FR", 55), ("R", 100), ("BR", 145), ("BL", 215), ("L", 260), ("FL", 305)],
               "bones": 2, "rows": 8, "col_deg": 10, "thick": 0.014,
               "colors": {"outer": "olive", "inner": "trousers", "hem": "mustard", "trim": "mustard"}}],
    "stance": {"grip_r": (0.10, 0.22, 1.12), "pivot": (0.14, 0.02, 1.34), "twist": -24, "clav_l": -8,
               "pole_r": (1, -0.4, -1), "pole_l": (-0.6, -0.2, -1), "two_handed": True,
               "grip_l": (0, 0.32, -0.01), "hand_r_y": (0, 0.55, -1), "hand_r_n": (-1, 0, 0),
               "hand_l_y": (1, 0.25, 0.1), "hand_l_n": (0, 0, 1), "mag": (0.06, 0.08, 0.0),
               "belt": (-0.2, 0.12, 0.95)},
    "idle": juniper_idle,
    "gait": {"run_amp": 34, "lean": 9},
    "casts": [("plant", [("x", -12)]), ("throw", [("z", 10)]), ("plant", [("x", -10)]), ("raise", [("x", 8)])],
}

WEAPONS = {"mender_w16": mender, "whisperfang_w16": whisperfang, "tackhammer_w16": tackhammer}
