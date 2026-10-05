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
    """A hex bolt head standing on the surface (p, n)."""
    h.cyl(bone, p - n * 0.002, p + n * r * 0.9, r, r * 0.8, col, ch, seg=6)


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
    for i in range(3):  # MOLLE rows
        h.box("UpperChest", plate + Vector((0, 0.02, -0.08 + i * 0.04)) * k, Vector((0.26, 0.008, 0.012)) * k,
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
    for i in range(6):                                                                  # top rail teeth
        wb((0, 0.0 + i * 0.045, 0.108), (0.03, 0.022, 0.012), "gun", bevel=0.15)
    wb((0, 0.04, 0.135), (0.04, 0.07, 0.04), "gun", bevel=0.3)                          # holo sight body
    wb((0, 0.072, 0.15), (0.044, 0.008, 0.05), "rubber", bevel=0.2)                    # hood
    wb((0, 0.074, 0.15), (0.03, 0.006, 0.032), "team", "team_emit", bevel=0.0)        # lens
    wb((0, 0.33, 0.045), (0.07, 0.24, 0.08), "olive", bevel=0.35, taper=(0.9, 1.0))     # handguard slab
    for i in range(4):                                                                  # vent cuts
        for sx in (-1, 1):
            wb((sx * 0.036, 0.25 + i * 0.05, 0.055), (0.004, 0.03, 0.012), "rubber", bevel=0.1)
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
    D.gloss(c, D.region(c, ["#6F8C45"], zmin=z0), 0.28)
    D.gloss(c, D.region(c, ["#1D3A55"], zmin=z0), 0.95)
    D.gloss(c, D.region(c, ["#4C5564"], zmin=z0), 0.6)
    olive = D.region(c, ["#6F8C45"], zmin=z0)
    top = H * 0.955
    lx = -1.0  # body_gen: the hero's left is -X
    D.decal(c, D.digits("07"), (-lx * 0.11 * k, -0.035 * k, top - 0.03 * k), (-lx, 0, 0), (0, 0, 1),
            (0.07 * k, 0.045 * k), olive, "#EAD49C", depth=0.06)
    D.decal(c, D.tally(5), (lx * 0.11 * k, -0.045 * k, top - 0.03 * k), (lx, 0, 0), (0, 0, 1),
            (0.07 * k, 0.035 * k), olive, "#EAD49C", depth=0.06)
    D.decal(c, D.chevron(n=2), (0, 0.06 * k, top + 0.02 * k), (0, 0.3, 1), (0, 1, 0), (0.06 * k, 0.05 * k), olive,
            "#EAD49C", depth=0.06, face=0.2)
    jaw = D.region(c, ["#3E4F6A"], zmin=z0 - 0.04 * k)
    D.decal(c, D.stripes(3), (lx * 0.035 * k, 0.12 * k, H * 0.87), (0, 1, 0), (0, 0, 1), (0.035 * k, 0.025 * k), jaw,
            "#E8B23A", depth=0.08, face=0.3)
    D.scratches(c, D.region(c, ["#6F8C45", "#4C5564"], zmax=z0), "#C9C4AE", density=0.25, strength=0.4, seed=19.0)
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
        "paint": {"hatch_density": 0.5, "hatch_threshold": -0.05, "post": ryker_post,
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
}

WEAPONS = {"breakline_ar7": breakline_ar7}
