"""W19-VM first-person viewmodel definitions (tools/art/build_fp.py).

One entry per hero. Every FP set is built from the hero's OWN weapon builder
(hero_defs.WEAPONS[...], the same function as the third-person glb), at FP detail.
Space: Blender eye space, metres. Eye at the origin, X = right, Y = forward, Z = up.
Weapon space (as in the hero pipeline): origin = right grip, +Y barrel, +Z up.

Keys
  hero        3P hero key (palette, paint, weapon builder via its def)
  weapon      key into hero_defs.WEAPONS (None = the hero def's weapon)
  grip        right grip origin in eye space at idle
  weapon_rot  idle weapon (pitch x, roll y, yaw z) in degrees
  hand_scale  glove scale (Borderlands chunk; 1.0 = a 1.85 m hero's hand)
  grip_shapes rounded boxes the right hand wraps: (centre, size, rx deg, radius), weapon space
  hand_r      right hand on the grip: middle knuckle position, finger dir, back-of-hand dir (weapon space)
  two_handed  True: the left hand holds `hand_l` on `grip_l_shapes` (weapon space)
  left_idle   one-handed heroes: left hand (wrist pos, finger dir, back dir) in eye space + shape
  mag         reload part: {"center", "axis", "region": fn(p) -> bool (weapon space)}; spins/slides in clips
  reload      reload choreography: "spool" (re-thread), "mag" (drop and seat a magazine)
  sockets     E13 mount / fx markers in weapon space (socket_core, _barrel, _frame, _chamber, fx_muzzle, grip_l)
  arm         glove + sleeve: "glove" colour, "bands" [(d0, d1, colour, offset, flare, rim colour|None)] along
              the forearm from the wrist, "plate" knuckle plate colour, extras fn(h, side, add) for trims
  detail      optional fn(h, W) adding FP-only weapon detail (seen at 30 cm)
  paint       hero_paint overrides for the FP bake (merged over the hero's own paint)
  fallback    True = built against the OLD weapon (regenerate when the hero's new weapon lands)
"""
import math

from mathutils import Matrix, Vector

# FP paint: the key light comes from above and behind the eye (we see the backs of the
# hands and the top / sides of the gun), no height falloff, finer hatching for 30 cm views.
FP_PAINT = {"key_dir": (0.35, -0.45, 1.0), "top": 0.0, "hatch_spacing": 0.011, "ao_dist": 0.012,
            "hatch_density": 0.45, "hatch_threshold": -0.08, "ink_px": 3, "normal_bump": 0.35, "grit": 0.04}


def _vesper_detail(h, W):
    """Vesper FP extras: gold filigree rails along the shuttle, brass screws, spool
    end-cap spokes, a carved grip wrap. Small, so they only read in first person."""
    from hero_defs import _rx

    def wb(c, s, col, ch="flat", **kw):
        h.box("Weapon", None, s, col, ch, mat=W @ Matrix.Translation(Vector(c)) @ _rx(kw.pop("rx", 0)), **kw)
    for sx in (-1, 1):
        wb((sx * 0.0262, 0.05, 0.045), (0.003, 0.17, 0.006), "gold", bevel=0.3)            # filigree rail
        wb((sx * 0.0262, 0.05, 0.017), (0.003, 0.12, 0.004), "gold", bevel=0.3)
        for y in (-0.03, 0.13):                                                             # screws
            h.cyl("Weapon", W @ Vector((sx * 0.025, y, 0.03)), W @ Vector((sx * 0.029, y, 0.03)), 0.005, 0.005,
                  "chrome", "chrome", seg=8)
        for i in range(4):                                                                  # spool spokes
            a = math.pi * i / 4
            wb((sx * 0.0505, 0.06, 0.035), (0.003, 0.09 * abs(math.cos(a)) + 0.004, 0.004), "gold", bevel=0.2,
               rx=math.degrees(a))
    for i in range(4):                                                                      # grip wrap
        wb((0, -0.012 - 0.003 * i, -0.02 - 0.024 * i), (0.035, 0.048, 0.006), "trim", rx=-14, bevel=0.4)


def _vesper_arm_extras(h, side, add):
    """A team-lit thread ring on the left middle finger (the Loom threads end at her
    left hand in third person)."""
    if side == "L":
        add.ring_on("Middle", 0, 0.45, "team", "team_emit", 0.0035)


HEROES = {
    "vesper": {
        "hero": "vesper",
        "weapon": "threadcaster_w16",
        "grip": (0.155, 0.34, -0.205),
        "weapon_rot": (3.0, -4.0, 3.5),
        "hand_scale": 1.12,
        "grip_shapes": [((0, -0.01, -0.05), (0.034, 0.047, 0.115), -14, 0.008),
                        ((0, 0.035, -0.018), (0.008, 0.012, 0.022), 0, 0.002)],
        "hand_r": {"knuckle": (0.018, 0.022, -0.035), "fingers": (-0.55, 0.78, -0.12), "dorsal": (1.0, 0.45, 0.25)},
        "two_handed": False,
        "left_idle": {"wrist": (-0.215, 0.30, -0.285), "fingers": (0.42, 0.85, 0.28), "dorsal": (-0.75, 0.05, 0.65),
                      "shape": "relax"},
        "mag": {"center": (0, 0.06, 0.035), "axis": (1, 0, 0),
                "region": lambda p: abs(p.x) < 0.058 and (Vector((0, p.y - 0.06, p.z - 0.035)).length < 0.0565)},
        "reload": "spool",
        "sockets": {"socket_core": (0, -0.035, 0.075), "socket_barrel": (0, 0.36, 0.055),
                    "socket_frame": (-0.03, 0.12, 0.03), "socket_chamber": (0.03, 0.12, 0.035),
                    "fx_muzzle": (0, 0.70, 0.03), "grip_l": (0, 0.28, 0.0)},
        "arm": {"glove": "glove", "plate": "gold",
                "bands": [(0.0, 0.05, "glove", 0.004, 0.006, None),
                          (0.05, 0.085, "gold", 0.0075, 0.0, None),
                          (0.085, 0.40, "plum", 0.012, 0.014, "gold")],
                "extras": _vesper_arm_extras},
        "detail": _vesper_detail,
        "paint": {},
    },
}


# ------------------------------------------------------------------ two-handed heroes (W16 weapons)
def _right(c, size, rx=-14.0, scale=1.0):
    """Right hand on a pistol grip box (centre, size, rx): the Vesper fit, shifted by the grip width."""
    c = Vector(c)
    off = Rx(rx) @ Vector((0.0, 0.032, 0.015))
    return ({"knuckle": tuple(c + Vector((size[0] / 2 + 0.002, 0, 0)) + off), "fingers": (-0.55, 0.78, -0.12),
             "dorsal": (1.0, 0.45, 0.25)},
            [(tuple(c), tuple(size), rx, 0.008 * scale)])


def _left_vertical(c, size, rx=0.0):
    """Left hand on a vertical fore / side grip: the right-hand fit mirrored."""
    c = Vector(c)
    off = Rx(rx) @ Vector((0.0, 0.032, 0.015))
    return ({"knuckle": tuple(c + Vector((-(size[0] / 2 + 0.002), 0, 0)) + off), "fingers": (0.55, 0.78, -0.12),
             "dorsal": (-1.0, 0.45, 0.25)},
            [(tuple(c), tuple(size), rx, 0.008)])


def _left_under(c, size, extra=()):
    """Left hand under a handguard / barrel: palm up, fingers wrapping up the right side."""
    c = Vector(c)
    k = (size[0] * 0.25, c.y, c.z - size[2] / 2 - 0.014)
    return ({"knuckle": k, "fingers": (0.8, 0.45, 0.3), "dorsal": (-0.45, 0.0, -1.0)},
            [(tuple(c), tuple(size), 0.0, 0.01)] + list(extra))


def Rx(deg):
    return Matrix.Rotation(math.radians(deg), 3, "X")


def _two(hero, weapon, pal, right, left, sockets, mag, arm, grip=(0.15, 0.2, -0.165), rot=(-1.0, -20.0, 8.0),
         scale=1.12, reload="mag"):
    hr, rs = right
    hl, ls = left
    return {"hero": hero, "weapon": weapon, "palette": pal, "grip": grip, "weapon_rot": rot, "hand_scale": scale,
            "grip_shapes": rs + [((0, 0.03, -0.014), (0.008, 0.012, 0.02), 0, 0.002)], "hand_r": hr,
            "two_handed": True, "hand_l": hl, "grip_l_shapes": ls, "mag": mag, "reload": reload,
            "sockets": sockets, "arm": arm, "paint": {},
            # authored at real size; drawn smaller about the grip so a rifle does not fill the view
            "view_scale": 0.74,
            # the support arm reaches forward: the shoulder leans into the gun
            "shoulder_L": (-0.15, 0.04, -0.25)}


def _box_region(c, h):
    c, h = Vector(c), Vector(h)
    return lambda p: all(abs(p[i] - c[i]) < h[i] for i in range(3))


def _ryker_arm_extras(h, side, add):
    if side == "R":  # cyber forearm: a team light strip along the chrome
        add.ring_on("Index", 0, 0.5, "gun", "flat", 0.003)


import fp_weapons_w16 as _w  # noqa: E402

HEROES.update({
    "ryker": _two("ryker", "breakline_ar7", _w.RYKER_PAL,
                  _right((0, -0.012, -0.048), (0.032, 0.044, 0.105), -18),
                  _left_under((0, 0.33, 0.045), (0.07, 0.24, 0.08), [((0, 0.3, -0.005), (0.03, 0.05, 0.05), 8, 0.008)]),
                  {"socket_core": (0, 0.16, 0.12), "socket_barrel": (0, 0.5, 0.07), "socket_frame": (-0.034, 0.1, 0.035),
                   "socket_chamber": (0.034, 0.12, 0.035), "fx_muzzle": (0, 0.68, 0.05), "grip_l": (0, 0.3, -0.005)},
                  {"center": (0, 0.13, -0.02), "axis": (1, 0, 0), "eject": (0, -0.03, -0.35),
                   "region": _box_region((0, 0.13, -0.09), (0.03, 0.06, 0.08))},
                  {"glove": "rubber", "plate": "gun",
                   "bands": [(0.0, 0.05, "rubber", 0.004, 0.006, None), (0.05, 0.40, "suit", 0.01, 0.006, "olive")],
                   "bands_R": [(0.0, 0.05, "rubber", 0.004, 0.006, None), (0.05, 0.40, "chrome", 0.004, 0.0, "gun", "chrome")],
                   "extras": _ryker_arm_extras}),
    "brannoc": _two("brannoc", "ironmaw_w16", _w.BRANNOC_PAL,
                    _right((0, -0.012, -0.055), (0.045, 0.055, 0.12), -20, 1.2),
                    _left_vertical((-0.07, 0.32, 0.03), (0.04, 0.05, 0.1)),
                    {"socket_core": (0, 0.15, 0.115), "socket_barrel": (0, 0.45, 0.1), "socket_frame": (-0.052, 0.15, 0.04),
                     "socket_chamber": (0.052, 0.0, 0.06), "fx_muzzle": (0, 0.72, 0.045), "grip_l": (-0.07, 0.32, 0.03)},
                    {"center": (0, 0.1, -0.03), "axis": (1, 0, 0), "eject": (0, -0.02, -0.35),
                     "region": lambda p: abs(p.x) < 0.07 and (p.y - 0.1) ** 2 + (p.z + 0.03) ** 2 < 0.078 ** 2},
                    {"glove": "iron", "plate": "gold", "arm_scale": 1.2,
                     "bands": [(0.0, 0.07, "iron", 0.006, 0.014, "gold"), (0.07, 0.24, "teal", 0.012, 0.0, "iron"),
                               (0.24, 0.40, "soot", 0.008, 0.0, None)]},
                    grip=(0.14, 0.18, -0.225), scale=1.3),
    "hex": _two("hex", "glitchcaster_w16", _w.HEX_PAL,
                _right((0, -0.01, -0.045), (0.032, 0.042, 0.095), -15),
                _left_vertical((0, 0.05, -0.06), (0.03, 0.05, 0.08), 10),
                {"socket_core": (0, 0.0, 0.08), "socket_barrel": (0, 0.25, 0.07), "socket_frame": (-0.033, 0.05, 0.03),
                 "socket_chamber": (0.033, -0.02, 0.03), "fx_muzzle": (0, 0.38, 0.035), "grip_l": (0, 0.05, -0.06)},
                {"center": (0, -0.06, 0.02), "axis": (1, 0, 0), "eject": (0.0, -0.05, 0.3),
                 "region": _box_region((0, -0.06, 0.02), (0.042, 0.032, 0.032))},
                {"glove": "hoodie", "plate": None,
                 "bands": [(0.0, 0.04, "hoodie", 0.004, 0.004, "lime"), (0.04, 0.40, "hoodie", 0.014, 0.01, "lime")]},
                grip=(0.14, 0.27, -0.21)),
    "liora": _two("liora", "mender_w16", _w.LIORA_PAL,
                  _right((0, -0.01, -0.05), (0.032, 0.045, 0.11), -16),
                  _left_vertical((0, 0.26, -0.03), (0.03, 0.04, 0.07), 8),
                  {"socket_core": (0, 0.09, 0.12), "socket_barrel": (0, 0.38, 0.065), "socket_frame": (-0.033, 0.0, 0.03),
                   "socket_chamber": (0.033, 0.0, 0.03), "fx_muzzle": (0, 0.55, 0.035), "grip_l": (0, 0.26, -0.03)},
                  {"center": (0, 0.09, 0.09), "axis": (0, 1, 0), "eject": (0.0, 0.0, 0.25),
                   "region": _box_region((0, 0.09, 0.09), (0.032, 0.085, 0.032))},
                  {"glove": "ink", "plate": None, "extras": lambda h, side, add: _medic_cross(add),
                   "bands": [(0.0, 0.05, "ink", 0.004, 0.006, None), (0.05, 0.085, "sage", 0.007, 0.0, None),
                             (0.085, 0.40, "slate", 0.012, 0.012, "ivory")]}),
    "sable": _two("sable", "whisperfang_w16", _w.SABLE_PAL,
                  _right((0, -0.01, -0.045), (0.028, 0.04, 0.095), -14),
                  _left_under((0, 0.25, 0.035), (0.044, 0.14, 0.044), [((0, 0.3, -0.012), (0.006, 0.2, 0.03), 0, 0.002)]),
                  {"socket_core": (0, 0.12, 0.08), "socket_barrel": (0, 0.3, 0.065), "socket_frame": (-0.024, 0.07, 0.03),
                   "socket_chamber": (0.024, 0.12, 0.03), "fx_muzzle": (0, 0.44, 0.035), "grip_l": (0, 0.16, -0.02)},
                  {"center": (0, 0.13, -0.01), "axis": (1, 0, 0), "eject": (0, -0.02, -0.35),
                   "region": _box_region((0, 0.13, -0.036), (0.016, 0.022, 0.034))},
                  {"glove": "deep", "plate": "mask",
                   "bands": [(0.0, 0.05, "deep", 0.004, 0.006, None), (0.05, 0.075, "jade", 0.006, 0.0, None),
                             (0.075, 0.40, "charcoal", 0.01, 0.006, "deep")]}),
    "juniper": _two("juniper", "tackhammer_w16", _w.JUNIPER_PAL,
                    _right((0, -0.01, -0.045), (0.03, 0.042, 0.1), -15),
                    _left_under((0, 0.33, 0.0), (0.045, 0.2, 0.045)),
                    {"socket_core": (0, 0.16, 0.085), "socket_barrel": (0, 0.45, 0.06), "socket_frame": (-0.03, 0.08, 0.03),
                     "socket_chamber": (0.03, 0.15, 0.04), "fx_muzzle": (0, 0.67, 0.035), "grip_l": (0, 0.33, 0.0)},
                    {"center": (0.055, 0.08, 0.0), "axis": (1, 0, 0), "eject": (0.3, 0.0, -0.12),
                     "region": lambda p: p.x > 0.03 and (p.y - 0.08) ** 2 + p.z ** 2 < 0.055 ** 2},
                    {"glove": "rubber", "plate": "brass",
                     "bands": [(0.0, 0.05, "rubber", 0.004, 0.006, None), (0.05, 0.11, "mustard", 0.007, 0.0, None),
                               (0.11, 0.40, "olive", 0.012, 0.01, "mustard")]}),
})


def _medic_cross(add):
    """Liora's medic gloves: a sage cross on the back of each hand."""
    s = add.c.s
    hand = add.b("Hand")
    for size in ((0.034, 0.011, 0.005), (0.011, 0.034, 0.005)):
        add.box(hand, Vector((0.0, 0.05, 0.02)) * s, Vector(size) * s, "sage", "flat")
