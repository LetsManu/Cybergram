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
    for ang in (100, -100):
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
             "bones": 2, "rows": 8, "col_deg": 12, "thick": 0.01,
             "colors": {"outer": "slate", "inner": "ink", "hem": "ivory", "trim": "ivory"}},
            {"part": "coat", "kind": "skirt", "top": 0.09, "hem": 0.36, "offset": 0.036, "flare": 0.15,
             "clear": 0.06, "open_front": 66, "slits": [(180, 0.55)],
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

WEAPONS = {"mender_w16": mender}
