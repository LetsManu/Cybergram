"""The other five heroes (W13 roll-out): Brannoc, Liora, Sable, Juniper, Hex.

Same conventions as hero_defs.py. Bodies are painted with one generic zone scheme
(head under the mask, torso, sleeves, gloves, legs, boots, belt) driven by a
per-hero spec; silhouettes come from the parts (masks, hooks, gear) and weapons.
Art direction: design/art-bible.md §4.7 / §5.2 and design/art/hero-art-bible.md §1.1.
"""
import math

from mathutils import Matrix, Vector

from hero_defs import TEAM, _along, _rx, _wz, closed_boots

TORSO = ("Spine", "Chest", "UpperChest", "Clavicle_L", "Clavicle_R", "Neck")
LEGS = ("Hips", "Spine", "UpperLeg_L", "UpperLeg_R")


def generic(spec):
    gt, bt = spec.get("glove_t", 0.8), spec.get("boot_t", 0.4)

    def cuts(h):
        c = []
        for s in ("L", "R"):
            c.append(({"LowerArm_" + s, "Hand_" + s}, *h.cut("LowerArm_" + s, gt)))
            c.append(({"LowerLeg_" + s, "Foot_" + s, "UpperLeg_" + s}, *h.cut("LowerLeg_" + s, bt)))
            if spec.get("sleeve_t"):
                c.append(({"UpperArm_" + s, "LowerArm_" + s}, *h.cut("UpperArm_" + s, spec["sleeve_t"])))
            if spec.get("shorts_t"):
                c.append(({"UpperLeg_" + s, "LowerLeg_" + s, "Hips"}, *h.cut("UpperLeg_" + s, spec["shorts_t"])))
        c.append(({"Neck", "Head", "UpperChest"}, *h.cut("Neck", 0.3)))
        zb = h.jh("Hips").z + spec.get("belt_dz", 0.1) * h.d["height"] / 1.85
        for dz in (-0.03, 0.03):
            c.append((set(LEGS), Vector((0, 0, zb + dz)), Vector((0, 0, 1))))
        h.belt_z = zb
        return c

    def regions(h, c, bone, n):
        P = spec["paint"]
        if bone in ("Head", "Neck") and h.side("Neck", 0.3, c) > 0:
            return P["head"], "flat"
        if bone.startswith("Hand") or (bone.startswith("LowerArm") and h.side(bone, gt, c) > 0):
            return P["gloves"], "flat"
        if bone.startswith("Foot") or (bone.startswith("LowerLeg") and h.side(bone, bt, c) > 0):
            return P["boots"], "flat"
        if abs(c.z - h.belt_z) < 0.03 and bone in LEGS:
            return P["belt"], "flat"
        if bone.startswith("UpperLeg") or bone.startswith("LowerLeg"):
            st = spec.get("shorts_t")
            if st and (bone.startswith("LowerLeg") or h.side(bone, st, c) > 0):
                return P["shins"], "flat"
            return P["legs"], "flat"
        if bone.startswith("UpperArm") or bone.startswith("LowerArm"):
            side = bone[-1]
            sl = spec.get("sleeve_t")
            if sl and (bone.startswith("LowerArm") or h.side(bone, sl, c) > 0):
                key = "forearm_" + side if "forearm_" + side in P else "forearm"
                return P[key], ("chrome" if P[key] == "chrome" else "flat")
            return P["sleeves"], "flat"
        if bone == "Hips" and c.z < h.belt_z:
            return P["legs"], "flat"
        return P["torso"], "flat"

    shells = []
    ts = spec.get("torso_shell")
    if ts:
        arms = ts.get("arms", False)

        def pick(h, c, bone, n, arms=arms, ts=ts):
            if bone in ("Head",) or (bone == "Neck" and h.side("Neck", 0.3, c) > 0):
                return False
            ok = bone in TORSO or (arms and bone.startswith("UpperArm"))
            if bone == "Hips" and ts.get("hips"):
                ok = True
            return ok and c.z > h.belt_z + ts.get("above_belt", 0.03) - (0.3 if ts.get("hips") else 0.0)
        shells.append({"pick": pick, "offset": ts["offset"], "paint": (ts["color"], "flat"), "rim": (ts["rim"], "flat")})
    th = spec.get("thigh_shell")
    if th:
        def tpick(h, c, bone, n):
            return bone.startswith("UpperLeg") and h.side(bone, 0.12, c) > 0 and h.side(bone, 0.92, c) < 0
        shells.append({"pick": tpick, "offset": th[0], "paint": (th[1], "flat"), "rim": (th[2], "flat")})
    bs = spec.get("boot_shell")
    if bs:
        def bpick(h, c, bone, n):
            return bone.startswith("Foot") or (bone.startswith("LowerLeg") and h.side(bone, bt, c) > 0)
        shells.append({"pick": bpick, "offset": bs[0], "paint": (bs[1], "flat"), "rim": (bs[2], "flat")})
    return cuts, regions, shells


def _head(h):
    lo, hi = h.bbox("Head")
    return lo, hi, (lo + hi) / 2, (hi - lo) / 2, (h.eye("L").z + h.eye("R").z) / 2


def _k(h):
    return h.d["height"] / 1.85


def _wbox(h, W):
    def wb(c, s, col, ch="flat", **kw):
        h.box("Weapon", None, s, col, ch, mat=W @ Matrix.Translation(Vector(c)) @ _rx(kw.pop("rx", 0)), **kw)
    return wb


# ======================================================================= Brannoc
def brannoc_parts(h):
    k = _k(h)
    lo, hi, hc, hr, eye_z = _head(h)
    # Heavy closed helm: squat bevelled block with a T-slit (team glow) + brow ridge.
    h.box("Head", (0, hc.y + 0.005, hc.z - 0.005), (hr.x * 2.5, hr.y * 2.35, hr.z * 2.15), "teal", bevel=0.35,
          taper=(0.85, 0.85))
    h.box("Head", (0, hi.y + 0.03, eye_z + 0.005), (hr.x * 1.7, 0.03, 0.026), "team", "team_emit", bevel=0.3)
    h.box("Head", (0, hi.y + 0.03, eye_z - 0.05), (0.03, 0.03, 0.08), "team", "team_emit", bevel=0.3)
    h.box("Head", (0, hi.y + 0.035, eye_z + 0.045), (hr.x * 2.4, 0.05, 0.04), "iron", bevel=0.35)
    h.box("Neck", (0, h.jh("Neck").y, h.jh("Neck").z + 0.02), (0.26 * k, 0.24 * k, 0.12 * k), "soot", bevel=0.3)
    # Huge square shoulder plates (stacked), the widest read in the cast.
    for s, sg in (("L", -1), ("R", 1)):
        sh = h.jh("UpperArm_" + s)
        for i, (w, z) in enumerate(((0.26, 0.07), (0.22, 0.0))):
            h.box("Clavicle_" + s, sh + Vector((sg * 0.02, 0, z)) * k, Vector((w, 0.26, 0.09)) * k,
                  "teal" if i == 0 else "iron", rot=(0, sg * 18, 0), bevel=0.35)
        h.box("Clavicle_" + s, sh + Vector((sg * 0.03, 0.11, 0.07)) * k, Vector((0.2, 0.02, 0.03)) * k, "team", "team",
              rot=(0, sg * 18, 0), bevel=0.2)
    # Chest plate with the furnace-heart grille (team glow), back vent.
    uc = h.jh("UpperChest")
    p, n = h.surface(0, uc.z - 0.06 * k, 1)
    h.box("UpperChest", p + n * 0.05 * k, Vector((0.34, 0.08, 0.3)) * k, "teal", bevel=0.3, taper=(1.1, 1.0))
    h.box("UpperChest", p + n * 0.095 * k, Vector((0.14, 0.02, 0.12)) * k, "soot", bevel=0.2)
    for i in range(4):
        h.box("UpperChest", p + n * 0.108 * k + Vector((0, 0, (i - 1.5) * 0.026)) * k, Vector((0.12, 0.01, 0.012)) * k,
              "team", "team_emit", bevel=0.0)
    pb, nb = h.surface(0, uc.z - 0.05 * k, -1)
    h.box("UpperChest", pb + nb * 0.08 * k, Vector((0.3, 0.14, 0.32)) * k, "soot", bevel=0.3)
    for i in range(3):
        h.box("UpperChest", pb + nb * 0.155 * k + Vector((0, 0, 0.06 * (i - 1))) * k, Vector((0.22, 0.02, 0.02)) * k,
              "team", "team_emit", bevel=0.0)
    # Right forearm shield generator slab (asymmetric hook) + hanging tags.
    a, b = h.jh("LowerArm_R"), h.jt("LowerArm_R")
    m = _along(a, b, Vector((1, 0, 0)))
    h.box(None, None, (0.07 * k, (b - a).length * 1.05, 0.22 * k), "iron", mat=m @ Matrix.Translation((0.07 * k, 0, 0)),
          weights=lambda co: {"LowerArm_R": 1.0}, bevel=0.3)
    h.box(None, None, (0.02 * k, (b - a).length * 0.8, 0.12 * k), "team", "team_emit",
          mat=m @ Matrix.Translation((0.11 * k, 0, 0)), weights=lambda co: {"LowerArm_R": 1.0}, bevel=0.2)
    for i in range(3):
        h.box(None, None, (0.01, 0.025, 0.04), ("bone", "gold", "bone")[i], mat=m @ Matrix.Translation(
            (0.1 * k, (i - 1) * 0.06, -0.14 * k)), weights=lambda co: {"LowerArm_R": 1.0}, bevel=0.2)
    # Waist plates and knee guards.
    for x in (-0.13, 0.0, 0.13):
        p, n = h.surface(x * k, h.belt_z - 0.06, 1)
        h.box("Hips", p + n * 0.035 * k, Vector((0.12, 0.03, 0.14)) * k, "teal", bevel=0.3, taper=(0.8, 1.0))
    for s in ("L", "R"):
        kn = h.jh("LowerLeg_" + s)
        h.box("LowerLeg_" + s, kn + Vector((0, 0.08, 0)) * k, Vector((0.13, 0.05, 0.15)) * k, "iron", bevel=0.4)
    closed_boots(h, "soot", "iron", k)


def ironmaw(h, W):
    wb = _wbox(h, W)
    wb((0, -0.01, -0.05), (0.04, 0.05, 0.11), "soot", rx=-20, bevel=0.3)
    wb((0, 0.08, 0.03), (0.08, 0.24, 0.11), "iron", bevel=0.3)
    h.cyl("Weapon", W @ Vector((0, 0.18, 0.04)), W @ Vector((0, 0.50, 0.04)), 0.042, 0.046, "soot", seg=10)
    wb((0, 0.33, -0.02), (0.07, 0.14, 0.05), "teal", bevel=0.4)
    for sz in (1, -1):
        wb((0, 0.53, 0.04 + sz * 0.035), (0.1, 0.07, 0.03), "iron", rx=sz * 18, bevel=0.3)
    wb((0, 0.52, 0.04), (0.06, 0.02, 0.05), "team", "team_emit", bevel=0.2)
    wb((0, -0.14, 0.02), (0.06, 0.16, 0.09), "teal", bevel=0.35, taper=(0.9, 0.8))


# ======================================================================== Liora
def liora_parts(h):
    k = _k(h)
    lo, hi, hc, hr, eye_z = _head(h)
    # Smooth medic helmet + full visor (team glow) and the leaf-in-ring emblem on the brow.
    hcen = Vector((0, hc.y, hc.z + 0.01))
    h.sphere("Head", hcen, Vector((hr.x * 1.2, hr.y * 1.16, hr.z * 1.12)), "ivory", seg=(18, 12),
             clip=[((0, 0, -0.7), (0, 0, -1))])
    h.sphere("Head", hcen + Vector((0, 0.012, -0.012)), Vector((hr.x * 1.12, hr.y * 1.12, hr.z * 0.62)), "team",
             "team_emit", seg=(16, 8), clip=[((0, -0.1, 0), (0, -1, 0)), ((0, 0, 0.75), (0, 0, 1))])
    h.torus("Head", (0, hi.y + 0.012, eye_z + 0.07), (0, 1, 0), 0.016 * k, 0.004 * k, "sage")
    # Long hair in a ribbon down the back.
    bands = [(hc.z, "Head"), (h.jh("Neck").z, "Neck"), (h.jh("UpperChest").z, "UpperChest"), (h.jh("Chest").z, "Chest")]
    top, _ = h.surface(0, hc.z - 0.03, -1)
    bot, _ = h.surface(0, h.jh("Chest").z - 0.05, -1)
    a, b = top + Vector((0, -0.03, 0)), bot + Vector((0, -0.05, 0))
    h.box(None, None, (0.1 * k, (a - b).length, 0.03 * k), "hair", mat=_along(b, a, Vector((0, -1, 0))),
          weights=lambda co: _wz(h, co.z, bands), bevel=0.4)
    h.box(None, None, (0.11 * k, 0.03, 0.035 * k), "sage", mat=_along(a.lerp(b, 0.25), a.lerp(b, 0.3), Vector((0, -1, 0))),
          weights=lambda co: _wz(h, co.z, bands), bevel=0.3)
    # Round-hemmed long coat skirt (open at the front) with sage panels.
    zt = h.belt_z + 0.02
    zb = h.jh("LowerLeg_L").z - 0.02

    def skirt_w(co):
        t = max(0.0, min(1.0, (zt - co.z) / max(zt - zb, 0.1)))
        return {"Hips": 1.0 - 0.6 * t, "UpperLeg_L": 0.3 * t, "UpperLeg_R": 0.3 * t}
    h.cyl(None, (0, -0.01, zt), (0, -0.03, zb), 0.17 * k, 0.25 * k, "ivory", seg=18, caps=False,
          clip=[((0, 0.6, 0), (0, 1, 0))], weights=skirt_w)
    h.cyl(None, (0, -0.01, zt - 0.005), (0, -0.03, zb + 0.005), 0.165 * k, 0.245 * k, "sage", seg=18, caps=False,
          clip=[((0, 0.6, 0), (0, 1, 0))], flip=True, weights=skirt_w)
    h.cyl(None, (0, -0.03, zb + 0.03), (0, -0.03, zb), 0.248 * k, 0.252 * k, "sage", seg=18, caps=False,
          clip=[((0, 0.6, 0), (0, 1, 0))], weights=skirt_w)
    # Soft round shoulder pads, elbow patches, mana IV lines (team) along the forearms.
    for s, sg in (("L", -1), ("R", 1)):
        sh = h.jh("UpperArm_" + s)
        h.sphere("Clavicle_" + s, sh + Vector((sg * 0.01, 0, 0.03)) * k, Vector((0.09, 0.1, 0.07)) * k, "ivory",
                 seg=(12, 8), clip=[((0, 0, -0.3), (0, 0, -1))])
        h.sphere("LowerArm_" + s, h.jh("LowerArm_" + s), Vector((0.045, 0.05, 0.045)) * k, "sage", seg=(10, 6))
        h.cyl("LowerArm_" + s, h.jl("LowerArm_" + s, 0.15) + Vector((0, 0, 0.035)) * k,
              h.jl("LowerArm_" + s, 0.85) + Vector((0, 0, 0.03)) * k, 0.006 * k, 0.006 * k, "team", "team_emit", seg=5)
    # Halo ring orbiting the back at shoulder height with two docked drones.
    uc = h.jh("UpperChest")
    p, n = h.surface(0, uc.z + 0.06, -1)
    c = p + Vector((0, -0.16, 0.05)) * k
    h.torus("UpperChest", c, (0, 1, 0), 0.3 * k, 0.014 * k, "chrome", "chrome", seg=(28, 6))
    h.torus("UpperChest", c + Vector((0, -0.005, 0)), (0, 1, 0), 0.3 * k, 0.006 * k, "team", "team_emit", seg=(28, 4))
    for ang in (35, 145):
        a = math.radians(ang)
        d = c + Vector((math.cos(a) * 0.3, 0, math.sin(a) * 0.3)) * k
        h.sphere("UpperChest", d, Vector((0.045, 0.045, 0.045)) * k, "ivory", seg=(10, 6))
        h.sphere("UpperChest", d + Vector((0, -0.03, 0)) * k, Vector((0.022, 0.02, 0.022)) * k, "team", "team_emit",
                 seg=(8, 4))
    h.box("UpperChest", p + Vector((0, -0.05, 0.02)) * k, Vector((0.05, 0.1, 0.05)) * k, "chrome", "chrome", bevel=0.3)
    closed_boots(h, "warm", "sage", k)


def halo_repeater(h, W):
    wb = _wbox(h, W)
    wb((0, -0.01, -0.045), (0.03, 0.04, 0.1), "warm", rx=-18, bevel=0.3)
    wb((0, 0.07, 0.035), (0.055, 0.28, 0.085), "ivory", bevel=0.4)
    wb((0, 0.31, 0.035), (0.05, 0.22, 0.06), "sage", bevel=0.4)
    h.cyl("Weapon", W @ Vector((0, 0.42, 0.04)), W @ Vector((0, 0.6, 0.04)), 0.016, 0.02, "chrome", "chrome", seg=8)
    h.sphere("Weapon", W @ Vector((0, 0.08, 0.11)), Vector((0.045, 0.06, 0.045)), "team", "team_emit", seg=(10, 6))
    h.torus("Weapon", W @ Vector((0, 0.6, 0.04)), W.to_3x3() @ Vector((0, 1, 0)), 0.028, 0.006, "sage")
    wb((0, -0.16, 0.025), (0.045, 0.18, 0.075), "ivory", bevel=0.4, taper=(0.9, 0.8))


# ========================================================================= Sable
def sable_parts(h):
    k = _k(h)
    lo, hi, hc, hr, eye_z = _head(h)
    # Hood with one swept-back horn + a blank matte mask with a single team slit.
    hcen = Vector((0, hc.y - 0.01, hc.z + 0.008))
    h.sphere("Head", hcen, Vector((hr.x * 1.3, hr.y * 1.25, hr.z * 1.2)), "charcoal", seg=(18, 12),
             clip=[((0, 0.62, -0.1), (0, 1, -0.3)), ((0, 0, -0.75), (0, 0, -1))])
    h.sphere("Head", Vector((0, hc.y + hr.y * 0.2, hc.z - 0.02)), Vector((hr.x * 1.02, hr.y * 0.95, hr.z * 0.98)),
             "mask", seg=(16, 10), clip=[((0, -0.1, 0), (0, -1, 0))])
    h.box("Head", (0, hi.y + 0.016, eye_z), (hr.x * 1.6, 0.014, 0.011), "team", "team_emit", bevel=0.3)
    h.cyl("Head", Vector((hr.x * 0.6, hc.y - hr.y * 0.4, hc.z + hr.z * 0.8)),
          Vector((hr.x * 1.4, hc.y - hr.y * 2.6, hc.z + hr.z * 1.6)), 0.04 * k, 0.004, "charcoal", seg=8)
    # Long split scarf: two tails trailing ~1.5 m behind (jade lining underneath).
    nk = h.jh("Neck")
    h.torus("Neck", nk + Vector((0, 0.0, 0.02)), (0, 0, 1), 0.075 * k, 0.03 * k, "charcoal", seg=(14, 6))
    bands = [(nk.z, "Neck"), (h.jh("UpperChest").z, "UpperChest"), (h.jh("Chest").z, "Chest"), (h.jh("Spine").z, "Hips")]
    for sx, drop, col in ((-0.05, 0.62, "charcoal"), (0.06, 0.82, "charcoal")):
        a = Vector((sx * k, nk.y - 0.09 * k, nk.z))
        b = Vector((sx * 2.0 * k, nk.y - 1.35 * k, nk.z - drop * k))
        h.box(None, None, (0.11 * k, (a - b).length, 0.012 * k), col, mat=_along(b, a, Vector((0, 0, 1))),
              weights=lambda co: _wz(h, co.z, bands), bevel=0.3)
        h.box(None, None, (0.1 * k, (a - b).length * 0.96, 0.006 * k), "jade",
              mat=_along(b, a, Vector((0, 0, 1))) @ Matrix.Translation((0, 0, -0.008 * k)),
              weights=lambda co: _wz(h, co.z, bands), bevel=0.0)
    # Minimal matte armour: chest plate, chrome calf struts with jade hinges.
    uc = h.jh("UpperChest")
    p, n = h.surface(0, uc.z - 0.05 * k, 1)
    h.box("UpperChest", p + n * 0.02 * k, Vector((0.22, 0.03, 0.16)) * k, "charcoal", bevel=0.35, taper=(0.8, 1.0))
    h.box("UpperChest", p + n * 0.04 * k + Vector((0, 0, -0.05)) * k, Vector((0.16, 0.01, 0.012)) * k, "team", "team",
          bevel=0.0)
    for s in ("L", "R"):
        a, b = h.jl("LowerLeg_" + s, 0.15), h.jl("LowerLeg_" + s, 0.95)
        h.cyl("LowerLeg_" + s, a + Vector((0, -0.06, 0)) * k, b + Vector((0, -0.05, 0)) * k, 0.012 * k, 0.012 * k,
              "chrome", "chrome", seg=6)
        h.sphere("Foot_" + s, h.jh("Foot_" + s) + Vector((0, -0.05, 0.02)) * k, Vector((0.02, 0.02, 0.02)) * k, "jade",
                 "emit", seg=(8, 4))
    closed_boots(h, "charcoal", "jade", k)


def whisperfang(h, W):
    wb = _wbox(h, W)
    wb((0, -0.01, -0.045), (0.028, 0.038, 0.09), "charcoal", rx=-15, bevel=0.3)
    wb((0, 0.07, 0.03), (0.045, 0.2, 0.07), "charcoal", bevel=0.35)
    wb((0, 0.16, -0.045), (0.028, 0.036, 0.08), "charcoal", rx=-10, bevel=0.3)
    h.cyl("Weapon", W @ Vector((0, 0.17, 0.04)), W @ Vector((0, 0.3, 0.04)), 0.013, 0.013, "chrome", "chrome", seg=8)
    wb((0, 0.22, -0.01), (0.006, 0.22, 0.03), "chrome", "chrome", taper=(1.0, 0.2), bevel=0.0)
    wb((0.024, 0.06, 0.03), (0.004, 0.12, 0.02), "team", "team_emit", bevel=0.0)
    wb((0, 0.03, 0.075), (0.02, 0.08, 0.02), "jade", "emit", bevel=0.3)


# ======================================================================= Juniper
def juniper_parts(h):
    k = _k(h)
    lo, hi, hc, hr, eye_z = _head(h)
    # Trapper mask: padded cap, big brass goggles (team lenses), rebreather snout + canisters.
    h.sphere("Head", Vector((0, hc.y - 0.005, hc.z + 0.01)), Vector((hr.x * 1.18, hr.y * 1.14, hr.z * 1.08)), "olive",
             seg=(16, 10), clip=[((0, 0, -0.62), (0, 0, -1))])
    h.sphere("Head", Vector((0, hc.y + hr.y * 0.2, hc.z - 0.02)), Vector((hr.x * 1.02, hr.y * 0.95, hr.z * 0.98)),
             "rubber", seg=(14, 10), clip=[((0, -0.1, 0), (0, -1, 0))])
    for sx in (-1, 1):
        c = Vector((sx * 0.034 * k, hi.y + 0.004, eye_z + 0.004))
        h.cyl("Head", c - Vector((0, 0.01, 0)), c + Vector((0, 0.025, 0)), 0.028 * k, 0.026 * k, "brass", seg=12)
        h.cyl("Head", c + Vector((0, 0.022, 0)), c + Vector((0, 0.03, 0)), 0.021 * k, 0.021 * k, "team", "team_emit",
              seg=12)
    h.box("Head", (0, hi.y + 0.02, eye_z - 0.06), (0.06 * k, 0.06, 0.055 * k), "rubber", bevel=0.4, taper=(0.8, 0.8))
    for sx in (-1, 1):
        h.cyl("Head", Vector((sx * 0.035, hi.y + 0.03, eye_z - 0.075)), Vector((sx * 0.07, hi.y + 0.045, eye_z - 0.085)),
              0.018 * k, 0.018 * k, "mustard", seg=8)
    # Messy bun with quill-darts.
    bun = Vector((0, hc.y - hr.y * 0.6, hc.z + hr.z * 0.9))
    h.sphere("Head", bun, Vector((0.05, 0.05, 0.045)) * k, "hair", seg=(10, 6))
    for ang in (-30, 10, 45):
        a = math.radians(ang)
        h.cyl("Head", bun, bun + Vector((math.sin(a) * 0.12, -0.04, math.cos(a) * 0.12)) * k, 0.004, 0.002, "brass", seg=4)
    # Huge square tool-pack taller than the head (the hook): stickers, spool wheel, folded launcher arm.
    uc = h.jh("UpperChest")
    p, n = h.surface(0, uc.z - 0.05, -1)
    pc = p + Vector((0, -0.16, 0.12)) * k

    def pack_w(co):
        return {"UpperChest": 0.85, "Chest": 0.15}
    h.box(None, pc, Vector((0.42, 0.28, 0.66)) * k, "mustard", bevel=0.18, weights=pack_w)
    h.box(None, pc + Vector((0, -0.145, 0.05)) * k, Vector((0.3, 0.02, 0.18)) * k, "olive", bevel=0.2, weights=pack_w)
    for i, (x, z, col) in enumerate(((-0.12, 0.2, "team"), (0.1, 0.24, "bone"), (0.13, -0.1, "olive"),
                                     (-0.1, -0.2, "bone"))):
        h.box(None, pc + Vector((x, -0.142, z)) * k, Vector((0.07, 0.01, 0.05)) * k, col, "team" if col == "team" else "flat",
              bevel=0.0, weights=pack_w)
    h.cyl(None, pc + Vector((0.21, 0, 0.05)) * k, pc + Vector((0.27, 0, 0.05)) * k, 0.12 * k, 0.12 * k, "rubber",
          seg=14, weights=pack_w)
    h.cyl(None, pc + Vector((0.265, 0, 0.05)) * k, pc + Vector((0.275, 0, 0.05)) * k, 0.05 * k, 0.05 * k, "team",
          "team_emit", seg=10, weights=pack_w)
    h.box(None, pc + Vector((-0.24, 0.0, 0.12)) * k, Vector((0.05, 0.08, 0.5)) * k, "olive", bevel=0.3, weights=pack_w)
    for sx in (-1, 1):
        a, b = h.surface(sx * 0.1 * k, uc.z + 0.08, 1)[0], h.surface(sx * 0.1 * k, h.belt_z + 0.05, 1)[0]
        h.box(None, None, ((a - b).length, 0.04 * k, 0.012 * k), "rubber", mat=_along(a, b, Vector((0, 1, 0))) @
              Matrix.Rotation(math.pi / 2, 4, "Z"), weights=lambda co: _wz(h, co.z, [(uc.z, "UpperChest"),
                                                                                   (h.belt_z, "Spine")]), bevel=0.2)
    # Utility belt of trap canisters (stripe + letter colours).
    for i, x in enumerate((-0.15, -0.08, 0.08, 0.15)):
        p, n = h.surface(x * k, h.belt_z - 0.01, 1)
        h.cyl("Hips", p + n * 0.03 * k - Vector((0, 0, 0.04)) * k, p + n * 0.03 * k + Vector((0, 0, 0.04)) * k,
              0.022 * k, 0.022 * k, "olive", seg=8)
        h.cyl("Hips", p + n * 0.03 * k, p + n * 0.03 * k + Vector((0, 0, 0.012)) * k, 0.023 * k, 0.023 * k,
              ("team", "mustard", "bone", "team")[i], "team" if i in (0, 3) else "flat", seg=8)
    closed_boots(h, "rubber", "mustard", k)


def tackhammer(h, W):
    wb = _wbox(h, W)
    wb((0, -0.01, -0.045), (0.03, 0.04, 0.095), "wood", rx=-15, bevel=0.3)
    wb((0, -0.005, -0.075), (0.012, 0.09, 0.03), "brass", bevel=0.3)
    wb((0, 0.08, 0.03), (0.05, 0.26, 0.075), "olive", bevel=0.3)
    h.cyl("Weapon", W @ Vector((0, 0.2, 0.04)), W @ Vector((0, 0.66, 0.04)), 0.014, 0.014, "rubber", seg=8)
    wb((0, 0.34, 0.02), (0.045, 0.22, 0.05), "wood", bevel=0.4)
    wb((0, 0.12, -0.06), (0.035, 0.07, 0.11), "mustard", bevel=0.3)
    h.cyl("Weapon", W @ Vector((-0.04, 0.02, 0.07)), W @ Vector((0.04, 0.02, 0.07)), 0.035, 0.035, "brass", seg=12)
    h.cyl("Weapon", W @ Vector((0, 0.04, 0.09)), W @ Vector((0, 0.6, 0.06)), 0.002, 0.002, "team", "team_emit", seg=3)
    wb((0, -0.17, 0.02), (0.045, 0.2, 0.08), "wood", bevel=0.35, taper=(0.9, 0.75))


# =========================================================================== Hex
def hex_parts(h):
    k = _k(h)
    lo, hi, hc, hr, eye_z = _head(h)
    # Oversized hood with cat-ear headset + antennae; a screen face showing a glyph.
    hcen = Vector((0, hc.y - 0.012, hc.z + 0.004))
    h.sphere("Head", hcen, Vector((hr.x * 1.35, hr.y * 1.3, hr.z * 1.22)), "hoodie", seg=(18, 12),
             clip=[((0, 0.6, -0.05), (0, 1, -0.2)), ((0, 0, -0.85), (0, 0, -1))])
    scr = Vector((0, hi.y + 0.01, eye_z - 0.02))
    h.box("Head", scr, (hr.x * 1.75, 0.03, hr.z * 1.25), "screen", bevel=0.25)
    for sx in (-1, 1):
        h.box("Head", scr + Vector((sx * 0.03, 0.017, 0.012)) * k, (0.03 * k, 0.006, 0.008 * k), "lime", "emit",
              rot=(0, sx * 25, 0), bevel=0.0)
    h.box("Head", scr + Vector((0, 0.017, -0.03)) * k, (0.035 * k, 0.006, 0.007 * k), "lime", "emit", bevel=0.0)
    for sx in (-1, 1):
        base = Vector((sx * hr.x * 0.9, hc.y - 0.01, hc.z + hr.z * 1.0))
        h.cyl("Head", base, base + Vector((sx * 0.03, 0, 0.11)) * k, 0.045 * k, 0.004, "hoodie", seg=4)
        h.cyl("Head", base + Vector((sx * 0.012, 0.012, 0.0)), base + Vector((sx * 0.035, 0.012, 0.085)) * 1.0,
              0.026 * k, 0.003, "lime", seg=4)
        h.cyl("Head", base + Vector((sx * 0.01, -0.02, 0)), base + Vector((sx * 0.07, -0.05, 0.2)) * 1.0, 0.004, 0.003,
              "chrome", "chrome", seg=4)
        h.sphere("Head", base + Vector((sx * 0.07, -0.05, 0.2)), Vector((0.012, 0.012, 0.012)), "team", "team_emit",
                 seg=(6, 4))
    # Lime drawstrings + patches on the hoodie.
    nk = h.jh("Neck")
    for sx in (-1, 1):
        p, n = h.surface(sx * 0.04 * k, nk.z - 0.06 * k, 1)
        h.cyl("UpperChest", p + n * 0.035, p + n * 0.035 - Vector((0, 0, 0.16)) * k, 0.006, 0.006, "lime", seg=4)
    p, n = h.surface(0.09 * k, h.jh("Chest").z, 1)
    h.box("Chest", p + n * 0.035, (0.07 * k, 0.01, 0.06 * k), "team", "team", bevel=0.2)
    # Chrome wrist decks with floating holo-panels (team glow).
    for s, sg in (("L", -1), ("R", 1)):
        w = h.jl("LowerArm_" + s, 0.8)
        h.box("LowerArm_" + s, w + Vector((0, 0, 0.035)) * k, Vector((0.07, 0.08, 0.025)) * k, "chrome", "chrome",
              bevel=0.3)
        h.box("LowerArm_" + s, w + Vector((sg * 0.09, 0.02, 0.1)) * k, Vector((0.004, 0.11, 0.08)) * k, "team",
              "team_emit", rot=(0, 0, 0), bevel=0.0)
    # Oversized sneakers with lime soles.
    for s in ("L", "R"):
        lo_, hi_ = h.bbox("Foot_" + s, 0.4)
        c = (lo_ + hi_) / 2
        sz = hi_ - lo_
        h.box("Foot_" + s, (c.x, c.y + 0.02, lo_.z + sz.z * 0.55), (sz.x + 0.05, sz.y + 0.07, sz.z + 0.04), "sneaker",
              bevel=0.6, taper=(0.9, 0.75))
        h.box("Foot_" + s, (c.x, c.y + 0.02, lo_.z + 0.01), (sz.x + 0.056, sz.y + 0.076, 0.03), "lime", bevel=0.4)


def glitchcaster(h, W):
    wb = _wbox(h, W)
    wb((0, -0.01, -0.045), (0.032, 0.042, 0.095), "hoodie", rx=-15, bevel=0.3)
    wb((0, 0.05, 0.03), (0.06, 0.18, 0.085), "screen", bevel=0.35)
    for i in range(4):
        y = 0.15 + i * 0.045
        off = (0.006 * (-1) ** i, 0, 0.004 * (i % 2))
        h.cyl("Weapon", W @ Vector((off[0], y, 0.035 + off[2])), W @ Vector((off[0], y + 0.035, 0.035 + off[2])),
              0.034, 0.034, ("lime", "hoodie")[i % 2], "emit" if i % 2 == 0 else "flat", seg=6)
    wb((0.032, 0.03, 0.03), (0.004, 0.06, 0.04), "team", "team", bevel=0.0)
    wb((-0.032, 0.07, 0.04), (0.004, 0.05, 0.03), "lime", bevel=0.0)
    wb((0, 0.05, -0.06), (0.03, 0.05, 0.08), "hoodie", rx=10, bevel=0.3)


# ======================================================================== table
def _stance(**kw):
    s = {"grip_r": (0.10, 0.20, 1.20), "pivot": (0.14, 0.02, 1.40), "twist": -26, "clav_l": -8,
         "pole_r": (1, -0.4, -1), "pole_l": (-0.6, -0.2, -1), "two_handed": True, "grip_l": (0, 0.26, 0.0),
         "hand_r_y": (0, 0.55, -1), "hand_r_n": (-1, 0, 0), "hand_l_y": (1, 0.25, 0.1), "hand_l_n": (0, 0, 1),
         "mag": (0, 0.12, -0.1)}
    s.update(kw)
    return s


def _hero(key, height, targets, palette, spec, parts, weapon, stance, casts, **extra):
    cuts, regions, shells = generic(spec)
    d = {"key": key, "height": height, "head_scale": extra.pop("head_scale", 0.95), "decimate": 0.19,
         "targets": targets, "palette": dict(palette, team=TEAM, eye="#101014"), "cuts": cuts, "regions": regions,
         "shells": shells, "parts": parts, "weapon": weapon, "stance": stance, "casts": casts}
    d.update(extra)
    return d


HEROES = {
    "brannoc": _hero(
        "brannoc", 2.2,
        {"african-male-young": 0.6, "caucasian-male-young": 0.4, "universal-male-young-maxmuscle-averageweight": 1.0,
         "male-young-maxmuscle-averageweight-idealproportions": 0.6},
        {"teal": "#2F8F87", "soot": "#4E4842", "iron": "#8C939C", "bone": "#E8D9B0", "gold": "#E0AC48"},
        {"paint": {"head": "soot", "torso": "soot", "sleeves": "soot", "gloves": "iron", "legs": "soot",
                   "boots": "soot", "belt": "iron", "forearm": "teal"}, "sleeve_t": 0.85, "boot_t": 0.35,
         "torso_shell": {"offset": 0.035, "color": "teal", "rim": "iron", "arms": True},
         "boot_shell": (0.02, "soot", "iron"), "thigh_shell": (0.03, "teal", "iron")},
        brannoc_parts, "ironmaw",
        _stance(grip_r=(0.14, 0.26, 1.0), pivot=(0.16, 0.02, 1.3), twist=-18, grip_l=(0, 0.33, -0.03),
                mag=(0, 0.33, -0.05)),
        [("thrust", [("x", -8)]), ("raise", []), ("sweep", [("z", 10)]), ("raise", [("x", 10)])],
        head_scale=0.85, widen=(1.16, 0.3), gait={"run_amp": 34, "lean": 5}),
    "liora": _hero(
        "liora", 1.78,
        {"caucasian-female-young": 0.5, "african-female-young": 0.5, "universal-female-young-averagemuscle-minweight": 0.5,
         "female-young-averagemuscle-averageweight-idealproportions": 1.0},
        {"ivory": "#DCCFB4", "sage": "#6FBF8A", "warm": "#56606E", "chrome": "#C9D4E2", "hair": "#8A5A3C"},
        {"paint": {"head": "warm", "torso": "warm", "sleeves": "ivory", "gloves": "warm", "legs": "warm",
                   "boots": "warm", "belt": "sage", "forearm": "sage"}, "sleeve_t": 0.5, "boot_t": 0.3,
         "torso_shell": {"offset": 0.018, "color": "ivory", "rim": "sage", "arms": True},
         "boot_shell": (0.012, "warm", "sage")},
        liora_parts, "halo_repeater", _stance(),
        [("thrust", []), ("raise", [("x", 6)]), ("plant", [("x", -10)]), ("raise", [("x", 12)])]),
    "sable": _hero(
        "sable", 1.70,
        {"asian-female-young": 0.5, "caucasian-female-young": 0.5, "universal-female-young-maxmuscle-minweight": 0.8,
         "female-young-maxmuscle-minweight-idealproportions": 1.0},
        {"charcoal": "#333A46", "jade": "#3FD69C", "chrome": "#C9D4E2", "mask": "#4A5260"},
        {"paint": {"head": "charcoal", "torso": "charcoal", "sleeves": "charcoal", "gloves": "charcoal",
                   "legs": "charcoal", "boots": "charcoal", "belt": "jade", "forearm": "charcoal"},
         "boot_t": 0.3, "boot_shell": (0.01, "charcoal", "jade")},
        sable_parts, "whisperfang",
        _stance(grip_r=(0.09, 0.24, 1.08), pivot=(0.12, 0.04, 1.28), twist=-22, grip_l=(0, 0.16, -0.02),
                mag=(0, 0.16, -0.06)),
        [("thrust", [("x", -10)]), ("sweep", [("z", 12)]), ("plant", [("x", -12)]), ("raise", [("x", 6)])],
        gait={"run_amp": 42, "lean": 14}),
    "juniper": _hero(
        "juniper", 1.72,
        {"caucasian-female-young": 0.7, "african-female-young": 0.3, "universal-female-young-averagemuscle-minweight": 0.3,
         "female-young-averagemuscle-averageweight-idealproportions": 1.0},
        {"mustard": "#E6A91E", "olive": "#6E8238", "rubber": "#3E342C", "brass": "#C8963E", "chrome": "#C9D4E2",
         "bone": "#EFE3C4", "hair": "#7A3B22", "wood": "#7A5232"},
        {"paint": {"head": "rubber", "torso": "olive", "sleeves": "olive", "gloves": "rubber", "legs": "rubber",
                   "boots": "rubber", "belt": "mustard", "forearm": "olive", "forearm_L": "chrome"},
         "sleeve_t": 0.75, "boot_t": 0.4, "torso_shell": {"offset": 0.016, "color": "olive", "rim": "mustard"},
         "boot_shell": (0.013, "rubber", "mustard")},
        juniper_parts, "tackhammer", _stance(grip_l=(0, 0.3, -0.01)),
        [("plant", [("x", -12)]), ("throw", [("z", 10)]), ("plant", [("x", -10)]), ("raise", [("x", 8)])]),
    "hex": _hero(
        "hex", 1.72,
        {"caucasian-male-young": 0.25, "caucasian-female-young": 0.25, "asian-male-young": 0.25,
         "asian-female-young": 0.25, "universal-male-young-averagemuscle-minweight": 0.4},
        {"hoodie": "#24242C", "lime": "#B6F23A", "screen": "#0E1416", "chrome": "#C9D4E2", "legs": "#4A4A56",
         "sneaker": "#E9E9F0"},
        {"paint": {"head": "hoodie", "torso": "hoodie", "sleeves": "hoodie", "gloves": "hoodie", "legs": "hoodie",
                   "shins": "legs", "boots": "legs", "belt": "lime", "forearm": "hoodie"},
         "shorts_t": 0.55, "boot_t": 0.6, "glove_t": 0.95,
         "torso_shell": {"offset": 0.03, "color": "hoodie", "rim": "lime", "arms": True, "hips": True}},
        hex_parts, "glitchcaster",
        _stance(grip_r=(0.1, 0.27, 1.12), pivot=(0.12, 0.04, 1.32), twist=-16, grip_l=(0, 0.06, -0.06),
                hand_l_y=(0.3, 0.3, -1), hand_l_n=(1, 0, 0), mag=(0, 0.05, -0.08)),
        [("thrust", []), ("sweep", [("z", 12)]), ("throw", [("z", 8)]), ("raise", [("x", 10)])],
        head_scale=1.02, gait={"run_amp": 40, "lean": 10}),
}

WEAPONS = {"ironmaw": ironmaw, "halo_repeater": halo_repeater, "whisperfang": whisperfang, "tackhammer": tackhammer,
           "glitchcaster": glitchcaster}
