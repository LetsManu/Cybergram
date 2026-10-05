"""W16 hero definitions for the bespoke pipeline (`"pipeline": "gen"`, tools/art/hero_gen.py).

A gen hero has the same keys as a MakeHuman hero (palette, cuts, regions, shells,
parts, weapon, stance, gait, casts) plus:
  body    body_gen params (see body_gen.DEFAULT_BODY; metres at 1.85 m)
  paint   hero_paint controls (see hero_paint.DEFAULT_PAINT)
  cloth   baked cloth garments (see cloth_bake.py)
  idle    optional personal idle loop fn(poser, phase, frame) (legs / hips / spine / chest)
  legacy  the old MakeHuman entry (build_hero.py --legacy) for before/after renders
Space: Blender metres, X = character right, Y = forward, Z = up, feet at Z = 0.
"""
import math

from mathutils import Matrix, Vector

import hero_defs
from hero_defs import TEAM, _along, _rx, _wz


# ======================================================================== Vesper Loom
def vesper_cuts(h):
    cuts = []
    for s in ("L", "R"):
        for t in (0.70, 0.80):
            cuts.append(({"LowerArm_" + s, "Hand_" + s}, *h.cut("LowerArm_" + s, t)))
        cuts.append(({"LowerLeg_" + s, "Foot_" + s, "UpperLeg_" + s}, *h.cut("LowerLeg_" + s, 0.30)))
    cuts.append(({"Neck", "Head", "UpperChest"}, *h.cut("Neck", 0.2)))
    zw = h.jh("Spine").z + 0.02
    for dz in (-0.05, -0.035, 0.035, 0.05):
        cuts.append(({"Hips", "Spine", "Chest"}, Vector((0, 0, zw + dz)), Vector((0, 0, 1))))
    h.waist_z = zw
    return cuts


def vesper_regions(h, c, bone, n):
    if bone in ("Head", "Neck") and h.side("Neck", 0.2, c) > 0:
        return "ink", "flat"  # hood under the mask (no visible face)
    if bone.startswith("Hand"):
        return "glove", "flat"
    if bone.startswith("LowerArm"):
        if h.side(bone, 0.80, c) > 0:
            return "glove", "flat"
        if h.side(bone, 0.70, c) > 0:
            return "gold", "flat"
        return "plum", "flat"
    if bone.startswith("UpperArm") or bone.startswith("Clavicle"):
        return "plum", "flat"
    if abs(c.z - h.waist_z) < 0.05 and bone in ("Hips", "Spine", "Chest"):
        return ("gold" if abs(c.z - h.waist_z) > 0.035 else "ink"), "flat"
    if bone.startswith("Foot") or (bone.startswith("LowerLeg") and h.side(bone, 0.30, c) > 0):
        return "plum", "flat"
    return "ink", "flat"


def _bodice_pick(h, c, bone, n):
    if bone not in ("Chest", "UpperChest", "Clavicle_L", "Clavicle_R", "Spine", "Neck"):
        return False
    if bone == "Neck" and h.side("Neck", 0.2, c) > 0:
        return False
    return c.z > h.waist_z + 0.05


def _boot_pick(h, c, bone, n):
    return bone.startswith("Foot") or (bone.startswith("LowerLeg") and h.side(bone, 0.30, c) > 0)


def vesper_parts(h):
    import hero_hd
    k = h.d["height"] / 1.88
    lo, hi = h.bbox("Head")
    hc = (lo + hi) / 2
    hr = (hi - lo) / 2
    eye_z = (h.eye("L").z + h.eye("R").z) / 2
    skin = hero_hd.BodySkin(h)
    # --- porcelain marionette mask: smooth oval, hinge lines, gold seam + glyph, violet slits.
    mc = Vector((0, hc.y + hr.y * 0.2, hc.z - 0.01))
    rad = Vector((hr.x * 1.04, hr.y * 0.95, hr.z * 1.02))
    h.sphere("Head", mc, rad, "white", seg=(20, 14), clip=[((0, -0.1, 0), (0, -1, 0))])

    def on_mask(x, z, out=0.003):
        q = 1.0 - (x / rad.x) ** 2 - ((z - mc.z) / rad.z) ** 2
        y = mc.y + rad.y * math.sqrt(max(q, 0.0))
        nrm = Vector((x / rad.x ** 2, (y - mc.y) / rad.y ** 2, (z - mc.z) / rad.z ** 2)).normalized()
        return Vector((x, y, z)) + nrm * out, nrm

    def yaw(nrm):
        return -math.degrees(math.atan2(nrm.x, nrm.y))
    for sx in (-1, 1):
        p, nrm = on_mask(sx * 0.036 * k, eye_z + 0.004)
        h.box("Head", p, (0.046 * k, 0.01, 0.008 * k), "violet", "emit", rot=(0, -sx * 16, yaw(nrm)), bevel=0.3)
        # marionette hinge lines: mouth corner -> jaw
        for i in range(3):
            z = eye_z - (0.06 + i * 0.022) * k
            p, nrm = on_mask(sx * (0.026 + i * 0.002) * k, z)
            h.box("Head", p, (0.005 * k, 0.006, 0.024 * k), "ink", rot=(0, 0, yaw(nrm)), bevel=0.2)
        p, nrm = on_mask(sx * 0.05 * k, eye_z - 0.03 * k)  # painted cheek diamond
        h.box("Head", p, (0.012 * k, 0.004, 0.012 * k), "gold", rot=(0, 45, yaw(nrm)), bevel=0.2)
    for i in range(5):
        z = eye_z - 0.03 * k + (i - 2) * 0.03 * k
        p, nrm = on_mask(0.0, z, 0.002)
        h.box("Head", p, (0.006 * k, 0.008, 0.032 * k), "gold", bevel=0.2)
    p, nrm = on_mask(0.0, eye_z + 0.055 * k)
    h.box("Head", p, (0.026 * k, 0.008, 0.026 * k), "gold", rot=(0, 45, 0), bevel=0.2)
    # --- sharp A-line bob over the hood + gold-wrapped braid.
    bc = Vector((0, hc.y - 0.006, hc.z + 0.012))
    h.sphere("Head", bc, Vector((hr.x * 1.2, hr.y * 1.14, hr.z * 1.1)), "hair", seg=(18, 12),
             clip=[((0, 0.48, -0.12), (0, 1, -0.9)), ((0, 0, -0.62), (0, -0.35, -1))])
    h.box("Head", (0, mc.y + rad.y * 0.55, eye_z + 0.06 * k), (hr.x * 1.95, 0.04, 0.032), "hair", rot=(22, 0, 0),
          bevel=0.4)
    top = Vector((-0.04 * k, lo.y - 0.005, hc.z - 0.02))
    bands = [(hc.z, "Head"), (h.jh("Neck").z, "Neck"), (h.jh("UpperChest").z, "UpperChest"),
             (h.jh("Chest").z, "Chest")]
    prev = top
    for i in range(7):
        p, nrm = h.surface(-0.05 * k, top.z - 0.07 * (i + 1) * k, -1)
        p = p + nrm * (0.04 if i > 0 else 0.03) * k
        h.sphere(None, (prev + p) / 2, Vector((0.032, 0.03, 0.046)) * k * (1.0 - i * 0.05),
                 "gold" if i % 2 == 1 else "hair", seg=(8, 6), weights=lambda co: _wz(h, co.z, bands))
        prev = p
    # --- high wide collar: plum outer, team lining, gold rim (open at the front).
    nb = h.jh("Neck")
    z0, z1 = nb.z - 0.04 * k, eye_z - 0.085 * k
    clip = [((0, 0.45, 0), (0, 1, 0))]
    h.cyl("UpperChest", (0, nb.y - 0.01, z0), (0, nb.y - 0.03, z1), 0.125 * k, 0.18 * k, "plum", seg=18, caps=False,
          clip=clip)
    h.cyl("UpperChest", (0, nb.y - 0.01, z0 + 0.005), (0, nb.y - 0.03, z1 - 0.005), 0.117 * k, 0.17 * k, "team",
          "team", seg=18, caps=False, clip=clip, flip=True)
    h.cyl("UpperChest", (0, nb.y - 0.03, z1 - 0.014), (0, nb.y - 0.03, z1 + 0.004), 0.178 * k, 0.183 * k, "gold",
          seg=18, caps=False, clip=clip)
    # --- gold waist cincher over the coat seam, buckle with the team light.
    zb = h.waist_z + 0.01
    pts = hero_hd.ring(h, Vector((0, h.jh("Hips").y, zb)), (0, 0, 1), ("Hips", "Spine", "Chest"), n=32, off=0.02)
    hero_hd.strap(h, pts, (0, 0, 1), 0.07 * k, 0.012, "gold", skin)
    p, d = max(pts, key=lambda pd: pd[1].y)
    M = hero_hd.frame(p + d * 0.012, d, Vector((0, 0, 1)))
    hero_hd.piece(h, M, (0, 0, 0.004), (0.07 * k, 0.085 * k, 0.012), "chrome", skin.fixed(p), "chrome", bevel=0.4)
    hero_hd.piece(h, M, (0, 0, 0.012), (0.03 * k, 0.05 * k, 0.006), "team", skin.fixed(p), "team_emit", bevel=0.4)
    # --- chunky boots: thick soles + gold cuff straps; gauntlet knuckle plates.
    for s in ("L", "R"):
        blo, bhi = h.bbox("Foot_" + s, 0.4)
        c = (blo + bhi) / 2
        sz = bhi - blo
        h.box("Foot_" + s, (c.x, c.y + 0.006, 0.012 * k), (sz.x + 0.022, sz.y + 0.03, 0.03 * k), "ink", bevel=0.35)
        h.box("Foot_" + s, (c.x, blo.y + 0.01, 0.045 * k), (sz.x * 0.8, 0.03, 0.07 * k), "gold", bevel=0.35)
        ax = (h.jt("LowerLeg_" + s) - h.jh("LowerLeg_" + s)).normalized()
        cuff = hero_hd.ring(h, h.jl("LowerLeg_" + s, 0.32), ax, ("LowerLeg_" + s,), n=20, off=0.006, reach=0.3)
        hero_hd.strap(h, cuff, ax, 0.04 * k, 0.012, "gold", skin)
        wr = h.jh("Hand_" + s)
        fwd = (h.jt("Hand_" + s) - wr).normalized()
        back = -h.palm[s]
        p0 = wr + fwd * 0.07 * k + back * 0.03 * k
        h.box("Hand_" + s, p0, (0.075 * k, 0.03 * k, 0.02 * k), "gold", mat=_along(p0 - fwd * 0.02, p0 + fwd * 0.02,
              back), bevel=0.4)
        ax = (h.jt("LowerArm_" + s) - h.jh("LowerArm_" + s)).normalized()
        g = hero_hd.ring(h, h.jl("LowerArm_" + s, 0.86), ax, ("LowerArm_" + s, "Hand_" + s), n=20, off=0.008, reach=0.3)
        hero_hd.strap(h, g, ax, 0.055 * k, 0.012, "gold", skin)
    # --- the Loom halo: spine rig + four chrome spindle arms, gold spools, violet crystals.
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
        tip = hub + Vector((math.cos(a) * 0.32, -0.1, math.sin(a) * 0.22 - 0.02)) * k
        h.cyl("UpperChest", hub, tip, 0.014 * k, 0.01 * k, "chrome", "chrome", seg=6)
        d = (tip - hub).normalized()
        h.cyl("UpperChest", tip - d * 0.03 * k, tip + d * 0.03 * k, 0.03 * k, 0.03 * k, "gold", seg=10)
        h.cyl("UpperChest", tip + d * 0.03 * k, tip + d * 0.05 * k, 0.018 * k, 0.012 * k, "chrome", "chrome", seg=8)
        cr = tip + d * 0.09 * k
        h.sphere("UpperChest", cr, Vector((0.022, 0.022, 0.05)) * k, "violet", "emit", seg=(6, 4),
                 rot=(0, -math.degrees(math.atan2(d.x, d.z)), 0))
        tips.append(cr)
    hand = h.jl("Hand_L", 1.1)
    for i, cr in enumerate(tips[2:]):
        end = hand + Vector((0, 0.01 * (i - 1), -0.01 * i))
        L = (end - cr).length

        def thread_w(co, cr=cr, end=end, L=L):
            t = max(0.0, min(1.0, (co - cr).dot((end - cr).normalized()) / L))
            return {"UpperChest": 1.0 - t, "Hand_L": t}
        h.cyl(None, cr, end, 0.004 * k, 0.003 * k, "team", "team_emit", seg=4, weights=thread_w, caps=False)


def threadcaster(h, W):
    """Vesper's own Threadcaster (W16): a one-hand loom carbine. Receiver shaped like a
    weaving shuttle, a gold spool drum with a violet core, thread guides along a needle
    barrel, a tensioner fin and a team-lit needle emitter. Weapon space: origin = right
    grip, +Y barrel, +Z up."""
    def wb(c, s, col, ch="flat", **kw):
        h.box("Weapon", None, s, col, ch, mat=W @ Matrix.Translation(Vector(c)) @ _rx(kw.pop("rx", 0)), **kw)

    def cyl(a, b, r0, r1, col, ch="flat", seg=10):
        h.cyl("Weapon", W @ Vector(a), W @ Vector(b), r0, r1, col, ch, seg=seg)
    wb((0, -0.01, -0.05), (0.032, 0.045, 0.11), "ink", rx=-14, bevel=0.35)            # grip
    wb((0, -0.01, -0.105), (0.036, 0.05, 0.016), "gold", rx=-14, bevel=0.3)            # pommel
    wb((0, 0.05, 0.03), (0.05, 0.22, 0.07), "chrome", "chrome", bevel=0.45, taper=(0.6, 0.85))   # shuttle receiver
    wb((0, -0.08, 0.035), (0.04, 0.09, 0.05), "chrome", "chrome", bevel=0.45, taper=(0.5, 0.6), rx=180)
    wb((0, 0.05, 0.068), (0.016, 0.2, 0.012), "plum", bevel=0.3)                         # top strip
    cyl((-0.042, 0.06, 0.035), (0.042, 0.06, 0.035), 0.05, 0.05, "gold", seg=16)         # spool drum
    for x in (-0.046, 0.046):
        cyl((x, 0.06, 0.035), (x * 1.08, 0.06, 0.035), 0.054, 0.054, "chrome", "chrome", seg=16)
    cyl((-0.05, 0.06, 0.035), (0.05, 0.06, 0.035), 0.022, 0.022, "violet", "emit", seg=8)
    for i in range(6):                                                                  # thread windings
        a = 2 * math.pi * i / 6
        y, z = 0.06 + math.cos(a) * 0.05, 0.035 + math.sin(a) * 0.05
        wb((0, y, z), (0.07, 0.006, 0.006), "team", "team", bevel=0.0)
    cyl((0, 0.15, 0.03), (0, 0.62, 0.03), 0.012, 0.008, "chrome", "chrome", seg=8)      # needle barrel
    for y in (0.24, 0.36, 0.48):                                                        # thread guides
        h.torus("Weapon", W @ Vector((0, y, 0.03)), W.to_3x3() @ Vector((0, 1, 0)), 0.022, 0.005, "gold", seg=(12, 5))
    h.cyl("Weapon", W @ Vector((0, 0.17, 0.03)), W @ Vector((0, 0.6, 0.03)), 0.003, 0.003, "team", "team_emit", seg=4,
          caps=False)
    cyl((0, 0.6, 0.03), (0, 0.68, 0.03), 0.016, 0.003, "team", "team_emit", seg=8)      # needle emitter
    wb((0, 0.2, 0.075), (0.006, 0.14, 0.05), "gold", bevel=0.3, taper=(1.0, 0.3))      # tensioner fin
    wb((0, 0.03, -0.012), (0.012, 0.06, 0.006), "ink", bevel=0.3)                       # trigger guard
    wb((0, 0.035, -0.02), (0.005, 0.008, 0.02), "chrome", "chrome", bevel=0.3)          # trigger


def vesper_idle(p, ph, f):
    """Personal idle: contrapposto on the right leg, hip dropped, chest open, slow breath."""
    from hero_anims import legs
    w = math.sin(ph)
    b = math.sin(2 * ph)
    legs(p, 0, 0, 0)
    p.rot("UpperLeg_R", [("y", -2 + 1.0 * w), ("z", 3), ("x", -1)])
    p.rot("UpperLeg_L", [("y", 4 + 1.5 * w), ("z", -9), ("x", 9)])
    p.rot("LowerLeg_L", [("x", -14 - 2 * max(0.0, -w))])
    p.rot("LowerLeg_R", [("x", -2)])
    p.rot("Foot_L", [("x", 5)])
    p.rot("Hips", [("y", 5 + 1.2 * w), ("z", -7)])
    p.hips((0.032 * p.k + 0.006 * w * p.k, 0, -0.008 * p.k))
    p.rot("Spine", [("y", -4 - 0.8 * w), ("x", -2 + 0.8 * b), ("z", 5)])
    p.rot("Chest", [("x", -4 + 0.6 * b), ("y", -2), ("z", 3)])


HEROES = {
    "vesper": {
        "key": "vesper",
        "pipeline": "gen",
        "legacy": hero_defs.HEROES["vesper"],
        "height": 1.88,
        "body": {"leg": 0.99, "torso": 0.53, "shoulder_w": 0.38, "chest_w": 0.31, "chest_d": 0.21,
                 "waist_w": 0.21, "waist_d": 0.165, "hip_w": 0.32, "hip_d": 0.215, "hip_joint_w": 0.18,
                 "neck": 0.08, "neck_r": 0.05, "head_w": 0.155, "head_d": 0.19, "head_h": 0.225,
                 "arm_r": 0.047, "forearm_r": 0.046, "wrist_r": 0.033, "thigh_r": 0.083, "knee_r": 0.056,
                 "calf_r": 0.064, "ankle_r": 0.042, "hand": 1.25, "foot": 1.25, "boot_r": 1.3,
                 "deltoid": 0.85, "pecs": 0.0, "bust": 0.3, "glutes": 0.6, "calves": 0.5, "traps": 0.3,
                 "chest_lift": 0.012, "arm_angle": 50.0},
        # Painted hatching is sparse; the runtime shader hatch is turned down so it
        # does not double up (per-hero shader overrides -> <id>_anim.tres metadata).
        "paint": {"hatch_density": 0.5, "hatch_threshold": -0.05,
                  "shader": {"hatch_strength": 0.1}},
        "palette": {"plum": "#8E3FB4", "gold": "#F5B83A", "ink": "#3D2C5F", "chrome": "#C9D4E2",
                    "violet": "#B57DFF", "hair": "#30234A", "glove": "#5A4483", "trim": "#4A2260",
                    "team": TEAM, "white": "#F4EEE2", "eye": "#1A1220",
                    "braid": "#F4B63B"},  # cloth gold for garment trims (not metal: no glint band)
        "cuts": vesper_cuts,
        "regions": vesper_regions,
        "shells": [
            {"pick": _bodice_pick, "offset": 0.016, "paint": ("plum", "flat"), "rim": ("gold", "flat")},
            {"pick": _boot_pick, "offset": 0.014, "paint": ("plum", "flat"), "rim": ("gold", "flat")},
        ],
        "parts": vesper_parts,
        "weapon": "threadcaster_w16",
        "cloth": [{"part": "coat", "kind": "skirt", "top": 0.10, "hem": 0.36, "offset": 0.016, "flare": 0.13,
                   "clear": 0.03, "open_front": 52, "slits": [(150, 0.55), (210, 0.55)],
                   "chains": [("FR", 60), ("BR", 120), ("B", 180), ("BL", 240), ("FL", 300)], "bones": 3,
                   "rows": 10, "col_deg": 10, "thick": 0.014,
                   "colors": {"outer": "plum", "inner": "ink", "hem": "braid", "trim": "braid"}}],
        # One-handed: carbine at chest height, the off hand free and open (conductor).
        "stance": {"grip_r": (0.15, 0.32, 1.28), "pivot": (0.14, 0.02, 1.42), "twist": -14, "clav_l": -4,
                   "pole_r": (1, -0.6, -1), "pole_l": (-1, -0.3, -0.6), "two_handed": False,
                   "left_free": ((-0.30, 0.24, 1.22), (-0.15, 0.8, 0.45), (0.25, 0.3, 1)),
                   "grip_l": (0, 0.28, 0.0), "hand_r_y": (0, 0.55, -1), "hand_r_n": (-1, 0, 0),
                   "hand_l_y": (1, 0.25, 0.1), "hand_l_n": (0, 0, 1), "mag": (0, 0.06, 0.12),
                   "belt": (-0.2, 0.1, 1.02)},
        "idle": vesper_idle,
        "gait": {"run_amp": 36, "lean": 6},
        "casts": [("thrust", []), ("plant", [("x", -10)]), ("sweep", [("z", 15)]), ("raise", [("x", 10)])],
    },
}

WEAPONS = {"threadcaster_w16": threadcaster}
