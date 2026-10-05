"""W16 hero weapons for the FP builds (tools/art/build_fp.py), read from the hero branches.

Verbatim copies of the six heroes' own weapon builders and palettes as committed on
claude/w16-heroA (6ac2204: breakline_ar7, ironmaw_w16, glitchcaster_w16) and
claude/w16-heroB (be4fe50: mender, whisperfang, tackhammer). When those branches merge,
hero_defs.WEAPONS carries the same functions and this file can go (fp_defs falls back to
hero_defs.WEAPONS first). Weapon space: origin = right grip, +Y barrel, +Z up.
"""
import math

from mathutils import Matrix, Vector

from hero_defs import TEAM, _rx

RYKER_PAL = {"olive": "#6F8C45", "bone": "#EAD49C", "suit": "#3E4F6A", "rubber": "#353A44", "gun": "#4C5564",
             "glass": "#1D3A55", "chrome": "#C9D4E2", "antenna": "#C6D2E0", "trim": "#4A5640", "khaki": "#9C8B5E",
             "team": TEAM, "eye": "#15151A"}

BRANNOC_PAL = {"teal": "#2F9A90", "iron": "#9AA3AD", "soot": "#5E554C", "bone": "#E8D9B0", "gold": "#E0AC48",
               "gun": "#565E69", "slit": "#15191E", "team": TEAM, "eye": "#101014"}

HEX_PAL = {"hoodie": "#5A5686", "lime": "#B6F23A", "shell": "#DCDFEA", "bezel": "#2C2F3D", "screen": "#12262A",
           "chrome": "#C9D4E2", "legs": "#6C6C88", "sneaker": "#E9E9F0", "team": TEAM, "eye": "#101014"}

LIORA_PAL = {"ivory": "#F2E8D0", "sage": "#45D38A", "slate": "#3E5F86", "chrome": "#C9D4E2",
             "hair": "#C0602E", "ink": "#24334A", "team": TEAM, "eye": "#101014"}
SABLE_PAL = {"charcoal": "#3C4C72", "deep": "#252F4A", "jade": "#34E3A2", "mask": "#C2CBDD",
             "chrome": "#C9D4E2", "team": TEAM, "eye": "#101014"}
JUNIPER_PAL = {"mustard": "#F2B12A", "olive": "#7F9B38", "rubber": "#5A4636", "brass": "#D9A23E",
               "chrome": "#C9D4E2", "bone": "#F3E6C6", "hair": "#B5462A", "wood": "#8A5A34",
               "trousers": "#6E5640", "ink": "#2B2530", "team": TEAM, "eye": "#101014"}


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


WEAPONS = {"breakline_ar7": breakline_ar7, "ironmaw_w16": ironmaw_w16, "glitchcaster_w16": glitchcaster_w16,
           "mender_w16": mender, "whisperfang_w16": whisperfang, "tackhammer_w16": tackhammer}
PALETTES = {"ryker": RYKER_PAL, "brannoc": BRANNOC_PAL, "hex": HEX_PAL, "liora": LIORA_PAL, "sable": SABLE_PAL,
            "juniper": JUNIPER_PAL}
