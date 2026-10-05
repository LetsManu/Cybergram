"""W16 gen-pipeline heroes, chunk A: Ryker Vance, Brannoc, Hex (hero_gen.py, `"pipeline": "gen"`).

Copied from Vesper's entry in hero_defs_gen.py (pipeline settings, sparse shadow-only
hatching, shader hatch turned down). New for these three: the mask / helmet is the
focal point (heroes never show a face), so each head gets
  * sculpted forms: layered rims, ridges, plates, vents, bolts (geometry),
  * painted detail: edge wear, scratches, stencils (hero_decals via `paint.post`),
  * glossy versus matte areas (mask G) and glowing lenses (emissive).
Space: Blender metres, X = character right, Y = forward, Z = up, feet at Z = 0.
"""
import math

from mathutils import Matrix, Vector

import hero_defs
from hero_defs import TEAM, _along, _rx, _wz, ryker_cuts, ryker_regions


# ======================================================================== helpers
def _k(h):
    return h.d["height"] / 1.85


def _head(h):
    lo, hi = h.bbox("Head")
    return lo, hi, (lo + hi) / 2, (hi - lo) / 2, (h.eye("L").z + h.eye("R").z) / 2


def _band(h, bone, C, R, col, ch="flat", seg=(28, 16), z=None, y=None, x=None, rot=(0, 0, 0)):
    """Part of the ellipsoid (C, R): kept between unit-space limits z=(lo, hi), y=(lo, hi), x=(lo, hi)."""
    clip = []
    for i, lim in enumerate((x, y, z)):
        if lim is None:
            continue
        lo, hi = lim
        ax = [0, 0, 0]
        if hi is not None:
            ax[i] = 1
            co = [0, 0, 0]
            co[i] = hi
            clip.append((tuple(co), tuple(ax)))
        if lo is not None:
            ax = [0, 0, 0]
            ax[i] = -1
            co = [0, 0, 0]
            co[i] = lo
            clip.append((tuple(co), tuple(ax)))
    h.sphere(bone, C, R, col, ch, seg=seg, clip=clip, rot=rot)


def _on(C, R, x, z, out=0.0, back=False):
    """Point + normal on the ellipsoid surface (front, or back) at (x, z)."""
    q = 1.0 - ((x - C.x) / R.x) ** 2 - ((z - C.z) / R.z) ** 2
    y = C.y + (-1 if back else 1) * R.y * math.sqrt(max(q, 0.0))
    n = Vector(((x - C.x) / R.x ** 2, (y - C.y) / R.y ** 2, (z - C.z) / R.z ** 2)).normalized()
    return Vector((x, y, z)) + n * out, n


def _side(C, R, s, y, z, out=0.0):
    """Point + normal on the ellipsoid side (s = +1 right / -1 left) at (y, z)."""
    q = 1.0 - ((y - C.y) / R.y) ** 2 - ((z - C.z) / R.z) ** 2
    x = C.x + s * R.x * math.sqrt(max(q, 0.0))
    n = Vector(((x - C.x) / R.x ** 2, (y - C.y) / R.y ** 2, (z - C.z) / R.z ** 2)).normalized()
    return Vector((x, y, z)) + n * out, n


def _yaw(n):
    return -math.degrees(math.atan2(n.x, n.y))


def _bolt(h, bone, p, n, r, col="gun", ch="flat"):
    """A domed bolt head on the surface (p, n): one UV island (a capped cylinder makes three)."""
    q = Vector((0, 0, 1)).rotation_difference(n)
    h.sphere(bone, p, (r, r, r * 0.75), col, ch, seg=(6, 3), rot=tuple(math.degrees(a) for a in q.to_euler("XYZ")),
             clip=[((0, 0, -0.05), (0, 0, -1))])


def _springs(h, specs):
    """Sec_ spring chains on the gen path (design/art/secondary-motion.md). hero_gen.build does
    not call hero_hd.add_secondary, so the parts function calls it with this hero's own specs."""
    import hero_hd
    orig = hero_hd._sec_specs
    hero_hd._sec_specs = lambda _h: specs
    try:
        return hero_hd.add_secondary(h)
    finally:
        hero_hd._sec_specs = orig


def _generic(spec):
    import hero_defs_more
    return hero_defs_more.generic(spec)


def _sel(names=None, bones=None, extra=None):
    def f(co, name, dom):
        return (names is None or name in names) and (bones is None or dom in bones) and (extra is None or extra(co))
    return f


# ======================================================================== Ryker Vance
RYKER_PAL = {"olive": "#6F8C45", "bone": "#EAD49C", "suit": "#3E4F6A", "rubber": "#353A44", "gun": "#4C5564",
             "glass": "#1D3A55", "chrome": "#C9D4E2", "antenna": "#C6D2E0", "trim": "#4A5640", "khaki": "#9C8B5E",
             "team": TEAM, "eye": "#15151A"}


def ryker_parts(h):
    import hero_hd
    k = _k(h)
    lo, hi, hc, hr, eye_z = _head(h)
    skin = hero_hd.BodySkin(h)
    # ---------------------------------------------------------------- tactical visor helmet
    C = Vector((0, hc.y - 0.004, hc.z + 0.016))
    R = Vector((hr.x * 1.2, hr.y * 1.12, hr.z * 1.08))
    h.sphere("Head", C, R, "olive", seg=(26, 16), clip=[((0, 0, -0.42), (0, 0, -1))])            # dome
    _band(h, "Head", C, R * 1.022, "bone", seg=(26, 16), x=(-0.13, 0.13), z=(0.38, None))       # centre ridge
    _band(h, "Head", C, Vector((R.x * 1.07, R.y * 1.1, R.z * 1.05)), "olive", z=(0.3, 0.44), y=(0.3, None))  # brow
    _band(h, "Head", C, Vector((R.x * 1.05, R.y * 1.08, R.z * 1.03)), "gun", z=(0.19, 0.31), y=(0.0, None))  # top rim
    _band(h, "Head", C, Vector((R.x * 1.085, R.y * 1.115, R.z * 1.06)), "bone", z=(0.27, 0.31), y=(0.2, None))
    _band(h, "Head", C, Vector((R.x * 1.035, R.y * 1.065, R.z * 1.02)), "glass", z=(-0.24, 0.21), y=(0.12, None))
    _band(h, "Head", C, Vector((R.x * 1.05, R.y * 1.08, R.z * 1.03)), "gun", z=(-0.33, -0.22), y=(0.0, None))
    _band(h, "Head", C, Vector((R.x * 1.045, R.y * 1.075, R.z * 1.02)), "team", "team_emit",       # lens line
          z=(-0.02, 0.012), y=(0.45, None))
    for sx in (-1, 1):                                                                             # eye lenses
        p, n = _on(C, Vector((R.x * 1.035, R.y * 1.065, R.z * 1.02)), sx * 0.036 * k, eye_z + 0.004, 0.004)
        h.sphere("Head", p, Vector((0.021 * k, 0.007, 0.013 * k)), "team", "team_emit", seg=(12, 6),
                 rot=(0, sx * 10, _yaw(n)))
        h.sphere("Head", p - n * 0.002, Vector((0.026 * k, 0.006, 0.017 * k)), "gun", seg=(12, 6),
                 rot=(0, sx * 10, _yaw(n)))
        # visor hinge hub + bolt at the temple
        hp, hn = _side(C, R, sx, C.y + R.y * 0.42, eye_z + 0.006, 0.004)
        h.cyl("Head", hp - hn * 0.004, hp + hn * 0.012, 0.02 * k, 0.018 * k, "gun", seg=12)
        _bolt(h, "Head", hp + hn * 0.012, hn, 0.008 * k, "chrome", "chrome")
    # earpieces: layered cups, LED ring, bolts
    for sx in (-1, 1):
        ep, en = _side(C, R, sx, C.y - R.y * 0.08, C.z - R.z * 0.18)
        h.cyl("Head", ep - en * 0.01, ep + en * 0.028 * k, 0.05 * k, 0.047 * k, "suit", seg=16)
        h.cyl("Head", ep + en * 0.028 * k, ep + en * 0.04 * k, 0.04 * k, 0.034 * k, "olive", seg=16)
        h.torus("Head", ep + en * 0.031 * k, en, 0.044 * k, 0.0045 * k, "team", "team_emit", seg=(18, 4))
        h.cyl("Head", ep + en * 0.04 * k, ep + en * 0.046 * k, 0.016 * k, 0.012 * k, "gun", seg=8)
        for i in range(4):
            a = math.pi / 4 + i * math.pi / 2
            t = Vector((0, 0, 1)).cross(en).normalized()
            u = en.cross(t)
            _bolt(h, "Head", ep + en * 0.03 * k + (t * math.cos(a) + u * math.sin(a)) * 0.037 * k, en, 0.0045 * k)
        # rivet row along the dome edge
        for i in range(4):
            rp, rn = _side(C, R, sx, C.y - R.y * (0.62 - i * 0.18), C.z - R.z * 0.36, 0.0)
            _bolt(h, "Head", rp, rn, 0.0055 * k)
    # antenna off the left earpiece (Sec_antenna_1 spring)
    lx = 1.0 if h.jh("UpperLeg_L").x > 0 else -1.0
    ep, en = _side(C, R, lx, C.y - R.y * 0.08, C.z - R.z * 0.18)
    base = ep + en * 0.03 * k + Vector((0, -0.03, 0.035)) * k
    h.box("Head", base, Vector((0.022, 0.03, 0.04)) * k, "gun", rot=(0, 0, 0), bevel=0.3)
    tip = base + Vector((lx * 0.02, -0.07, 0.24)) * k
    h.cyl("Head", base + Vector((0, 0, 0.02)) * k, tip, 0.0055 * k, 0.003 * k, "antenna", "chrome", seg=6)
    h.sphere("Head", tip, Vector((0.009, 0.009, 0.009)) * k, "team", "team_emit", seg=(8, 5))
    # mic boom off the right earpiece
    ep, en = _side(C, R, -lx, C.y - R.y * 0.08, C.z - R.z * 0.18)
    m0 = ep + en * 0.03 * k
    m1 = Vector((-lx * R.x * 0.75, C.y + R.y * 0.95, C.z - R.z * 0.62))
    h.cyl("Head", m0, m1, 0.0045 * k, 0.004 * k, "gun", seg=6)
    h.sphere("Head", m1, Vector((0.011, 0.014, 0.01)) * k, "rubber", seg=(8, 5))
    # rebreather jaw guard: plates, vents, twin filters
    J = Vector((0, hc.y + hr.y * 0.42, C.z - R.z * 0.62))
    JR = Vector((R.x * 0.82, R.y * 0.72, R.z * 0.42))
    _band(h, "Head", J, JR, "suit", seg=(20, 12), y=(-0.1, None))
    _band(h, "Head", J, JR * 1.06, "olive", seg=(20, 12), x=(0.5, None), y=(-0.05, None), z=(-0.7, 0.75))
    _band(h, "Head", J, JR * 1.06, "olive", seg=(20, 12), x=(None, -0.5), y=(-0.05, None), z=(-0.7, 0.75))
    for sx in (-1, 1):
        cp, cn = _on(J, JR * 1.06, sx * JR.x * 0.78, J.z + JR.z * 0.3, 0.002)
        _bolt(h, "Head", cp, cn, 0.005 * k)
        for i in range(3):
            pv, nv = _on(J, JR, sx * JR.x * 0.2, J.z + JR.z * (0.35 - i * 0.3), 0.004)
            h.box("Head", pv, Vector((0.022, 0.006, 0.0055)) * k, "rubber", rot=(0, 0, _yaw(nv)), bevel=0.2)
        fp, fn = _on(J, JR, sx * JR.x * 0.42, J.z - JR.z * 0.45, 0.0)
        d = (fn + Vector((sx * 0.5, 0, -0.6))).normalized()
        h.cyl("Head", fp - d * 0.01, fp + d * 0.028 * k, 0.019 * k, 0.021 * k, "gun", seg=12)
        h.cyl("Head", fp + d * 0.028 * k, fp + d * 0.036 * k, 0.022 * k, 0.018 * k, "olive", seg=12)
        h.cyl("Head", fp + d * 0.036 * k, fp + d * 0.039 * k, 0.011 * k, 0.011 * k, "rubber", seg=8)
    # NVG mount on the brow + rear neck guard
    p, n = _on(C, Vector((R.x * 1.07, R.y * 1.1, R.z * 1.05)), 0, C.z + R.z * 0.44, 0.004)
    h.box("Head", p + Vector((0, 0, 0.008)) * k, Vector((0.05, 0.022, 0.036)) * k, "gun", rot=(-25, 0, 0), bevel=0.3)
    h.box("Head", p + Vector((0, 0.012, 0.004)) * k, Vector((0.028, 0.012, 0.02)) * k, "rubber", rot=(-25, 0, 0),
          bevel=0.3)
    for sx in (-1, 1):
        _bolt(h, "Head", p + Vector((sx * 0.018, 0.012, 0.016)) * k, Vector((0, 0.5, 0.86)), 0.004 * k, "chrome",
              "chrome")
    _band(h, "Head", C, Vector((R.x * 1.03, R.y * 1.05, R.z * 1.04)), "olive", z=(-0.66, -0.3), y=(None, -0.25))
    # ---------------------------------------------------------------- oversized LEFT pauldron (the hook)
    sh = h.jh("UpperArm_L")
    sg = 1.0 if sh.x > 0 else -1.0
    pc = sh + Vector((0.01 * sg, -0.005, 0.035)) * k
    tilt = (0, -22 * -sg, 0)
    h.sphere("Clavicle_L", pc, Vector((0.125, 0.135, 0.1)) * k, "olive", seg=(16, 10), rot=tilt,
             clip=[((0, 0, -0.18), (0, 0, -1))])
    h.sphere("Clavicle_L", pc + Vector((0.012 * sg, 0, -0.035)) * k, Vector((0.133, 0.143, 0.085)) * k, "suit",
             seg=(16, 10), rot=tilt, clip=[((0, 0, -0.2), (0, 0, -1)), ((0, 0, 0.25), (0, 0, 1))])
    h.sphere("Clavicle_L", pc + Vector((0, 0, 0.012)) * k, Vector((0.127, 0.137, 0.102)) * k, "bone", seg=(16, 10),
             rot=tilt, clip=[((0, 0.25, 0), (0, 1, 0)), ((0, -0.25, 0), (0, -1, 0)), ((0, 0, 0.5), (0, 0, -1))])
    h.box("Clavicle_L", pc + Vector((0.0, 0.095, 0.045)) * k, Vector((0.14, 0.025, 0.03)) * k, "team", "team",
          rot=(-30, tilt[1], 0), bevel=0.2)
    for i in range(5):
        a = math.radians(-60 + i * 30)
        rp = pc + Vector((sg * math.sin(a) * 0.08, math.cos(a) * 0.1, 0.02)) * k
        h.sphere("Clavicle_L", rp + Vector((0, 0, 0.05)) * k, Vector((0.007, 0.007, 0.005)) * k, "gun", seg=(6, 4))
    # ---------------------------------------------------------------- plate carrier
    uc = h.jh("UpperChest")
    zc = uc.z - 0.07 * k
    p, n = h.surface(0, zc, 1)
    plate = p + n * 0.03 * k
    h.box("UpperChest", plate, Vector((0.28, 0.035, 0.26)) * k, "olive", bevel=0.35, taper=(1.08, 1.0))
    for i in range(2):  # MOLLE rows
        h.box("UpperChest", plate + Vector((0, 0.02, -0.08 + i * 0.05)) * k, Vector((0.26, 0.008, 0.012)) * k,
              "trim", bevel=0.1)
    for x in (-0.085, 0.0, 0.085):  # mag pouches on the front flap
        q, qn = h.surface(x * k, h.jh("Chest").z - 0.03 * k, 1)
        hero_hd.pouch(h, q + qn * 0.03 * k, qn, Vector((0, 0, 1)), (0.07 * k, 0.11 * k, 0.04 * k), skin,
                      col="olive", flap="khaki")
    # name tape + team chest band
    h.box("UpperChest", plate + Vector((0.07, 0.02, 0.09)) * k, Vector((0.1, 0.008, 0.025)) * k, "khaki", bevel=0.2)
    h.box("UpperChest", plate + Vector((-0.07, 0.02, 0.09)) * k, Vector((0.08, 0.008, 0.025)) * k, "team", "team",
          bevel=0.2)
    # shoulder straps
    for x in (-0.1, 0.1):
        pts = []
        for i in range(7):
            t = i / 6
            a = math.pi * t
            pts.append(Vector((x * k, uc.y + math.cos(a) * 0.15 * k, uc.z + 0.06 * k + math.sin(a) * 0.05 * k)))
        for p0, p1 in zip(pts, pts[1:]):
            out = ((p0 + p1) / 2 - Vector((x * k, uc.y, uc.z))).normalized()
            h.box("UpperChest", None, ((p1 - p0).length + 0.01, 0.05 * k, 0.012 * k), "olive",
                  mat=hero_defs._along_box(p0, p1, out), bevel=0.2)
    # grenade bandolier (left shoulder -> right hip)
    a = (-0.12 * sg * -1 * k, h.jh("Clavicle_L").z + 0.0)
    b = (0.15 * -sg * k, h.belt_z + 0.04)
    pts = []
    for i in range(8):
        t = i / 7
        x, z = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
        p, n = h.surface(x, z, 1)
        pts.append((p + n * 0.05 * k, n))
    bands = [(h.jh("UpperChest").z, "UpperChest"), (h.jh("Chest").z, "Chest"), (h.jh("Spine").z, "Spine")]
    for (p0, n0), (p1, _) in zip(pts, pts[1:]):
        h.box(None, None, ((p1 - p0).length + 0.01, 0.05 * k, 0.014 * k), "rubber",
              mat=hero_defs._along_box(p0, p1, n0), weights=lambda co: _wz(h, co.z, bands))
    for i in (3, 5):
        p, n = pts[i]
        h.sphere(None, p + n * 0.024 * k, Vector((0.028, 0.028, 0.036)) * k, "olive", seg=(10, 6),
                 weights=lambda co: _wz(h, co.z, bands))
        h.cyl(None, p + n * 0.024 * k + Vector((0, 0, 0.03)) * k, p + n * 0.024 * k + Vector((0, 0, 0.045)) * k,
              0.012 * k, 0.01 * k, "gun", seg=8, weights=lambda co: _wz(h, co.z, bands))
    # back plate + radio pack
    p, n = h.surface(0, uc.z - 0.06 * k, -1)
    h.box("UpperChest", p + Vector((0, -0.03, 0)) * k, Vector((0.28, 0.04, 0.3)) * k, "olive", bevel=0.35)
    h.box("UpperChest", p + Vector((0, -0.085, 0.02)) * k, Vector((0.18, 0.08, 0.2)) * k, "suit", bevel=0.3)
    h.box("UpperChest", p + Vector((0, -0.128, 0.05)) * k, Vector((0.12, 0.01, 0.04)) * k, "team", "team_emit",
          bevel=0.2)
    # ---------------------------------------------------------------- belt, pouches, pads, boots
    pts = hero_hd.ring(h, Vector((0, h.jh("Hips").y, h.belt_z)), (0, 0, 1), ("Hips", "Spine"), n=32, off=0.012)
    hero_hd.strap(h, pts, (0, 0, 1), 0.055 * k, 0.014, "rubber", skin)
    q, d = max(pts, key=lambda pd: pd[1].y)
    M = hero_hd.frame(q + d * 0.014, d, Vector((0, 0, 1)))
    hero_hd.piece(h, M, (0, 0, 0.004), (0.06 * k, 0.05 * k, 0.012), "gun", skin.fixed(q), bevel=0.4)
    for ang in (55, 115, -60, -120):
        q, d = min(pts, key=lambda pd: abs(math.degrees(math.atan2(pd[1].x * -sg, pd[1].y)) - ang))
        hero_hd.pouch(h, q + d * 0.016, d, Vector((0, 0, 1)), (0.07 * k, 0.04 * k, 0.075 * k), skin, col="olive",
                      flap="khaki")
    for s in ("L", "R"):
        kn = h.jh("LowerLeg_" + s)
        h.box("LowerLeg_" + s, kn + Vector((0, 0.07, -0.02)) * k, Vector((0.1, 0.045, 0.12)) * k, "olive", bevel=0.45,
              taper=(0.8, 0.8))
        h.box("LowerLeg_" + s, kn + Vector((0, 0.094, -0.02)) * k, Vector((0.06, 0.008, 0.02)) * k, "team", "team",
              bevel=0.2)
    hero_defs.closed_boots(h, "rubber", "suit", k)
    for s in ("L", "R"):
        wr = h.jh("Hand_" + s)
        fwd = (h.jt("Hand_" + s) - wr).normalized()
        back = -h.palm[s]
        p0 = wr + fwd * 0.07 * k + back * 0.03 * k
        h.box("Hand_" + s, p0, (0.075 * k, 0.03 * k, 0.02 * k), "olive", mat=_along(p0 - fwd * 0.02, p0 + fwd * 0.02,
              back), bevel=0.4)
    ep = h.jl("LowerArm_R", 0.45)  # chrome stim port ring
    h.torus("LowerArm_R", ep, h.jt("LowerArm_R") - h.jh("LowerArm_R"), 0.05 * k, 0.009 * k, "team", "team_emit")
    _springs(h, [("Sec_antenna_1", "Head", 2, "bottom",
                  _sel({"antenna", "team"}, {"Head"}, lambda co: co.z > C.z - 0.01 and co.y < C.y - 0.02 * k
                       and co.x * lx > R.x * 0.9))])


def breakline_ar7(h, W):
    """Ryker's own Breakline AR-7 (W16): a bulky bullpup-free full-auto rifle. Boxy
    upper receiver with a carry rail, a holo sight with a team-lit lens, a slab
    handguard with vent cuts, a ribbed straight mag, a muzzle brake and a skeleton
    stock. Weapon space: origin = right grip, +Y barrel, +Z up."""
    def wb(c, s, col, ch="flat", **kw):
        h.box("Weapon", None, s, col, ch, mat=W @ Matrix.Translation(Vector(c)) @ _rx(kw.pop("rx", 0)), **kw)

    def cyl(a, b, r0, r1, col, ch="flat", seg=10):
        h.cyl("Weapon", W @ Vector(a), W @ Vector(b), r0, r1, col, ch, seg=seg)
    wb((0, -0.012, -0.048), (0.032, 0.044, 0.105), "rubber", rx=-18, bevel=0.35)       # grip
    wb((0, 0.03, -0.012), (0.014, 0.065, 0.006), "gun", bevel=0.3)                      # trigger guard
    wb((0, 0.07, 0.035), (0.062, 0.3, 0.09), "gun", bevel=0.25)                         # lower receiver
    wb((0, 0.08, 0.088), (0.058, 0.27, 0.03), "olive", bevel=0.3)                       # upper receiver
    wb((0.033, 0.05, 0.045), (0.006, 0.07, 0.035), "chrome", "chrome", bevel=0.2)      # ejection port
    for i in range(4):                                                                  # top rail teeth
        wb((0, 0.0 + i * 0.065, 0.108), (0.03, 0.03, 0.012), "gun", bevel=0.15)
    wb((0, 0.04, 0.135), (0.04, 0.07, 0.04), "gun", bevel=0.3)                          # holo sight body
    wb((0, 0.072, 0.15), (0.044, 0.008, 0.05), "rubber", bevel=0.2)                    # hood
    wb((0, 0.074, 0.15), (0.03, 0.006, 0.032), "team", "team_emit", bevel=0.0)        # lens
    wb((0, 0.33, 0.045), (0.07, 0.24, 0.08), "olive", bevel=0.35, taper=(0.9, 1.0))     # handguard slab
    for i in range(4):                                                                  # vent cuts
        wb((0, 0.25 + i * 0.05, 0.055), (0.074, 0.03, 0.012), "rubber", bevel=0.1)
    wb((0, 0.3, -0.005), (0.03, 0.05, 0.05), "rubber", rx=8, bevel=0.3)                # foregrip stub
    cyl((0, 0.44, 0.05), (0, 0.6, 0.05), 0.014, 0.014, "gun", seg=10)                  # barrel
    cyl((0, 0.6, 0.05), (0, 0.67, 0.05), 0.024, 0.024, "gun", seg=8)                   # muzzle brake
    for y in (0.615, 0.635, 0.655):
        wb((0, y, 0.05), (0.052, 0.006, 0.014), "rubber", bevel=0.0)
    wb((0, 0.12, -0.08), (0.036, 0.07, 0.17), "rubber", rx=12, bevel=0.3)              # mag
    for i in range(4):
        wb((0, 0.125 + i * 0.004, -0.05 - i * 0.035), (0.04, 0.074, 0.008), "gun", rx=12, bevel=0.1)
    wb((0, 0.135, -0.165), (0.04, 0.078, 0.014), "olive", rx=12, bevel=0.3)            # mag base plate
    wb((0, -0.12, 0.05), (0.03, 0.12, 0.022), "gun", bevel=0.3)                         # stock tube
    wb((0, -0.17, 0.0), (0.03, 0.022, 0.08), "gun", rx=-30, bevel=0.3)                  # stock strut
    wb((0, -0.24, 0.025), (0.05, 0.035, 0.13), "rubber", bevel=0.35)                    # butt pad
    wb((0, -0.205, 0.075), (0.036, 0.07, 0.022), "olive", bevel=0.3)                    # cheek rest
    wb((0.031, 0.32, 0.045), (0.006, 0.16, 0.022), "team", "team", bevel=0.0)          # team stripes
    wb((-0.031, 0.32, 0.045), (0.006, 0.16, 0.022), "team", "team", bevel=0.0)


def ryker_idle(p, ph, f):
    """Personal idle: soldier's low-ready stance, feet wide, knees soft, weight forward,
    a slow breath and a small weight shift between the feet."""
    from hero_anims import legs
    w = math.sin(ph)
    b = math.sin(2 * ph)
    legs(p, 0, 0, 0)
    p.rot("UpperLeg_L", [("x", 10 + 0.8 * w), ("z", -7), ("y", 4)])
    p.rot("UpperLeg_R", [("x", 4 - 0.8 * w), ("z", 7), ("y", -6)])
    p.rot("LowerLeg_L", [("x", -16 - 1.0 * w)])
    p.rot("LowerLeg_R", [("x", -9 + 1.0 * w)])
    p.rot("Foot_L", [("x", 6)])
    p.rot("Foot_R", [("x", 4), ("z", 6)])
    p.rot("Hips", [("y", 1.5 * w), ("z", -4)])
    p.hips((0.008 * w * p.k, 0.01 * p.k, -0.03 * p.k - 0.004 * b * p.k))
    p.rot("Spine", [("x", 6 + 0.8 * b), ("y", -1.5 * w), ("z", 2)])
    p.rot("Chest", [("x", 3 + 0.6 * b), ("z", 2)])


def ryker_post(c):
    """Painted helmet detail: chipped edges, scratches, a unit stencil, a kill tally,
    a hazard flash on the jaw guard; glossy visor, satin helmet paint, matte cloth."""
    import hero_decals as D
    H, k = c["H"], c["k"]
    z0 = H * 0.845
    helm = D.region(c, ["#6F8C45", "#EAD49C"], zmin=z0)
    D.wear(c, helm, "#C7C3AE", 0.9)
    D.scratches(c, helm, "#D8D3BC", density=0.45, strength=0.55)
    D.gloss(c, D.region(c, ["#6F8C45"], zmin=z0), 0.08)   # satin paint
    D.gloss(c, D.region(c, ["#1D3A55"], zmin=z0), 0.75)   # glossy visor glass
    D.gloss(c, D.region(c, ["#4C5564"], zmin=z0), 0.35)   # rims and hubs
    olive = D.region(c, ["#6F8C45"], zmin=z0)
    lo, hi = D.bounds(c, olive)
    mid = (lo + hi) / 2
    lx = -1.0  # body_gen: the hero's left is -X
    zs = mid[2] + (hi[2] - mid[2]) * 0.45
    D.decal(c, D.digits("07"), (0, mid[1] - 0.005, zs), (-lx, 0, 0), (0, 0, 1), (0.055 * k, 0.034 * k), olive,
            "#EAD49C", depth=0.2)
    D.decal(c, D.tally(5), (0, mid[1] - 0.01, zs), (lx, 0, 0), (0, 0, 1), (0.055 * k, 0.028 * k), olive,
            "#EAD49C", depth=0.2)
    D.decal(c, D.chevron(n=2), (0, lo[1], mid[2] + 0.01 * k), (0, -1, 0), (0, 0, 1), (0.05 * k, 0.045 * k), olive,
            "#EAD49C", depth=0.2)
    jaw = D.region(c, ["#3E4F6A"], zmin=z0 - 0.04 * k)
    D.decal(c, D.stripes(3), (lx * 0.035 * k, 0.12 * k, H * 0.87), (0, 1, 0), (0, 0, 1), (0.035 * k, 0.025 * k), jaw,
            "#E8B23A", depth=0.08, face=0.3)
    D.scratches(c, D.region(c, ["#6F8C45", "#4C5564"], zmax=z0), "#C9C4AE", density=0.25, strength=0.4, seed=19.0)
    return c["alb"], c["spec"], c["emit"]


# ======================================================================== Brannoc
BRANNOC_PAL = {"teal": "#2F9A90", "iron": "#9AA3AD", "soot": "#5E554C", "bone": "#E8D9B0", "gold": "#E0AC48",
               "gun": "#565E69", "slit": "#15191E", "team": TEAM, "eye": "#101014"}
BRANNOC_SPEC = {"paint": {"head": "soot", "torso": "soot", "sleeves": "soot", "gloves": "iron", "legs": "soot",
                          "boots": "soot", "belt": "iron", "forearm": "teal"}, "sleeve_t": 0.85, "boot_t": 0.35,
                "torso_shell": {"offset": 0.03, "color": "teal", "rim": "iron", "arms": True},
                "boot_shell": (0.02, "soot", "iron"), "thigh_shell": (0.026, "teal", "iron")}


def brannoc_parts(h):
    import hero_hd
    k = _k(h)
    lo, hi, hc, hr, eye_z = _head(h)
    skin = hero_hd.BodySkin(h)
    lx = 1.0 if h.jh("UpperLeg_L").x > 0 else -1.0
    # ---------------------------------------------------------------- heavy closed helm
    W, D, Hh = hr.x * 2.75, hr.y * 2.6, hr.z * 2.45
    hb = Vector((0, hc.y - 0.006, hc.z + 0.016))
    h.box("Head", hb, (W, D, Hh), "teal", bevel=0.3, taper=(0.88, 0.9))                    # bucket
    h.box("Head", hb + Vector((0, 0, Hh * 0.5)), (W * 0.84, D * 0.86, Hh * 0.2), "teal", bevel=0.6,
          taper=(0.72, 0.76))                                                               # crown cap
    fy = hb.y + D / 2                                                                       # front face plane
    # sculpted faceplate: two angled halves meeting in a prow ridge
    for sx in (-1, 1):
        c = Vector((sx * W * 0.24, fy + 0.006 - W * 0.06, hb.z - Hh * 0.08))
        h.box("Head", c, (W * 0.52, 0.03 * k, Hh * 0.8), "iron", rot=(0, 0, sx * 18), bevel=0.4,
              taper=(0.9, 1.0))
    h.box("Head", (0, fy + 0.016, hb.z - Hh * 0.1), (0.022 * k, 0.03 * k, Hh * 0.82), "gun", bevel=0.4,
          taper=(1.4, 1.0))                                                                 # prow ridge
    # T-visor: dark slit frame + team glow
    zt = eye_z + 0.006
    h.box("Head", (0, fy + 0.02, zt), (W * 0.82, 0.03 * k, 0.034 * k), "slit", bevel=0.3)
    h.box("Head", (0, fy + 0.032, zt), (W * 0.76, 0.012, 0.016 * k), "team", "team_emit", bevel=0.2)
    h.box("Head", (0, fy + 0.034, zt - 0.05 * k), (0.03 * k, 0.03 * k, 0.1 * k), "slit", bevel=0.3)
    h.box("Head", (0, fy + 0.046, zt - 0.05 * k), (0.014 * k, 0.012, 0.09 * k), "team", "team_emit", bevel=0.2)
    # heavy brow ridge (overhang) with a gold trim line
    h.box("Head", (0, fy + 0.03, zt + 0.042 * k), (W * 1.02, 0.06 * k, 0.04 * k), "iron", rot=(-10, 0, 0),
          bevel=0.45, taper=(0.95, 0.8))
    h.box("Head", (0, fy + 0.052, zt + 0.03 * k), (W * 0.9, 0.012, 0.008 * k), "gold", rot=(-10, 0, 0), bevel=0.2)
    # cheek guards down to the jaw
    for sx in (-1, 1):
        c = Vector((sx * W * 0.45, fy - D * 0.2, hb.z - Hh * 0.2))
        h.box("Head", c, (0.024 * k, D * 0.42, Hh * 0.5), "iron", rot=(0, 0, -sx * 4), bevel=0.4, taper=(1.0, 0.85))
        for i in range(3):  # side breathing slats
            h.box("Head", c + Vector((sx * 0.012 * k, 0.01 * k, -0.03 * k + i * 0.026 * k)),
                  (0.006, 0.05 * k, 0.008 * k), "slit", rot=(0, 0, -sx * 4), bevel=0.2)
    # crest ridge front -> back, gold capped
    h.box("Head", (0, hb.y - 0.01, hb.z + Hh * 0.6), (0.03 * k, D * 0.9, 0.05 * k), "teal", bevel=0.4,
          taper=(0.7, 0.95))
    h.box("Head", (0, hb.y - 0.01, hb.z + Hh * 0.6 + 0.026 * k), (0.012 * k, D * 0.85, 0.008 * k), "gold", bevel=0.3)
    # rivets: faceplate rim, brow, crest base
    for i in range(5):
        z = hb.z - Hh * 0.42 + i * Hh * 0.17
        for sx in (-1, 1):
            p = Vector((sx * W * 0.43, fy + 0.014 - W * 0.12, z))
            _bolt(h, "Head", p, Vector((sx * 0.31, 0.95, 0)).normalized(), 0.0075 * k)
    for i in range(4):
        x = (-0.75 + i * 0.5) * W * 0.5
        _bolt(h, "Head", Vector((x, fy + 0.055, zt + 0.05 * k)), Vector((0, 0.8, 0.6)), 0.007 * k, "gun")
    # gorget: stacked iron rings under the helm
    nk = h.jh("Neck")
    for i, (r, z) in enumerate(((0.15, 0.0), (0.135, 0.035))):
        h.cyl("Neck" if i else "UpperChest", (0, nk.y, nk.z + (z - 0.02) * k), (0, nk.y, nk.z + (z + 0.02) * k),
              r * k, (r - 0.012) * k, "iron" if i == 0 else "gun", seg=20)
    # ---------------------------------------------------------------- tiered pauldrons
    for s in ("L", "R"):
        sh = h.jh("UpperArm_" + s)
        sg = 1.0 if sh.x > 0 else -1.0
        tilt = (0, sg * 22, 0)
        pc = sh + Vector((sg * 0.035, 0, 0.05)) * k
        h.sphere("Clavicle_" + s, pc, Vector((0.17, 0.18, 0.13)) * k, "teal", seg=(18, 10), rot=tilt,
                 clip=[((0, 0, -0.1), (0, 0, -1))])                                         # dome
        h.sphere("Clavicle_" + s, pc + Vector((sg * 0.012, 0, -0.03)) * k, Vector((0.18, 0.19, 0.12)) * k, "iron",
                 seg=(18, 10), rot=tilt, clip=[((0, 0, -0.35), (0, 0, -1)), ((0, 0, 0.05), (0, 0, 1))])   # tier 2
        h.sphere("Clavicle_" + s, pc + Vector((sg * 0.024, 0, -0.07)) * k, Vector((0.19, 0.2, 0.11)) * k, "teal",
                 seg=(18, 10), rot=tilt, clip=[((0, 0, -0.45), (0, 0, -1)), ((0, 0, -0.1), (0, 0, 1))])   # tier 3
        h.sphere("Clavicle_" + s, pc + Vector((0, 0, 0.003)) * k, Vector((0.172, 0.182, 0.132)) * k, "gold",
                 seg=(18, 10), rot=tilt, clip=[((0, 0, -0.1), (0, 0, -1)), ((0, 0, 0.02), (0, 0, 1))])    # trim
        top = pc + Vector((0, 0, 0.115)) * k
        h.box("Clavicle_" + s, top, Vector((0.05, 0.26, 0.03)) * k, "team", "team", rot=tilt, bevel=0.3)
        for j in range(3):
            _bolt(h, "Clavicle_" + s, top + Vector((sg * 0.06, -0.08 + j * 0.08, -0.012)) * k,
                  Vector((sg * 0.37, 0, 0.93)), 0.009 * k)
    # ---------------------------------------------------------------- gauntlets
    for s in ("L", "R"):
        a, b = h.jh("LowerArm_" + s), h.jt("LowerArm_" + s)
        ax = (b - a).normalized()
        g = hero_hd.ring(h, h.jl("LowerArm_" + s, 0.55), ax, ("LowerArm_" + s,), n=16, off=0.012, reach=0.3)
        hero_hd.strap(h, g, ax, 0.2 * k, 0.03, "iron", skin)
        g = hero_hd.ring(h, h.jl("LowerArm_" + s, 0.9), ax, ("LowerArm_" + s, "Hand_" + s), n=16, off=0.04,
                         reach=0.3)
        hero_hd.strap(h, g, ax, 0.05 * k, 0.025, "gold", skin)
        wr = h.jh("Hand_" + s)
        fwd = (h.jt("Hand_" + s) - wr).normalized()
        back = -h.palm[s]
        p0 = wr + fwd * 0.07 * k + back * 0.035 * k
        h.box("Hand_" + s, p0, (0.1 * k, 0.04 * k, 0.03 * k), "iron", mat=_along(p0 - fwd * 0.03, p0 + fwd * 0.03,
              back), bevel=0.4)
        for j in range(3):
            q = p0 + fwd * 0.04 * k + (h.palm[s].cross(fwd)).normalized() * (j - 1) * 0.028 * k + back * 0.014 * k
            _bolt(h, "Hand_" + s, q, back, 0.008 * k, "gun")
    # right forearm shield-generator slab (asymmetric hook)
    a, b = h.jh("LowerArm_R"), h.jt("LowerArm_R")
    m = _along(a, b, Vector((1, 0, 0)))
    w1 = lambda co: {"LowerArm_R": 1.0}
    h.box(None, None, (0.06 * k, (b - a).length * 0.95, 0.24 * k), "teal", mat=m @ Matrix.Translation((0.09 * k, 0, 0)),
          weights=w1, bevel=0.35)
    h.box(None, None, (0.016 * k, (b - a).length * 0.7, 0.13 * k), "team", "team_emit",
          mat=m @ Matrix.Translation((0.125 * k, 0, 0)), weights=w1, bevel=0.2)
    # ---------------------------------------------------------------- chest: furnace-heart grille
    uc = h.jh("UpperChest")
    p, n = h.surface(0, uc.z - 0.07 * k, 1)
    c = p + n * 0.04 * k
    h.box("UpperChest", c, Vector((0.38, 0.06, 0.3)) * k, "teal", bevel=0.35, taper=(1.12, 1.0))
    h.box("UpperChest", c + Vector((0, 0.035, 0)) * k, Vector((0.16, 0.02, 0.13)) * k, "gun", bevel=0.25)
    for i in range(4):
        h.box("UpperChest", c + Vector((0, 0.047, (i - 1.5) * 0.028)) * k, Vector((0.13, 0.008, 0.012)) * k,
              "team", "team_emit", bevel=0.0)
    for sx in (-1, 1):
        for sz in (-1, 1):
            _bolt(h, "UpperChest", c + Vector((sx * 0.07, 0.045, sz * 0.055)) * k, Vector((0, 1, 0)), 0.008 * k)
    pb, nb = h.surface(0, uc.z - 0.05 * k, -1)
    h.box("UpperChest", pb + nb * 0.07 * k, Vector((0.32, 0.12, 0.34)) * k, "soot", bevel=0.3)
    for i in range(3):
        h.box("UpperChest", pb + nb * 0.135 * k + Vector((0, 0, 0.07 * (i - 1))) * k, Vector((0.24, 0.016, 0.022)) * k,
              "team", "team_emit", bevel=0.0)
    # ---------------------------------------------------------------- belt plates, knees, boots
    pts = hero_hd.ring(h, Vector((0, h.jh("Hips").y, h.belt_z)), (0, 0, 1), ("Hips", "Spine"), n=32, off=0.014)
    hero_hd.strap(h, pts, (0, 0, 1), 0.07 * k, 0.018, "iron", skin)
    q, d = max(pts, key=lambda pd: pd[1].y)
    M = hero_hd.frame(q + d * 0.02, d, Vector((0, 0, 1)))
    hero_hd.piece(h, M, (0, 0, 0.006), (0.1 * k, 0.08 * k, 0.016), "gold", skin.fixed(q), bevel=0.4)
    for x in (-0.15, 0.15):
        q, qn = h.surface(x * k, h.belt_z - 0.09 * k, 1)
        h.box("Hips", q + qn * 0.04 * k, Vector((0.14, 0.03, 0.16)) * k, "teal", bevel=0.3, taper=(0.8, 1.0))
    for s in ("L", "R"):
        kn = h.jh("LowerLeg_" + s)
        h.box("LowerLeg_" + s, kn + Vector((0, 0.085, 0)) * k, Vector((0.14, 0.05, 0.16)) * k, "iron", bevel=0.45,
              taper=(0.8, 0.8))
        _bolt(h, "LowerLeg_" + s, kn + Vector((0, 0.112, 0.02)) * k, Vector((0, 1, 0)), 0.01 * k, "gun")
    hero_defs.closed_boots(h, "soot", "iron", k)


def ironmaw_w16(h, W):
    """Brannoc's own Ironmaw (W16): a two-hand siege scattergun. Slab receiver, a drum
    magazine, a thick barrel shroud with heat vents and a toothed 'maw' muzzle that
    glows inside, a top carry handle and a side grip. Weapon space: origin = right
    grip, +Y barrel, +Z up."""
    def wb(c, s, col, ch="flat", **kw):
        h.box("Weapon", None, s, col, ch, mat=W @ Matrix.Translation(Vector(c)) @ _rx(kw.pop("rx", 0)), **kw)

    def cyl(a, b, r0, r1, col, ch="flat", seg=12):
        h.cyl("Weapon", W @ Vector(a), W @ Vector(b), r0, r1, col, ch, seg=seg)
    wb((0, -0.012, -0.055), (0.045, 0.055, 0.12), "soot", rx=-20, bevel=0.35)            # grip
    wb((0, 0.03, -0.015), (0.016, 0.07, 0.008), "gun", bevel=0.3)                        # guard
    wb((0, 0.08, 0.04), (0.1, 0.28, 0.12), "iron", bevel=0.3)                            # receiver
    wb((0, 0.08, 0.105), (0.08, 0.22, 0.02), "teal", bevel=0.3)                          # top plate
    cyl((-0.06, 0.1, -0.03), (0.06, 0.1, -0.03), 0.075, 0.075, "teal", seg=16)          # drum
    for x in (-0.062, 0.062):
        cyl((x, 0.1, -0.03), (x * 1.06, 0.1, -0.03), 0.06, 0.05, "gun", seg=16)
    cyl((0, 0.22, 0.045), (0, 0.56, 0.045), 0.05, 0.054, "soot", seg=12)                 # shroud
    for i in range(4):                                                                   # heat vents
        wb((0, 0.28 + i * 0.07, 0.096), (0.05, 0.03, 0.012), "team", "team_emit", bevel=0.1)
    cyl((0, 0.56, 0.045), (0, 0.6, 0.045), 0.064, 0.064, "iron", seg=12)                 # maw collar
    cyl((0, 0.6, 0.045), (0, 0.63, 0.045), 0.05, 0.05, "team", "team_emit", seg=12)      # glowing throat
    for sz in (1, -1):                                                                   # jaws with teeth
        wb((0, 0.64, 0.045 + sz * 0.045), (0.12, 0.09, 0.035), "iron", rx=sz * 16, bevel=0.3)
        for j in range(3):
            wb(((j - 1) * 0.035, 0.69, 0.045 + sz * 0.028), (0.016, 0.02, 0.022), "bone", rx=sz * 16, bevel=0.2,
               taper=(0.3, 0.3) if sz < 0 else (1.0, 1.0))
    wb((0, 0.06, 0.15), (0.026, 0.16, 0.024), "gun", bevel=0.3)                          # carry handle
    for y in (0.0, 0.12):
        wb((0, y, 0.128), (0.024, 0.024, 0.05), "gun", bevel=0.3)
    wb((-0.07, 0.32, 0.03), (0.04, 0.05, 0.1), "soot", bevel=0.35)                        # side grip
    wb((0, -0.15, 0.03), (0.08, 0.16, 0.1), "teal", bevel=0.35, taper=(0.9, 0.8))          # stock
    wb((0, -0.235, 0.025), (0.085, 0.03, 0.13), "soot", bevel=0.35)
    wb((0.052, 0.08, 0.04), (0.006, 0.2, 0.03), "team", "team", bevel=0.0)


def brannoc_idle(p, ph, f):
    """Personal idle: planted wide like a wall, knees sunk, a slow heavy breath that
    lifts the chest, weight rocking a little from heel to toe."""
    from hero_anims import legs
    w = math.sin(ph)
    b = math.sin(2 * ph)
    legs(p, 0, 0, 0)
    for s, sg in (("L", 1), ("R", -1)):
        p.rot("UpperLeg_" + s, [("x", 9), ("z", -sg * 10), ("y", sg * 6)])
        p.rot("LowerLeg_" + s, [("x", -16)])
        p.rot("Foot_" + s, [("x", 7), ("z", sg * 8)])
    p.rot("Hips", [("x", 1.5 * w)])
    p.hips((0, 0.006 * w * p.k, -0.045 * p.k - 0.006 * b * p.k))
    p.rot("Spine", [("x", 3 + 1.2 * b)])
    p.rot("Chest", [("x", -3 + 1.0 * b)])


def brannoc_post(c):
    """Painted helm detail: chipped edges and scratches on the plates, two dents, a
    breathing-hole grid on the faceplate, a clan mark; brushed iron versus satin teal."""
    import hero_decals as D
    H, k = c["H"], c["k"]
    z0 = H * 0.86
    helm = D.region(c, ["#2F9A90", "#9AA3AD", "#565E69"], zmin=z0)
    D.wear(c, helm, "#D6DCE2", 0.95, scale=55.0)
    D.scratches(c, helm, "#DCE1E6", density=0.55, strength=0.6)
    iron = D.region(c, ["#9AA3AD"], zmin=z0)
    teal = D.region(c, ["#2F9A90"], zmin=z0)
    D.gloss(c, iron, 0.45)
    D.gloss(c, teal, 0.1)
    lo, hi = D.bounds(c, D.region(c, ["#2F9A90"], zmin=z0))
    mid = (lo + hi) / 2
    flo, fhi = D.bounds(c, iron)
    D.decal(c, D.holes(4, 3), (0, fhi[1], mid[2] - (hi[2] - lo[2]) * 0.3), (0, 1, 0), (0, 0, 1),
            (0.07 * k, 0.04 * k), iron, "#15191E", depth=0.08, face=0.3)
    D.decal(c, D.dent(), (0.05 * k, fhi[1], mid[2] - 0.02 * k), (0, 1, 0), (0, 0, 1), (0.04 * k, 0.03 * k), iron,
            "#3B4148", depth=0.08, face=0.2)
    D.decal(c, D.dent(), (-0.06 * k, mid[1], hi[2] - 0.02 * k), (0, 0, 1), (0, 1, 0), (0.045 * k, 0.035 * k), teal,
            "#1C5C56", depth=0.08, face=0.3)
    D.decal(c, D.chevron(n=3), (0, lo[1], mid[2]), (0, -1, 0), (0, 0, 1), (0.06 * k, 0.06 * k), teal, "#E8D9B0",
            depth=0.2)
    body = D.region(c, ["#2F9A90", "#9AA3AD"], zmax=z0)
    D.wear(c, body, "#D6DCE2", 0.7, scale=40.0, seed=11.0)
    D.scratches(c, body, "#DCE1E6", density=0.3, strength=0.4, seed=23.0)
    return c["alb"], c["spec"], c["emit"]


# =========================================================================== Hex
HEX_PAL = {"hoodie": "#5A5686", "lime": "#B6F23A", "shell": "#DCDFEA", "bezel": "#2C2F3D", "screen": "#12262A",
           "chrome": "#C9D4E2", "legs": "#6C6C88", "sneaker": "#E9E9F0", "team": TEAM, "eye": "#101014"}
HEX_SPEC = {"paint": {"head": "hoodie", "torso": "hoodie", "sleeves": "hoodie", "gloves": "hoodie", "legs": "hoodie",
                      "shins": "legs", "boots": "legs", "belt": "lime", "forearm": "hoodie"},
            "shorts_t": 0.55, "boot_t": 0.6, "glove_t": 0.95,
            "torso_shell": {"offset": 0.028, "color": "hoodie", "rim": "lime", "arms": True, "hips": True}}
HEX_FACE = ["..........",
            ".##....##.",
            "#..#..#..#",
            "..........",
            "...#..#...",
            "....##....",
            ".........."]


def hex_parts(h):
    import hero_hd
    k = _k(h)
    lo, hi, hc, hr, eye_z = _head(h)
    skin = hero_hd.BodySkin(h)
    lx = 1.0 if h.jh("UpperLeg_L").x > 0 else -1.0
    # ---------------------------------------------------------------- helmet with a screen face
    C = Vector((0, hc.y + 0.004, hc.z + 0.004))
    R = Vector((hr.x * 1.2, hr.y * 1.14, hr.z * 1.12))
    h.sphere("Head", C, R, "shell", seg=(24, 14), clip=[((0, 0, -0.62), (0, 0, -1))])
    _band(h, "Head", C, R * 1.035, "bezel", seg=(28, 16), x=(-0.74, 0.74), y=(0.25, None), z=(-0.66, 0.52))
    _band(h, "Head", C, R * 1.06, "screen", seg=(28, 16), x=(-0.62, 0.62), y=(0.3, None), z=(-0.55, 0.42))
    for sx in (-1, 1):
        # bezel screws and side vents
        for z in (0.42, -0.5):
            p, n = _on(C, R * 1.035, sx * R.x * 0.68, C.z + R.z * z, 0.001)
            _bolt(h, "Head", p, n, 0.0045 * k, "chrome", "chrome")
        for i in range(3):
            p, n = _side(C, R, sx, C.y + R.y * (0.2 - i * 0.16), C.z - R.z * 0.4, 0.002)
            h.box("Head", p, Vector((0.006, 0.012, 0.045)) * k, "bezel", rot=(0, 0, _yaw(n)), bevel=0.3)
    # ---------------------------------------------------------------- cat-ear headset
    for sx in (-1, 1):
        ep, en = _side(C, R, sx, C.y - R.y * 0.05, C.z + R.z * 0.05)
        h.cyl("Head", ep - en * 0.01, ep + en * 0.03 * k, 0.045 * k, 0.04 * k, "bezel", seg=14)
        h.torus("Head", ep + en * 0.03 * k, en, 0.035 * k, 0.005 * k, "lime", "emit", seg=(14, 4))
        h.cyl("Head", ep + en * 0.03 * k, ep + en * 0.036 * k, 0.026 * k, 0.02 * k, "shell", seg=10)
        base = Vector((sx * R.x * 0.62, C.y - R.y * 0.1, C.z + R.z * 0.8))
        up = Vector((sx * 0.35, 0.05, 1)).normalized()
        h.cyl("Head", base - up * 0.03 * k, base + up * 0.11 * k, 0.05 * k, 0.004, "hoodie", seg=4)      # ear
        h.cyl("Head", base + Vector((0, 0.022, 0)) * k - up * 0.01 * k, base + Vector((0, 0.022, 0)) * k
              + up * 0.08 * k, 0.03 * k, 0.003, "lime", seg=4)                                           # inner
        # antenna on a Sec_ spring, from the ear pod up and out
        a0 = ep + en * 0.02 * k + Vector((0, -0.02, 0.03)) * k
        a1 = a0 + Vector((sx * 0.07, -0.05, 0.22)) * k
        h.cyl("Head", a0, a1, 0.005 * k, 0.003 * k, "chrome", "chrome", seg=6)
        h.sphere("Head", a1, Vector((0.012, 0.012, 0.012)) * k, "team", "team_emit", seg=(8, 5))
    # ---------------------------------------------------------------- hood over the helmet
    HC = C + Vector((0, -0.016, 0.006))
    HR = Vector((R.x * 1.22, R.y * 1.2, R.z * 1.15))
    cut = ((0, 0.42, 0), (0, 1, -0.28))
    h.sphere("Head", HC, HR, "hoodie", seg=(22, 14), clip=[cut, ((0, 0, -0.8), (0, 0, -1))])
    h.sphere("Head", HC, HR * 1.025, "lime", seg=(22, 14),
             clip=[cut, ((0, 0, -0.8), (0, 0, -1)), ((0, 0.33, 0), (0, -1, 0.28))])          # hood rim trim
    # drawstrings, chest patch
    nk = h.jh("Neck")
    for sx in (-1, 1):
        p, n = h.surface(sx * 0.04 * k, nk.z - 0.06 * k, 1)
        h.cyl("UpperChest", p + n * 0.03, p + n * 0.03 - Vector((0, 0, 0.15)) * k, 0.006, 0.006, "lime", seg=4)
        h.sphere("UpperChest", p + n * 0.03 - Vector((0, 0, 0.16)) * k, Vector((0.01, 0.01, 0.014)) * k, "chrome",
                 "chrome", seg=(6, 4))
    p, n = h.surface(-lx * 0.09 * k, h.jh("Chest").z, 1)
    h.box("Chest", p + n * 0.03, (0.07 * k, 0.01, 0.06 * k), "team", "team", bevel=0.2)
    # ---------------------------------------------------------------- wrist decks + holo panels
    for s in ("L", "R"):
        sg = 1.0 if h.jh("UpperArm_" + s).x > 0 else -1.0
        w = h.jl("LowerArm_" + s, 0.75)
        h.box("LowerArm_" + s, w + Vector((0, 0, 0.04)) * k, Vector((0.075, 0.09, 0.028)) * k, "shell", bevel=0.35)
        h.box("LowerArm_" + s, w + Vector((0, 0, 0.056)) * k, Vector((0.05, 0.06, 0.006)) * k, "lime", "emit",
              bevel=0.2)
        h.box("LowerArm_" + s, w + Vector((sg * 0.09, 0.02, 0.1)) * k, Vector((0.004, 0.11, 0.08)) * k, "team",
              "team_emit", bevel=0.0)
    # ---------------------------------------------------------------- belt with a battery cell, sneakers
    pts = hero_hd.ring(h, Vector((0, h.jh("Hips").y, h.belt_z)), (0, 0, 1), ("Hips", "Spine"), n=32, off=0.01)
    hero_hd.strap(h, pts, (0, 0, 1), 0.04 * k, 0.012, "lime", skin)
    q, d = min(pts, key=lambda pd: pd[1].y)
    h.cyl("Hips", q + d * 0.02 + Vector((-0.06 * k, 0, 0)), q + d * 0.02 + Vector((0.06 * k, 0, 0)), 0.03 * k,
          0.03 * k, "shell", seg=10)
    h.box("Hips", q + d * 0.052, Vector((0.08, 0.006, 0.02)) * k, "lime", "emit", bevel=0.2)
    for s in ("L", "R"):
        lo_, hi_ = h.bbox("Foot_" + s, 0.4)
        c = (lo_ + hi_) / 2
        sz = hi_ - lo_
        h.box("Foot_" + s, (c.x, c.y + 0.02, lo_.z + sz.z * 0.55), (sz.x + 0.05, sz.y + 0.07, sz.z + 0.04), "sneaker",
              bevel=0.6, taper=(0.9, 0.75))
        h.box("Foot_" + s, (c.x, c.y + 0.02, lo_.z + 0.01), (sz.x + 0.056, sz.y + 0.076, 0.03), "lime", bevel=0.4)
    _springs(h, [("Sec_antenna_%s" % s, "Head", 2, "bottom",
                  _sel({"chrome", "team"}, {"Head"}, lambda co, sx=sx: co.z > C.z + R.z * 0.35 and co.x * sx > R.x * 0.5
                       and co.y < C.y + 0.01))
                 for s, sx in (("L", lx), ("R", -lx))])


def glitchcaster_w16(h, W):
    """Hex's own Glitchcaster (W16): a compact hacker caster. A shell-white receiver
    with a little screen on its flank, three lime coil rings, a prong emitter, a holo
    sight panel, a battery cell and a cable loop to the grip. Weapon space: origin =
    right grip, +Y barrel, +Z up."""
    def wb(c, s, col, ch="flat", **kw):
        h.box("Weapon", None, s, col, ch, mat=W @ Matrix.Translation(Vector(c)) @ _rx(kw.pop("rx", 0)), **kw)

    def cyl(a, b, r0, r1, col, ch="flat", seg=10):
        h.cyl("Weapon", W @ Vector(a), W @ Vector(b), r0, r1, col, ch, seg=seg)
    wb((0, -0.01, -0.045), (0.032, 0.042, 0.095), "bezel", rx=-15, bevel=0.35)            # grip
    wb((0, 0.05, 0.03), (0.062, 0.19, 0.085), "shell", bevel=0.4)                         # receiver
    wb((0.032, 0.05, 0.035), (0.004, 0.11, 0.05), "screen", bevel=0.2)                    # flank screen
    wb((0.0345, 0.05, 0.035), (0.002, 0.08, 0.008), "lime", "emit", bevel=0.0)            # waveform line
    cyl((0, 0.14, 0.035), (0, 0.32, 0.035), 0.016, 0.014, "bezel", seg=8)                 # core rod
    for i in range(3):                                                                    # coil rings
        h.torus("Weapon", W @ Vector((0, 0.17 + i * 0.05, 0.035)), W.to_3x3() @ Vector((0, 1, 0)), 0.03, 0.008,
                "lime", "emit", seg=(14, 5))
    for a in range(3):                                                                    # prong emitter
        ang = math.radians(90 + a * 120)
        o = Vector((math.cos(ang) * 0.022, 0, math.sin(ang) * 0.022 + 0.035))
        cyl(tuple(o + Vector((0, 0.31, 0))), tuple(o * 1.4 + Vector((0, 0.39, -0.014))), 0.007, 0.003, "chrome",
            "chrome", seg=5)
    h.sphere("Weapon", W @ Vector((0, 0.36, 0.035)), (0.014, 0.014, 0.014), "team", "team_emit", seg=(8, 5))
    wb((0, 0.04, 0.1), (0.05, 0.004, 0.04), "team", "team_emit", bevel=0.0)              # holo sight
    wb((0, 0.04, 0.078), (0.012, 0.012, 0.012), "bezel", bevel=0.3)
    cyl((-0.035, -0.06, 0.02), (0.035, -0.06, 0.02), 0.03, 0.03, "lime", seg=10)          # battery cell
    wb((0, -0.06, 0.02), (0.075, 0.018, 0.04), "bezel", bevel=0.3)
    wb((0, 0.05, -0.06), (0.03, 0.05, 0.08), "bezel", rx=10, bevel=0.3)                    # fore stub
    wb((-0.032, 0.07, 0.04), (0.004, 0.05, 0.03), "team", "team", bevel=0.0)


def hex_idle(p, ph, f):
    """Personal idle: restless. Hip popped onto the left leg, right knee loose, a toe
    tap on the right foot and a small head-bob bounce in the hips."""
    from hero_anims import legs
    w = math.sin(ph)
    tap = max(0.0, math.sin(4 * ph))
    legs(p, 0, 0, 0)
    p.rot("UpperLeg_L", [("x", 2), ("z", -4), ("y", 3)])
    p.rot("UpperLeg_R", [("x", 12), ("z", 10), ("y", -12)])
    p.rot("LowerLeg_L", [("x", -4)])
    p.rot("LowerLeg_R", [("x", -20)])
    p.rot("Foot_R", [("x", -6 + 10 * tap), ("z", 10)])
    p.rot("Hips", [("y", -6 + 1.0 * w), ("z", 8)])
    p.hips((-0.035 * p.k, 0, -0.012 * p.k - 0.006 * abs(math.sin(2 * ph)) * p.k))
    p.rot("Spine", [("y", 5 - 0.8 * w), ("x", 4), ("z", -5)])
    p.rot("Chest", [("x", 3), ("y", 2)])


def hex_post(c):
    """Painted head detail: the emissive pixel face and scanlines on the screen, glossy
    screen and plastic shell, matte hood; light wear, a sticker and a hazard tab."""
    import hero_decals as D
    H, k = c["H"], c["k"]
    z0 = H * 0.82
    scr = D.region(c, ["#12262A"], zmin=z0)
    lo, hi = D.bounds(c, scr)
    mid = (lo + hi) / 2
    sz = hi - lo
    D.decal(c, D.pixel_face(HEX_FACE), (0, hi[1], mid[2] - sz[2] * 0.02), (0, 1, 0), (0, 0, 1),
            (sz[0] * 0.86, sz[2] * 0.78), scr, "#B6F23A", emit=True, depth=0.08, face=0.2)
    lines = D.canvas(4, 64)
    lines[::4, :] = 0.35
    D.decal(c, lines, (0, hi[1], mid[2]), (0, 1, 0), (0, 0, 1), (sz[0] * 1.1, sz[2] * 1.1), scr, "#1F3A38",
            depth=0.08, face=0.2)
    D.gloss(c, scr, 0.9)
    shell = D.region(c, ["#DCDFEA"], zmin=z0)
    D.gloss(c, shell, 0.35)
    D.wear(c, shell, "#8A8FA0", 0.5, scale=60.0)
    D.scratches(c, shell, "#9AA0B2", density=0.35, strength=0.45)
    bez = D.region(c, ["#2C2F3D"], zmin=z0)
    D.gloss(c, bez, 0.3)
    D.decal(c, D.stripes(3), (0, mid[1], lo[2] - 0.01 * k), (0, 1, 0), (0, 0, 1), (0.04 * k, 0.012 * k), bez,
            "#B6F23A", depth=0.08, face=0.2)
    slo, shi = D.bounds(c, shell)
    D.decal(c, D.chevron(n=1), (0, slo[1] + 0.005, (slo[2] + shi[2]) / 2), (0, -1, 0), (0, 0, 1), (0.04 * k, 0.03 * k),
            shell, "#B6F23A", depth=0.2)
    D.gloss(c, D.region(c, ["#5A5686"], zmin=z0), 0.0)
    return c["alb"], c["spec"], c["emit"]


HEROES = {
    "ryker": {
        "key": "ryker",
        "pipeline": "gen",
        "legacy": hero_defs.HEROES["ryker"],
        "height": 1.85,
        "body": {"leg": 0.93, "torso": 0.58, "shoulder_w": 0.5, "chest_w": 0.41, "chest_d": 0.26,
                 "waist_w": 0.28, "waist_d": 0.2, "hip_w": 0.34, "hip_d": 0.22, "hip_joint_w": 0.2,
                 "neck": 0.07, "neck_r": 0.066, "head_w": 0.155, "head_d": 0.19, "head_h": 0.22,
                 "arm_r": 0.064, "forearm_r": 0.06, "wrist_r": 0.04, "thigh_r": 0.098, "knee_r": 0.066,
                 "calf_r": 0.074, "ankle_r": 0.048, "hand": 1.4, "foot": 1.35, "boot_r": 1.3,
                 "deltoid": 1.2, "pecs": 0.7, "glutes": 0.5, "calves": 0.7, "forearms": 0.8, "traps": 0.9,
                 "chest_lift": 0.016, "arm_angle": 50.0, "stance": 0.03},
        "paint": {"hatch_density": 0.5, "hatch_threshold": -0.05, "post": ryker_post, "uv_margin": 0.0012, "uv_max_tries": 40,
                  "shader": {"hatch_strength": 0.1}},
        "palette": RYKER_PAL,
        "cuts": ryker_cuts,
        "regions": ryker_regions,
        "shells": hero_defs.HEROES["ryker"]["shells"],
        "parts": ryker_parts,
        "weapon": "breakline_ar7",
        "cloth": [],
        "stance": {"grip_r": (0.10, 0.22, 1.25), "pivot": (0.14, 0.02, 1.42), "twist": -28, "clav_l": -10,
                   "pole_r": (1, -0.4, -1), "pole_l": (-0.6, -0.2, -1), "two_handed": True,
                   "grip_l": (0, 0.30, -0.005), "hand_r_y": (0, 0.55, -1), "hand_r_n": (-1, 0, 0),
                   "hand_l_y": (1, 0.25, 0.1), "hand_l_n": (0, 0, 1), "mag": (0, 0.12, -0.12)},
        "idle": ryker_idle,
        "gait": {"run_amp": 40, "lean": 9},
        "casts": [("throw", [("z", 12)]), ("inject", []), ("thrust", [("x", -6)]), ("raise", [("x", 8)])],
    },
    "brannoc": {
        "key": "brannoc",
        "pipeline": "gen",
        "legacy": hero_defs.HEROES["brannoc"],
        "height": 2.2,
        "body": {"leg": 0.92, "torso": 0.6, "shoulder_w": 0.6, "chest_w": 0.52, "chest_d": 0.33,
                 "waist_w": 0.42, "waist_d": 0.3, "hip_w": 0.42, "hip_d": 0.28, "hip_joint_w": 0.22,
                 "neck": 0.05, "neck_r": 0.08, "head_w": 0.145, "head_d": 0.175, "head_h": 0.2,
                 "upper_arm": 0.29, "forearm": 0.27,
                 "arm_r": 0.08, "forearm_r": 0.078, "wrist_r": 0.05, "thigh_r": 0.118, "knee_r": 0.08,
                 "calf_r": 0.09, "ankle_r": 0.06, "hand": 1.55, "foot": 1.4, "boot_r": 1.35,
                 "deltoid": 1.3, "pecs": 0.9, "glutes": 0.5, "calves": 0.8, "forearms": 1.0, "traps": 1.4,
                 "boxy": 2.8, "chest_lift": 0.02, "arm_angle": 46.0, "stance": 0.06},
        "paint": {"hatch_density": 0.5, "hatch_threshold": -0.05, "post": brannoc_post, "uv_margin": 0.0012,
                  "uv_max_tries": 40, "shader": {"hatch_strength": 0.1}},
        "palette": BRANNOC_PAL,
        "cuts": _generic(BRANNOC_SPEC)[0],
        "regions": _generic(BRANNOC_SPEC)[1],
        "shells": _generic(BRANNOC_SPEC)[2],
        "parts": brannoc_parts,
        "weapon": "ironmaw_w16",
        "cloth": [],
        # Two-handed at belly / low chest (v0.10 held it at the thighs).
        "stance": {"grip_r": (0.14, 0.27, 1.17), "pivot": (0.16, 0.02, 1.36), "twist": -18, "clav_l": -8,
                   "pole_r": (1, -0.4, -1), "pole_l": (-0.6, -0.2, -1), "two_handed": True,
                   "grip_l": (-0.07, 0.32, 0.03), "hand_r_y": (0, 0.55, -1), "hand_r_n": (-1, 0, 0),
                   "hand_l_y": (0.3, 0.3, -1), "hand_l_n": (1, 0, 0), "mag": (0, 0.1, -0.06)},
        "idle": brannoc_idle,
        "gait": {"run_amp": 34, "lean": 5},
        "casts": [("thrust", [("x", -8)]), ("raise", []), ("sweep", [("z", 10)]), ("raise", [("x", 10)])],
    },
    "hex": {
        "key": "hex",
        "pipeline": "gen",
        "legacy": hero_defs.HEROES["hex"],
        "height": 1.72,
        "body": {"leg": 0.97, "torso": 0.54, "shoulder_w": 0.4, "chest_w": 0.32, "chest_d": 0.21,
                 "waist_w": 0.25, "waist_d": 0.18, "hip_w": 0.31, "hip_d": 0.2, "hip_joint_w": 0.18,
                 "neck": 0.07, "neck_r": 0.05, "head_w": 0.17, "head_d": 0.2, "head_h": 0.24,
                 "arm_r": 0.05, "forearm_r": 0.046, "wrist_r": 0.034, "thigh_r": 0.08, "knee_r": 0.055,
                 "calf_r": 0.062, "ankle_r": 0.04, "hand": 1.35, "foot": 1.45, "boot_r": 1.2,
                 "deltoid": 0.6, "pecs": 0.2, "glutes": 0.4, "calves": 0.4, "forearms": 0.3, "traps": 0.3,
                 "chest_lean": 4.0, "head_fwd": 0.015, "arm_angle": 52.0},
        "paint": {"hatch_density": 0.5, "hatch_threshold": -0.05, "post": hex_post, "uv_margin": 0.0012,
                  "uv_max_tries": 40, "shader": {"hatch_strength": 0.1}},
        "palette": HEX_PAL,
        "cuts": _generic(HEX_SPEC)[0],
        "regions": _generic(HEX_SPEC)[1],
        "shells": _generic(HEX_SPEC)[2],
        "parts": hex_parts,
        "weapon": "glitchcaster_w16",
        "cloth": [],
        "stance": {"grip_r": (0.1, 0.27, 1.12), "pivot": (0.12, 0.04, 1.32), "twist": -16, "clav_l": -8,
                   "pole_r": (1, -0.4, -1), "pole_l": (-0.6, -0.2, -1), "two_handed": True,
                   "grip_l": (0, 0.06, -0.06), "hand_r_y": (0, 0.55, -1), "hand_r_n": (-1, 0, 0),
                   "hand_l_y": (0.3, 0.3, -1), "hand_l_n": (1, 0, 0), "mag": (0, 0.05, -0.08)},
        "idle": hex_idle,
        "gait": {"run_amp": 40, "lean": 10},
        "casts": [("thrust", []), ("sweep", [("z", 12)]), ("throw", [("z", 8)]), ("raise", [("x", 10)])],
    },
}

WEAPONS = {"breakline_ar7": breakline_ar7, "ironmaw_w16": ironmaw_w16, "glitchcaster_w16": glitchcaster_w16}
