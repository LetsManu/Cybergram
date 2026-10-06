"""Wardling v2 (owner redesign 2026-10-06): a rigged mini-soldier on the hero pipeline.

Brief: docs/assets/wardling.md. A knee-to-waist-high (1.05 m) armoured construct
soldier, built and animated like a hero (body_gen skeleton, mocap locomotion,
shoot / hit / death clips, painted bake, ink outline), so it walks, runs, aims
and falls instead of hopping. Never reads as a hero (art bible V4): chibi
proportions (big helmet, short legs, broad chest), a single holo-LED visor eye,
the team mana core in a chrome cage on the chest and a reactor on the back.

Two faction skins of one design (art bible §5.3): `wardling_c` Concord (white
porcelain + gold) and `wardling_s` Syndicate (black iron + brass + rust suit).
Tier / class / Elite pieces are separate baked props attached to bones at runtime
(tools/art/world/wardling_props.py), so one rig serves every tier.

Space: Blender metres, X = character right, Y = forward, Z = up, feet at Z = 0.
Lengths in the body / stance tables are hero space (1.85 m) and scale by k.
Build: /tmp/venv/bin/python tools/art/build_hero.py wardling_c --out assets/models/wardlings
"""
import math

from mathutils import Matrix, Vector

from hero_defs import TEAM, _rx
from hero_defs_gen_a import _band, _bolt, _generic, _head, _k, _on, _side, _yaw

HEIGHT = 1.05

PAL_C = {"shell": "#F1ECE4", "shell_dk": "#C9C2B8", "trim": "#D6B25E", "suit": "#4A5068", "ink": "#1B1E2E",
         "gun": "#3B4052", "chrome": "#C9D4E2", "rubber": "#2A2C36", "eye": "#F4F7FF", "team": TEAM}
PAL_S = {"shell": "#5E5866", "shell_dk": "#3C3843", "trim": "#C99A55", "suit": "#8A4A30", "ink": "#120E10",
         "gun": "#4C464C", "chrome": "#D5C8B4", "rubber": "#221E22", "eye": "#F4F7FF", "team": TEAM}

SPEC = {"paint": {"head": "ink", "torso": "suit", "sleeves": "suit", "gloves": "gun", "legs": "suit",
                  "boots": "shell", "belt": "trim", "forearm": "shell"}, "sleeve_t": 0.55, "boot_t": 0.45,
        "glove_t": 0.75,
        "torso_shell": {"offset": 0.022, "color": "shell", "rim": "trim", "arms": True},
        "boot_shell": (0.018, "shell", "trim"), "thigh_shell": (0.016, "shell", "trim")}

BODY = {"leg": 0.80, "thigh_frac": 0.5, "ankle": 0.11, "torso": 0.60, "neck": 0.035, "neck_r": 0.075,
        "head_h": 0.36, "head_w": 0.29, "head_d": 0.31,
        "shoulder_w": 0.58, "chest_w": 0.50, "chest_d": 0.36, "waist_w": 0.40, "waist_d": 0.30,
        "hip_w": 0.44, "hip_d": 0.30, "hip_joint_w": 0.25, "upper_arm": 0.25, "forearm": 0.23,
        "arm_r": 0.078, "forearm_r": 0.085, "wrist_r": 0.055, "thigh_r": 0.115, "knee_r": 0.085,
        "calf_r": 0.1, "ankle_r": 0.065, "hand": 1.75, "foot": 1.7, "boot_r": 1.45,
        "deltoid": 0.6, "pecs": 0.2, "glutes": 0.3, "calves": 0.3, "forearms": 0.6, "traps": 0.6,
        "muscle": 0.6, "boxy": 2.9, "chest_lift": 0.02, "arm_angle": 46.0, "stance": 0.07}


def wardling_parts(h):
    """Helmet (the focal point), chest core cage, backpack reactor + fin, pauldrons,
    belt kit, knee and elbow guards. Geometry only; the paint does wear and stencils."""
    syn = h.d.get("faction") == "s"
    k = _k(h)
    lo, hi, hc, hr, eye_z = _head(h)
    # ------------------------------------------------------------ helmet: oversized dome
    C = Vector((0, hc.y - 0.01 * k, hc.z + 0.03 * k))
    R = Vector((hr.x * 1.5, hr.y * 1.4, hr.z * 1.32))
    h.sphere("Head", C, R, "shell", seg=(28, 16), clip=[((0, 0, -0.5), (0, 0, -1))])
    _band(h, "Head", C, R * 1.025, "trim", seg=(28, 16), z=(-0.5, -0.4))                          # lower rim
    _band(h, "Head", C, R * 1.02, "shell_dk", seg=(28, 16), x=(-0.12, 0.12), z=(0.2, None))       # centre ridge
    # visor: a wide ink slot across the front with ONE holo-LED eye (the read at 30 m)
    V = R * 1.03
    _band(h, "Head", C, V, "ink", seg=(28, 16), z=(-0.22, 0.08), y=(0.35, None))
    _band(h, "Head", C, V * 1.012, "trim", seg=(28, 16), z=(0.08, 0.13), y=(0.3, None))           # brow lip
    ep, en = _on(C, V, 0.0, C.z - R.z * 0.07, 0.003)
    h.sphere("Head", ep, Vector((0.055, 0.016, 0.03)) * k, "eye", "emit", seg=(14, 8), rot=(0, 0, _yaw(en)))
    h.sphere("Head", ep - en * 0.003, Vector((0.07, 0.012, 0.042)) * k, "gun", seg=(14, 8), rot=(0, 0, _yaw(en)))
    # jaw guard with vent slits
    J = Vector((0, C.y + R.y * 0.35, C.z - R.z * 0.42))
    JR = Vector((R.x * 0.72, R.y * 0.62, R.z * 0.3))
    _band(h, "Head", J, JR, "shell_dk", seg=(20, 10), y=(0.0, None))
    for i in range(3):
        vp, vn = _on(J, JR, 0.0, J.z + JR.z * (0.3 - i * 0.28), 0.003)
        h.box("Head", vp, Vector((0.07, 0.008, 0.012)) * k, "rubber", rot=(0, 0, _yaw(vn)), bevel=0.2)
    # side "ear" housings with a team ring and an antenna nub on the left
    for sx in (-1, 1):
        sp, sn = _side(C, R, sx, C.y - R.y * 0.05, C.z - R.z * 0.12)
        h.cyl("Head", sp - sn * 0.01, sp + sn * 0.03 * k, 0.07 * k, 0.065 * k, "shell_dk", seg=16)
        h.torus("Head", sp + sn * 0.032 * k, sn, 0.055 * k, 0.007 * k, "team", "team_emit", seg=(18, 4))
        _bolt(h, "Head", sp + sn * 0.036 * k, sn, 0.012 * k, "chrome", "chrome")
        if syn:  # brass rivets along the rim
            for i in range(4):
                rp, rn = _side(C, R, sx, C.y + R.y * (0.4 - i * 0.3), C.z - R.z * 0.42, 0.0)
                _bolt(h, "Head", rp, rn, 0.009 * k, "trim", "chrome")
    sp, sn = _side(C, R, -1, C.y - R.y * 0.05, C.z - R.z * 0.12)
    a0 = sp + sn * 0.03 * k + Vector((0, -0.01, 0.05)) * k
    h.cyl("Head", a0, a0 + Vector((0, -0.04, 0.16)) * k, 0.008 * k, 0.005 * k, "chrome", "chrome", seg=6)
    h.sphere("Head", a0 + Vector((0, -0.04, 0.16)) * k, Vector((0.014, 0.014, 0.014)) * k, "team", "team_emit",
             seg=(8, 5))
    # ------------------------------------------------------------ chest: the mana core in a cage
    ch = h.jh("Chest")
    uc = h.jh("UpperChest")
    front = max(v.y for v in (ch, uc)) + 0.17 * k
    cc = Vector((0, front, (ch.z + uc.z) / 2))
    h.sphere("UpperChest", cc, Vector((0.07, 0.04, 0.07)) * k, "team", "team_emit", seg=(14, 8))
    h.torus("UpperChest", cc + Vector((0, 0.012, 0)) * k, Vector((0, 1, 0)), 0.08 * k, 0.014 * k, "chrome", "chrome",
            seg=(18, 5))
    for dx in (-0.035, 0.0, 0.035):
        h.box("UpperChest", cc + Vector((dx, 0.045, 0)) * k, Vector((0.012, 0.012, 0.15)) * k, "chrome", "chrome",
              bevel=0.3)
    # chest plate rim + stencil serial plate (Concord) / crew tag plate (Syndicate)
    h.box("UpperChest", cc + Vector((0.13, -0.01, 0.06)) * k, Vector((0.08, 0.012, 0.035)) * k,
          "ink" if not syn else "trim", rot=(0, 0, 12), bevel=0.3)
    # ------------------------------------------------------------ back: reactor pack + fin
    back = min(v.y for v in (ch, uc)) - 0.2 * k
    bp = Vector((0, back, (ch.z + uc.z) / 2))
    h.cyl("UpperChest", bp + Vector((0, 0, -0.13)) * k, bp + Vector((0, 0, 0.13)) * k, 0.11 * k, 0.1 * k, "gun", seg=14)
    h.cyl("UpperChest", bp + Vector((0, -0.005, -0.08)) * k, bp + Vector((0, -0.005, 0.08)) * k, 0.112 * k,
          0.112 * k, "team", "team_emit", seg=14, caps=False)
    for z in (-0.14, 0.14):
        h.cyl("UpperChest", bp + Vector((0, 0, z)) * k, bp + Vector((0, 0, z + (0.03 if z > 0 else -0.03))) * k,
              0.125 * k, 0.115 * k, "shell", seg=14)
    for sx in (-1, 1):  # straps over the shoulders
        h.box("UpperChest", bp + Vector((sx * 0.1, 0.09, 0.1)) * k, Vector((0.035, 0.18, 0.025)) * k, "rubber",
              rot=(-20, 0, 0), bevel=0.3)
    fin = bp + Vector((0, -0.06, 0.24)) * k
    h.box("UpperChest", fin, Vector((0.03, 0.14, 0.18)) * k, "shell", rot=(-30, 0, 0), bevel=0.3, taper=(0.8, 0.5))
    h.box("UpperChest", fin + Vector((0, -0.07, -0.04)) * k, Vector((0.04, 0.02, 0.02)) * k, "trim", "chrome",
          rot=(-30, 0, 0), bevel=0.3)                                                             # tier I pip
    # ------------------------------------------------------------ pauldrons
    for s, sg in (("L", 1.0 if h.jh("UpperArm_L").x > 0 else -1.0), ("R", 1.0 if h.jh("UpperArm_R").x > 0 else -1.0)):
        sh = h.jh("UpperArm_" + s)
        pc = sh + Vector((0.015 * sg, 0, 0.04)) * k
        h.sphere("Clavicle_" + s, pc, Vector((0.12, 0.13, 0.095)) * k, "shell", seg=(16, 10),
                 rot=(0, -20 * -sg, 0), clip=[((0, 0, -0.2), (0, 0, -1))])
        h.sphere("Clavicle_" + s, pc + Vector((0.01 * sg, 0, -0.03)) * k, Vector((0.126, 0.136, 0.08)) * k, "trim",
                 seg=(16, 10), rot=(0, -20 * -sg, 0), clip=[((0, 0, -0.25), (0, 0, -1)), ((0, 0, 0.15), (0, 0, 1))])
        # team band on the pauldron: the team reads from the front, where the arms and gun hide the core
        h.sphere("Clavicle_" + s, pc + Vector((0.006 * sg, 0, 0.0)) * k, Vector((0.123, 0.133, 0.097)) * k, "team",
                 "team", seg=(16, 10), rot=(0, -20 * -sg, 0), clip=[((0, 0, 0.1), (0, 0, 1)), ((0, 0, -0.05), (0, 0, -1))])
    # ------------------------------------------------------------ belt kit + guards
    bz = h.belt_z
    for sx, w in ((-1, 0.07), (1, 0.06), (0, 0.09)):
        if sx == 0:
            p = Vector((0, h.jh("Hips").y - 0.17 * k, bz - 0.03 * k))
        else:
            p = Vector((sx * 0.2 * k, h.jh("Hips").y + 0.08 * k, bz - 0.04 * k))
        h.box("Hips", p, Vector((w, 0.05, 0.07)) * k, "rubber" if sx else "gun", bevel=0.35)
    for s in ("L", "R"):
        kn = h.jh("LowerLeg_" + s)
        h.sphere("LowerLeg_" + s, kn + Vector((0, 0.07, 0.01)) * k, Vector((0.075, 0.05, 0.07)) * k, "trim", seg=(12, 8))
        el = h.jh("LowerArm_" + s)
        h.sphere("LowerArm_" + s, el + Vector((0, -0.05, 0)) * k, Vector((0.06, 0.05, 0.055)) * k, "shell_dk",
                 seg=(12, 8))


def ward_blaster(h, W):
    """Compact two-hand mana blaster: boxy receiver, short shrouded barrel with a team
    emitter, a crystal cell magazine, stubby stock. Weapon space: origin = right grip,
    +Y barrel, +Z up."""
    k = _k(h) * 1.25  # chunkier than a scaled hero gun (toy-soldier read)

    def wb(c, s, col, ch="flat", **kw):
        h.box("Weapon", None, Vector(s) * k, col, ch, mat=W @ Matrix.Translation(Vector(c) * k) @ _rx(kw.pop("rx", 0)),
              **kw)

    def cyl(a, b, r0, r1, col, ch="flat", seg=10):
        h.cyl("Weapon", W @ (Vector(a) * k), W @ (Vector(b) * k), r0 * k, r1 * k, col, ch, seg=seg)
    wb((0, -0.01, -0.06), (0.04, 0.05, 0.12), "rubber", rx=-12, bevel=0.35)       # grip
    wb((0, 0.08, 0.03), (0.07, 0.26, 0.09), "gun", bevel=0.35)                    # receiver
    wb((0, 0.08, 0.08), (0.05, 0.2, 0.015), "shell", bevel=0.3)                    # top rail plate
    wb((0, -0.12, 0.02), (0.05, 0.14, 0.07), "shell", bevel=0.35, taper=(0.8, 0.7), rx=180)  # stock
    cyl((0, 0.2, 0.035), (0, 0.4, 0.035), 0.032, 0.03, "shell_dk", seg=12)        # shroud
    cyl((0, 0.4, 0.035), (0, 0.46, 0.035), 0.022, 0.018, "chrome", "chrome", seg=10)
    cyl((0, 0.46, 0.035), (0, 0.48, 0.035), 0.016, 0.01, "team", "team_emit", seg=10)  # emitter
    for y in (0.24, 0.3, 0.36):
        h.torus("Weapon", W @ (Vector((0, y, 0.035)) * k), W.to_3x3() @ Vector((0, 1, 0)), 0.034 * k, 0.005 * k,
                "trim", "chrome", seg=(12, 4))
    wb((0, 0.11, -0.05), (0.035, 0.06, 0.07), "chrome", "chrome", bevel=0.3)      # cell housing
    wb((0, 0.11, -0.05), (0.04, 0.035, 0.05), "team", "team_emit", bevel=0.3)     # crystal cell
    wb((0, 0.03, -0.015), (0.014, 0.06, 0.007), "ink", bevel=0.3)                 # trigger guard


def wardling_idle(p, ph, f):
    """Ready stance: feet apart, knees bent, slight forward lean, small breathing bob."""
    from hero_anims import legs
    w = math.sin(ph)
    legs(p, 0, 0, 0)
    for s, a in (("L", -6), ("R", 6)):
        p.rot("UpperLeg_" + s, [("x", 14), ("z", a)])
        p.rot("LowerLeg_" + s, [("x", -24)])
        p.rot("Foot_" + s, [("x", 10)])
    p.hips((0, 0, -0.03 * p.k + 0.004 * w * p.k))
    p.rot("Spine", [("x", 6 + 1.0 * w)])
    p.rot("Chest", [("x", 3 + 0.6 * w)])


def _entry(key, pal, faction):
    cuts, regions, shells = _generic(SPEC)
    return {
        "key": key, "pipeline": "gen", "faction": faction, "height": HEIGHT,
        "lod_tris": 2500,  # far LOD (beyond RiggedHeroModel.LOD_M): ~100 on screen stay cheap
        "body": dict(BODY),
        "paint": {"hatch_density": 0.5, "hatch_threshold": -0.05, "uv_margin": 0.0015, "uv_max_tries": 30,
                  "shader": {"hatch_strength": 0.1}},
        "palette": dict(pal), "cuts": cuts, "regions": regions, "shells": shells,
        "parts": wardling_parts, "weapon": "ward_blaster", "cloth": [],
        # Two-handed, gun at the belly: a squat, ready soldier (hero space, scaled by k).
        "stance": {"grip_r": (0.16, 0.30, 1.05), "pivot": (0.17, 0.02, 1.28), "twist": -20, "clav_l": -8,
                   "pole_r": (1, -0.4, -1), "pole_l": (-0.6, -0.2, -1), "two_handed": True,
                   "grip_l": (-0.06, 0.30, 0.02), "hand_r_y": (0, 0.55, -1), "hand_r_n": (-1, 0, 0),
                   "hand_l_y": (0.3, 0.3, -1), "hand_l_n": (1, 0, 0), "mag": (0, 0.1, -0.06)},
        "idle": wardling_idle,
        "gait": {"run_amp": 42, "lean": 12},
        "casts": [("thrust", [("x", -8)]), ("raise", []), ("sweep", [("z", 10)]), ("raise", [("x", 10)])],
    }


HEROES = {"wardling_c": _entry("wardling_c", PAL_C, "c"), "wardling_s": _entry("wardling_s", PAL_S, "s")}
WEAPONS = {"ward_blaster": ward_blaster}
