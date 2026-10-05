"""Per-hero definitions for tools/art/build_hero.py (design/art/hero-art-bible.md §4).

Space: Blender metres, X = character right, Y = forward, Z = up, feet at Z = 0.
Weapon parts are in weapon space: origin at the right grip, +Y = barrel, +Z = up.
Region / shell callbacks receive (hero, face centre, dominant bone, normal).
"""
import math

from mathutils import Matrix, Vector

TEAM = "#FFFFFF"  # team channels are recoloured by the shader


def _along(a, b, up=Vector((0, 0, 1))):
    """Matrix whose +Y runs a->b, +Z ~ `up`, origin at the midpoint."""
    a, b = Vector(a), Vector(b)
    y = (b - a).normalized()
    z = (up - y * y.dot(up)).normalized()
    x = y.cross(z)
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = (a + b) / 2
    return m


def _wz(h, z, bands):
    """Weights by height: bands = [(z_top, bone), ...] high -> low, linear between."""
    for (z0, b0), (z1, b1) in zip(bands, bands[1:]):
        if z >= z1:
            t = 0.0 if z >= z0 else (z0 - z) / max(z0 - z1, 1e-6)
            return {b0: 1 - t, b1: t} if b0 != b1 else {b0: 1.0}
    return {bands[-1][1]: 1.0}


# ======================================================================== Ryker
def ryker_cuts(h):
    cuts = []
    for s in ("L", "R"):
        cuts.append(({"LowerArm_" + s, "Hand_" + s}, *h.cut("LowerArm_" + s, 0.80)))
        cuts.append(({"LowerLeg_" + s, "Foot_" + s}, *h.cut("LowerLeg_" + s, 0.50)))
        cuts.append(({"UpperLeg_" + s, "LowerLeg_" + s}, *h.cut("UpperLeg_" + s, 0.15)))
    cuts.append(({"LowerArm_R", "UpperArm_R"}, *h.cut("LowerArm_R", 0.12)))
    cuts.append(({"Neck", "Head", "UpperChest"}, *h.cut("Neck", 0.35)))
    zb = h.jh("Hips").z + 0.1 * h.d["height"] / 1.85
    for dz in (-0.035, 0.035):
        cuts.append(({"Hips", "Spine", "UpperLeg_L", "UpperLeg_R"}, Vector((0, 0, zb + dz)), Vector((0, 0, 1))))
    h.belt_z = zb
    return cuts


def ryker_regions(h, c, bone, n):
    if bone in ("Head", "Neck") and h.side("Neck", 0.35, c) > 0:
        return "skin", "skin"
    if bone.startswith("Hand") or (bone.startswith("LowerArm") and h.side(bone, 0.80, c) > 0):
        return "rubber", "flat"
    if bone == "LowerArm_R" and h.side(bone, 0.12, c) > 0:
        return "chrome", "chrome"
    if bone.startswith("Foot") or (bone.startswith("LowerLeg") and h.side(bone, 0.5, c) > 0):
        return "rubber", "flat"
    if abs(c.z - h.belt_z) < 0.035 and bone in ("Hips", "Spine", "UpperLeg_L", "UpperLeg_R"):
        return "rubber", "flat"
    return "suit", "flat"


def _vest_pick(h, c, bone, n):
    if bone not in ("Spine", "Chest", "UpperChest", "Clavicle_L", "Clavicle_R", "Neck"):
        return False
    if bone == "Neck" and h.side("Neck", 0.35, c) > 0:
        return False
    sh = h.jh("UpperArm_R").x
    return c.z > h.belt_z + 0.04 and abs(c.x) < sh * 0.92


def _thigh_pick(h, c, bone, n):
    return bone.startswith("UpperLeg") and h.side(bone, 0.15, c) > 0 and h.side(bone, 0.9, c) < 0 and n.y > 0.1


def _boot_pick(h, c, bone, n):
    return bone.startswith("Foot") or (bone.startswith("LowerLeg") and h.side(bone, 0.5, c) > 0)


def _vest_paint(h, c):
    if c.y > 0 and abs(c.z - (h.jh("UpperChest").z + 0.02)) < 0.022:
        return "team", "team"
    return "olive", "flat"


def ryker_parts(h):
    k = h.d["height"] / 1.85
    lo, hi = h.bbox("Head")
    hc = (lo + hi) / 2
    hr = (hi - lo) / 2
    eye_z = (h.eye("L").z + h.eye("R").z) / 2
    front = hi.y
    # Closed helmet with a horizontal visor bar.
    hcen = Vector((0, hc.y - 0.004, hc.z + 0.012))
    rad = Vector((hr.x * 1.2, hr.y * 1.12, hr.z * 1.08))
    h.sphere("Head", hcen, rad, "olive", seg=(16, 10), clip=[((0, 0, -0.62), (0, 0, -1))])
    h.sphere("Head", hcen + Vector((0, 0, 0.012)), rad * 1.03, "bone", seg=(16, 10),
             clip=[((0, 0, 0.55), (0, 0, -1)), ((0.28, 0, 0), (1, 0, 0)), ((-0.28, 0, 0), (-1, 0, 0))])
    h.box("Head", (0, front + 0.012, eye_z + 0.004), (hr.x * 2.05, 0.05, 0.042), "team", "team_emit", bevel=0.4)
    h.box("Head", (0, front - 0.004, eye_z - 0.055), (hr.x * 1.6, 0.06, 0.07), "suit", taper=(1.1, 1.0), bevel=0.4)
    h.box("Head", (0, front + 0.02, eye_z - 0.075), (0.05, 0.03, 0.03), "rubber", bevel=0.3)
    for s in (-1, 1):
        h.cyl("Head", (s * hr.x * 1.05, hc.y, eye_z), (s * hr.x * 1.28, hc.y, eye_z), 0.03, 0.026, "suit", seg=10)
    # Oversized LEFT pauldron (the hook) with an antenna fin and kill-tally tape.
    sh = h.jh("UpperArm_L")
    pc = sh + Vector((-0.02, -0.005, 0.045)) * k
    h.sphere("Clavicle_L", pc, Vector((0.15, 0.155, 0.12)) * k, "bone", seg=(14, 8), rot=(0, -22, 0),
             clip=[((0, 0, -0.18), (0, 0, -1))])
    h.sphere("Clavicle_L", pc + Vector((-0.012, 0, -0.03)) * k, Vector((0.16, 0.165, 0.10)) * k, "olive", seg=(14, 8),
             rot=(0, -22, 0), clip=[((0, 0, -0.2), (0, 0, -1)), ((0, 0, 0.25), (0, 0, 1))])
    h.box("Clavicle_L", pc + Vector((-0.04, 0.0, 0.11)) * k, Vector((0.016, 0.07, 0.24)) * k, "olive",
          rot=(-12, -22, 0), taper=(0.5, 0.35), bevel=0.3)
    h.box("Clavicle_L", pc + Vector((-0.045, 0.0, 0.23)) * k, Vector((0.02, 0.02, 0.03)) * k, "team", "team_emit",
          rot=(-12, -22, 0), bevel=0.3)
    h.box("Clavicle_L", pc + Vector((-0.02, 0.105, 0.06)) * k, Vector((0.17, 0.03, 0.035)) * k, "team", "team",
          rot=(-30, -22, 0), bevel=0.2)
    h.box("Clavicle_L", pc + Vector((-0.11, 0.0, 0.04)) * k, Vector((0.012, 0.12, 0.03)) * k, "tape", rot=(0, -60, 0),
          bevel=0.2)
    # Grenade bandolier across the chest (left shoulder -> right hip), on the vest surface.
    a = (-0.11 * k, h.jh("Clavicle_L").z + 0.02)
    b = (0.14 * k, h.belt_z + 0.03)
    pts = []
    for i in range(8):
        t = i / 7
        x, z = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
        p, n = h.surface(x, z, 1)
        pts.append((p + n * 0.035 * k, n))
    bands = [(h.jh("UpperChest").z, "UpperChest"), (h.jh("Chest").z, "Chest"), (h.jh("Spine").z, "Spine")]
    for (p0, n0), (p1, _) in zip(pts, pts[1:]):
        m = _along(p0, p1, n0)
        h.box(None, None, ((p1 - p0).length + 0.01, 0.05 * k, 0.014 * k), "rubber", mat=_along_box(p0, p1, n0),
              weights=lambda co: _wz(h, co.z, bands))
    for i in (2, 4, 6):
        p, n = pts[i]
        h.sphere(None, p + n * 0.02 * k, Vector((0.026, 0.026, 0.034)) * k, "olive", seg=(8, 6),
                 weights=lambda co: _wz(h, co.z, bands))
        h.box(None, p + n * 0.02 * k + Vector((0, 0, 0.026 * k)), Vector((0.02, 0.02, 0.012)) * k, "team", "team",
              weights=lambda co: _wz(h, co.z, bands))
    # Belt pouches, knee pads, stim port, small back pack.
    for x in (-0.13, -0.06, 0.08):
        p, n = h.surface(x * k, h.belt_z - 0.01, 1)
        h.box("Hips", p + n * 0.03 * k, Vector((0.055, 0.035, 0.065)) * k, "olive", bevel=0.35)
    for s in ("L", "R"):
        kn = h.jh("LowerLeg_" + s)
        h.box("LowerLeg_" + s, kn + Vector((0, 0.065, -0.02)) * k, Vector((0.09, 0.04, 0.11)) * k, "bone", bevel=0.45,
              taper=(0.8, 0.8))
    ep = h.jl("LowerArm_R", 0.45)
    h.torus("LowerArm_R", ep, h.jt("LowerArm_R") - h.jh("LowerArm_R"), 0.042 * k, 0.009 * k, "team", "team_emit")
    p, n = h.surface(0, h.jh("UpperChest").z - 0.05, -1)
    h.box("UpperChest", p + Vector((0, -0.07, 0)) * k, Vector((0.24, 0.12, 0.28)) * k, "suit", bevel=0.3)
    h.box("UpperChest", p + Vector((0, -0.135, 0.03)) * k, Vector((0.2, 0.02, 0.05)) * k, "olive", bevel=0.3)


def _along_box(a, b, n):
    """Box matrix: X along a->b (strap length), Z = surface normal."""
    a, b = Vector(a), Vector(b)
    x = (b - a).normalized()
    z = (n - x * x.dot(n)).normalized()
    y = z.cross(x)
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = (a + b) / 2
    return m


def breakline(h, W):
    def wb(c, s, col, ch="flat", **kw):
        h.box("Weapon", None, s, col, ch, mat=W @ Matrix.Translation(Vector(c)) @ _rx(kw.pop("rx", 0)), **kw)

    wb((0, -0.012, -0.045), (0.032, 0.042, 0.10), "rubber", rx=-18, bevel=0.3)
    wb((0, 0.07, 0.035), (0.058, 0.30, 0.095), "suit", bevel=0.25)
    wb((0, 0.33, 0.04), (0.064, 0.24, 0.075), "olive", bevel=0.35, taper=(0.85, 1.0))
    h.cyl("Weapon", W @ Vector((0, 0.44, 0.045)), W @ Vector((0, 0.62, 0.045)), 0.015, 0.015, "suit", seg=8)
    h.cyl("Weapon", W @ Vector((0, 0.60, 0.045)), W @ Vector((0, 0.67, 0.045)), 0.024, 0.022, "rubber", seg=8)
    wb((0, 0.12, -0.075), (0.036, 0.075, 0.17), "rubber", rx=14, bevel=0.3)
    wb((0, -0.17, 0.03), (0.045, 0.22, 0.085), "olive", bevel=0.35, taper=(0.9, 0.7))
    wb((0, -0.275, 0.02), (0.05, 0.03, 0.12), "rubber", bevel=0.3)
    wb((0, 0.17, 0.092), (0.03, 0.34, 0.014), "suit", bevel=0.2)
    h.cyl("Weapon", W @ Vector((0, 0.0, 0.125)), W @ Vector((0, 0.15, 0.125)), 0.024, 0.024, "suit", seg=10)
    h.cyl("Weapon", W @ Vector((0, 0.15, 0.125)), W @ Vector((0, 0.16, 0.125)), 0.02, 0.02, "team", "team_emit", seg=10)
    wb((0.031, 0.06, 0.035), (0.006, 0.11, 0.03), "team", "team", bevel=0.0)
    wb((-0.031, 0.06, 0.035), (0.006, 0.11, 0.03), "team", "team", bevel=0.0)


def _rx(deg):
    return Matrix.Rotation(math.radians(deg), 4, "X")


# ======================================================================== Vesper
def vesper_cuts(h):
    cuts = []
    for s in ("L", "R"):
        for t in (0.72, 0.84):
            cuts.append(({"LowerArm_" + s, "Hand_" + s}, *h.cut("LowerArm_" + s, t)))
        cuts.append(({"LowerLeg_" + s, "Foot_" + s, "UpperLeg_" + s}, *h.cut("LowerLeg_" + s, 0.12)))
        cuts.append(({"Hand_" + s}, *h.cut("Hand_" + s, 0.95)))
    cuts.append(({"Neck", "Head", "UpperChest"}, *h.cut("Neck", 0.2)))
    zw = h.jh("Spine").z + 0.02
    for dz in (-0.05, 0.05):
        cuts.append(({"Hips", "Spine", "Chest"}, Vector((0, 0, zw + dz)), Vector((0, 0, 1))))
    h.waist_z = zw
    return cuts


def vesper_regions(h, c, bone, n):
    if bone in ("Head", "Neck") and h.side("Neck", 0.2, c) > 0:
        return "skin", "skin"
    if bone.startswith("Hand"):
        return ("chrome", "chrome") if h.side(bone, 0.95, c) > 0 else ("ink", "flat")
    if bone.startswith("LowerArm"):
        if h.side(bone, 0.84, c) > 0:
            return "ink", "flat"
        if h.side(bone, 0.72, c) > 0:
            return "gold", "flat"
        return "plum", "flat"
    if bone.startswith("UpperArm") or bone.startswith("Clavicle"):
        return "plum", "flat"
    if abs(c.z - h.waist_z) < 0.05 and bone in ("Hips", "Spine", "Chest"):
        return "gold" if abs(c.z - h.waist_z) > 0.035 else "ink", "flat"
    if bone.startswith("Foot") or (bone.startswith("LowerLeg") and h.side(bone, 0.12, c) > 0):
        return "plum", "flat"
    return "ink", "flat"


def _coat_pick(h, c, bone, n):
    if bone not in ("Chest", "UpperChest", "Clavicle_L", "Clavicle_R", "Spine", "Neck"):
        return False
    if bone == "Neck" and h.side("Neck", 0.2, c) > 0:
        return False
    return c.z > h.waist_z + 0.05


def _vboot_pick(h, c, bone, n):
    return bone.startswith("Foot") or (bone.startswith("LowerLeg") and h.side(bone, 0.12, c) > 0)


def vesper_parts(h):
    k = h.d["height"] / 1.88
    lo, hi = h.bbox("Head")
    hc = (lo + hi) / 2
    hr = (hi - lo) / 2
    eye_z = (h.eye("L").z + h.eye("R").z) / 2
    # Sharp A-line bob: skull cap cut open at the face, bottom slanted (longer at the front).
    bc = Vector((0, hc.y - 0.006, hc.z + 0.01))
    h.sphere("Head", bc, Vector((hr.x * 1.18, hr.y * 1.12, hr.z * 1.1)), "hair", seg=(18, 12),
             clip=[((0, 0.5, -0.12), (0, 1, -0.9)), ((0, 0, -0.62), (0, -0.35, -1))])
    h.box("Head", (0, hi.y - 0.01, eye_z + 0.05), (hr.x * 1.9, 0.035, 0.03), "hair", rot=(18, 0, 0), bevel=0.4)
    # Gold-wrapped braid down the back (head -> neck -> upper chest).
    top = Vector((-0.04 * k, lo.y - 0.005, hc.z - 0.02))
    bands = [(hc.z, "Head"), (h.jh("Neck").z, "Neck"), (h.jh("UpperChest").z, "UpperChest"), (h.jh("Chest").z, "Chest")]
    prev = top
    for i in range(7):
        p, nrm = h.surface(-0.05 * k, top.z - 0.07 * (i + 1) * k, -1)
        p = p + nrm * 0.035 * k if i > 0 else p + nrm * 0.03 * k
        col = "gold" if i % 2 == 1 else "hair"
        h.sphere(None, (prev + p) / 2, Vector((0.03, 0.03, 0.045)) * k * (1.0 - i * 0.05), col, seg=(8, 6),
                 weights=lambda co: _wz(h, co.z, bands))
        prev = p
    # High wide collar: outer plum shell + team lining, open at the front.
    nb = h.jh("Neck")
    z0, z1 = nb.z - 0.04 * k, eye_z - 0.03 * k
    clip = [((0, 0.7, 0), (0, 1, 0))]
    h.cyl("UpperChest", (0, nb.y - 0.01, z0), (0, nb.y - 0.03, z1), 0.12 * k, 0.17 * k, "plum", seg=16, caps=False, clip=clip)
    h.cyl("UpperChest", (0, nb.y - 0.01, z0 + 0.005), (0, nb.y - 0.03, z1 - 0.005), 0.112 * k, 0.16 * k, "team", "team",
          seg=16, caps=False, clip=clip, flip=True)
    h.cyl("UpperChest", (0, nb.y - 0.03, z1 - 0.012), (0, nb.y - 0.03, z1 + 0.004), 0.168 * k, 0.172 * k, "gold", seg=16,
          caps=False, clip=clip)
    # Coat tails: three ribbons at the back (asymmetric lengths) + two front-side panels.
    zt = h.waist_z + 0.04
    back, _ = h.surface(0, zt, -1)

    def tail_w(co):
        t = max(0.0, min(1.0, (zt - co.z) / 0.6))
        return {"Hips": 1.0 - 0.6 * t, "UpperLeg_L": 0.3 * t, "UpperLeg_R": 0.3 * t}
    for x, bottom, col in ((-0.1, 0.30, "plum"), (0.0, 0.40, "plum"), (0.1, 0.52, "plum")):
        a = Vector((x * k, back.y - 0.03 * k, zt))
        b = Vector((x * 1.35 * k, back.y - 0.16 * k, bottom * k))
        m = _along(b, a, Vector((0, -1, 0)))
        L = (a - b).length
        h.box(None, None, (0.1 * k, L, 0.014 * k), col, mat=m, weights=tail_w, bevel=0.3)
        tip = b + (a - b).normalized() * 0.04
        h.box(None, None, (0.104 * k, 0.07, 0.018 * k), "gold", mat=_along(b - (a - b).normalized() * 0.005, tip,
              Vector((0, -1, 0))), weights=tail_w, bevel=0.3)
    for s in (-1, 1):
        p, n = h.surface(s * 0.15 * k, zt - 0.02, 1)
        a = Vector((s * 0.17 * k, p.y - 0.02, zt))
        b = Vector((s * 0.2 * k, p.y + 0.0, zt - 0.36 * k))
        side = "UpperLeg_L" if s < 0 else "UpperLeg_R"
        h.box(None, None, (0.11 * k, (a - b).length, 0.012 * k), "plum", mat=_along(b, a, Vector((s, 0.6, 0))),
              weights=lambda co, side=side: {"Hips": 0.55, side: 0.45} if co.z < zt - 0.1 else {"Hips": 1.0}, bevel=0.3)
    # Loom halo: spine rig + four chrome spindle arms with gold spools and violet crystals.
    uc = h.jh("UpperChest")
    p, n = h.surface(0, uc.z + 0.02, -1)
    plate = p + Vector((0, -0.03, 0)) * k
    h.box("UpperChest", plate, Vector((0.07, 0.04, 0.26)) * k, "chrome", "chrome", bevel=0.35)
    h.box("UpperChest", plate + Vector((0, -0.02, 0.0)) * k, Vector((0.03, 0.02, 0.2)) * k, "gold", bevel=0.3)
    hub = plate + Vector((0, -0.06, 0.12)) * k
    h.sphere("UpperChest", hub, Vector((0.045, 0.045, 0.045)) * k, "chrome", "chrome", seg=(10, 6))
    tips = []
    for ang in (22, 64, 116, 158):
        a = math.radians(ang)
        tip = hub + Vector((math.cos(a) * 0.40, -0.08, math.sin(a) * 0.30)) * k
        h.cyl("UpperChest", hub, tip, 0.014 * k, 0.01 * k, "chrome", "chrome", seg=6)
        d = (tip - hub).normalized()
        h.cyl("UpperChest", tip - d * 0.03 * k, tip + d * 0.03 * k, 0.03 * k, 0.03 * k, "gold", seg=10)
        h.cyl("UpperChest", tip + d * 0.03 * k, tip + d * 0.05 * k, 0.018 * k, 0.012 * k, "chrome", "chrome", seg=8)
        cr = tip + d * 0.09 * k
        h.sphere("UpperChest", cr, Vector((0.022, 0.022, 0.05)) * k, "violet", "emit", seg=(6, 4),
                 rot=(0, -math.degrees(math.atan2(d.x, d.z)), 0))
        tips.append(cr)
    # Glowing threads: crystal tips -> left fingertips (skinned UpperChest -> Hand_L).
    hand = h.jl("Hand_L", 1.25)
    for i, cr in enumerate(tips[2:]):
        end = hand + Vector((0, 0.01 * (i - 1), -0.01 * i))
        L = (end - cr).length

        def thread_w(co, cr=cr, end=end, L=L):
            t = max(0.0, min(1.0, (co - cr).dot((end - cr).normalized()) / L))
            return {"UpperChest": 1.0 - t, "Hand_L": t}
        h.cyl(None, cr, end, 0.004 * k, 0.003 * k, "team", "team_emit", seg=4, weights=thread_w, caps=False)
    # Thimble rings on the right forearm cuff (chrome), boot trims are shells.


def threadcaster(h, W):
    def wb(c, s, col, ch="flat", **kw):
        h.box("Weapon", None, s, col, ch, mat=W @ Matrix.Translation(Vector(c)) @ _rx(kw.pop("rx", 0)), **kw)

    wb((0, -0.012, -0.045), (0.03, 0.04, 0.095), "ink", rx=-15, bevel=0.3)
    wb((0, 0.06, 0.03), (0.05, 0.24, 0.075), "chrome", "chrome", bevel=0.3, taper=(0.8, 1.0))
    wb((0, 0.30, 0.04), (0.042, 0.26, 0.05), "plum", bevel=0.35)
    h.cyl("Weapon", W @ Vector((0, 0.16, 0.04)), W @ Vector((0, 0.72, 0.04)), 0.013, 0.011, "chrome", "chrome", seg=8)
    for y in (0.46, 0.58):
        h.cyl("Weapon", W @ Vector((0, y, 0.04)), W @ Vector((0, y + 0.02, 0.04)), 0.02, 0.02, "gold", seg=8)
    h.cyl("Weapon", W @ Vector((0.0, 0.70, 0.04)), W @ Vector((0.0, 0.75, 0.04)), 0.016, 0.022, "team", "team_emit", seg=8)
    h.cyl("Weapon", W @ Vector((-0.035, 0.06, 0.10)), W @ Vector((0.035, 0.06, 0.10)), 0.048, 0.048, "gold", seg=14)
    h.cyl("Weapon", W @ Vector((-0.04, 0.06, 0.10)), W @ Vector((0.04, 0.06, 0.10)), 0.022, 0.022, "violet", "emit", seg=8)
    wb((0, -0.13, 0.02), (0.04, 0.16, 0.06), "plum", bevel=0.35, taper=(0.9, 0.8))


# ======================================================================== table
HEROES = {
    "ryker": {
        "key": "ryker",
        "height": 1.85,
        "head_scale": 0.95,
        "decimate": 0.28,
        "targets": {"caucasian-male-young": 0.5, "african-male-young": 0.25, "asian-male-young": 0.25,
                    "universal-male-young-maxmuscle-averageweight": 0.75,
                    "male-young-maxmuscle-averageweight-idealproportions": 0.8},
        "palette": {"olive": "#4E5A45", "bone": "#E3DCC8", "suit": "#2F333B", "rubber": "#232428",
                    "chrome": "#C9D4E2", "skin": "#C98F6B", "eye": "#15151A", "tape": "#F2EFE6",
                    "trim": "#3A4236", "team": TEAM},
        "cuts": ryker_cuts,
        "regions": ryker_regions,
        "shells": [
            {"pick": _vest_pick, "offset": 0.022, "paint": _vest_paint, "rim": ("trim", "flat")},
            {"pick": _thigh_pick, "offset": 0.012, "paint": ("olive", "flat"), "rim": ("trim", "flat")},
            {"pick": _boot_pick, "offset": 0.013, "paint": ("rubber", "flat"), "rim": ("rubber", "flat")},
        ],
        "parts": ryker_parts,
        "weapon": "breakline",
        "stance": {"grip_r": (0.16, 0.27, 1.22), "pivot": (0.16, 0.04, 1.42), "twist": -20, "clav_l": -6,
                   "pole_r": (1, -0.4, -1), "pole_l": (-0.6, -0.2, -1), "two_handed": True,
                   "grip_l": (0, 0.34, 0.0), "hand_r_y": (0, 0.55, -1), "hand_r_n": (-1, 0, 0),
                   "hand_l_y": (1, 0.25, 0.1), "hand_l_n": (0, 0, 1), "mag": (0, 0.12, -0.12)},
        "gait": {"run_amp": 40, "lean": 9},
        "casts": [("throw", [("z", 12)]), ("inject", []), ("thrust", [("x", -6)]), ("raise", [("x", 8)])],
    },
    "vesper": {
        "key": "vesper",
        "height": 1.88,
        "head_scale": 0.95,
        "decimate": 0.28,
        "targets": {"caucasian-female-young": 0.6, "asian-female-young": 0.4,
                    "universal-female-young-averagemuscle-minweight": 0.8,
                    "universal-female-young-maxmuscle-minweight": 0.2,
                    "female-young-averagemuscle-minweight-idealproportions": 1.0},
        "palette": {"plum": "#5B2A6E", "gold": "#D9A441", "ink": "#2A1E33", "chrome": "#C9D4E2",
                    "violet": "#B07CFF", "skin": "#E9B994", "eye": "#1A1220", "hair": "#231A2B",
                    "trim": "#3E1D4B", "team": TEAM},
        "cuts": vesper_cuts,
        "regions": vesper_regions,
        "shells": [
            {"pick": _coat_pick, "offset": 0.016, "paint": ("plum", "flat"), "rim": ("gold", "flat")},
            {"pick": _vboot_pick, "offset": 0.012, "paint": ("plum", "flat"), "rim": ("gold", "flat")},
        ],
        "parts": vesper_parts,
        "weapon": "threadcaster",
        "stance": {"grip_r": (0.21, 0.22, 1.08), "pivot": (0.2, 0.0, 1.38), "twist": 8, "clav_l": 0,
                   "pole_r": (1, -0.6, -1), "pole_l": (-1, -0.4, -0.6), "two_handed": False,
                   "left_free": ((-0.2, 0.30, 1.30), (0.1, 0.3, 1), (0.2, 1, 0)),
                   "grip_l": (0, 0.3, 0.0), "hand_r_y": (0, 0.55, -1), "hand_r_n": (-1, 0, 0),
                   "hand_l_y": (1, 0.25, 0.1), "hand_l_n": (0, 0, 1), "mag": (0, 0.06, 0.12)},
        "gait": {"run_amp": 36, "lean": 6},
        "casts": [("thrust", []), ("plant", [("x", -10)]), ("sweep", [("z", 15)]), ("raise", [("x", 10)])],
    },
}

WEAPONS = {"breakline": breakline, "threadcaster": threadcaster}
