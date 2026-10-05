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
    """Gold knuckle plate + three-strand team thread ring on the left middle finger
    (the Loom threads end at her left hand in third person)."""
    if side == "L":
        add.ring_on("Middle", 0, 0.45, "team", "team_emit", 0.0035)
        add.thread("team", "team_emit")


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
                          (0.085, 0.40, "plum", 0.0135, 0.022, "gold")],
                "extras": _vesper_arm_extras},
        "detail": _vesper_detail,
        "paint": {},
    },
}
