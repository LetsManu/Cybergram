#!/usr/bin/env python3
"""Writes assets/data/visuals/armory_visuals.json: Armory v2 visual data
(items-and-armory.md §3.8, weapons-and-mods.md §3.6.2-3.6.3 and §3.7.1).

Offsets are in skeleton space with model axes (+Y up, -Z forward, +X the
hero's right), relative to the bone's rest origin; "along" first moves the
point toward a child bone. Per-hero presets ("heroes") scale and nudge the
shared anchors, so the art cost is items, not items x heroes (§3.8 rule 5).
Run from the repo root: python3 tools/art/gen_armory_visuals.py
"""
import json
import math
import os


def belt_clips():
    """6 clips on an arc from the left hip, over the front, to the right hip."""
    out = []
    for i in range(6):
        t = i / 5.0
        ang = math.radians(200.0 - t * 220.0)
        x = round(math.cos(ang) * 0.17, 3)
        z = round(-math.sin(ang) * 0.13, 3)
        out.append({"bone": "Hips", "pos": [x, 0.06, z]})
    return out


DATA = {
    "idle_cull_m": 30.0,
    "tier_size": [1.0, 1.4, 1.9],
    "tier_glow": [0.6, 1.0, 1.6],
    "spare_dim": 0.15,
    # Body gear base scale: silhouette first, readable at 20 m (§3.8 rule 6).
    "gear_base_scale": 1.25,
    "item_cuts": {
        "ember_part": "ember_heart", "ember_facet": "ember_heart", "ember_heart": "ember_heart",
        "tempo_part": "tempest", "pulse_facet": "tempest", "tempest_heart": "tempest",
        "lens_part": "lens", "prism_eye": "prism_eye", "longsight_ring": "lens", "longsight_lens": "lens",
        "steady_part": "flat", "bore_ring": "bore", "breaker_bore": "bore",
        "feed_part": "vial", "wellframe": "vial", "reservoir_frame": "tank", "flux_coil": "helix",
        "anchor_frame": "hexblock",
    },
    "gear_shapes": {
        "vital_cell": "cell", "vital_core": "cell_cage", "vigil_core": "heart_cage",
        "plate_scale": "plate", "plate_harness": "plates", "bastion_plate": "pauldron",
        "null_thread": "spool", "null_cowl": "cowl", "null_veil": "fins", "barrier_lattice": "lattice",
        "cadence_bead": "bead", "cadence_circlet": "circlet", "cadence_crown": "halo",
        "stride_clip": "band", "stride_rig": "calf_rig", "breaker_sigil": "gauntlet",
    },
    # Keys = DamageMath ammo type ids. Colour "" = keep the team tracer colour.
    # Hues stay out of the team bands (azure 195-235, ember 0-25 at > 40% sat).
    "ammo": {
        "0": {"name": "standard", "color": "", "width": 1.0, "length": 1.0, "shape": "plain", "impact": "spark"},
        "1": {"name": "piercing", "color": "#B8C7D6", "width": 0.55, "length": 1.4, "shape": "thin", "impact": "puncture"},
        "2": {"name": "sunder", "color": "#FFC040", "width": 2.2, "length": 0.8, "shape": "heavy", "impact": "debris"},
        "3": {"name": "incendiary", "color": "#FF9A40", "width": 1.2, "length": 1.6, "shape": "trail", "impact": "flame"},
        "4": {"name": "shock", "color": "#F2F5A8", "width": 1.0, "length": 1.0, "shape": "arc", "impact": "ring"},
        "5": {"name": "siphon", "color": "#57E07F", "width": 1.0, "length": 1.0, "shape": "plain", "impact": "mote"},
        "6": {"name": "cryo", "color": "#D8F6FF", "width": 1.1, "length": 1.0, "shape": "frost", "impact": "bloom"},
    },
    "ammo_mods": {
        "1": {"name": "saturated", "width": 1.5},
        "2": {"name": "lingering", "linger_s": 0.3},
        "3": {"name": "volatile", "sparks": True},
        "4": {"name": "tracer", "pulse_head": True},
        "5": {"name": "overcharged", "glow": 1.6},
    },
    "anchors": {
        "body_belt": {"subs": belt_clips(), "overflow": None, "fp": True},
        "body_chest": {"subs": [{"bone": "UpperChest", "pos": [-0.07, -0.02, -0.15]},
                                {"bone": "UpperChest", "pos": [0.07, -0.02, -0.15]}],
                       "overflow": {"bone": "Spine", "pos": [0.0, 0.02, -0.15]}},
        "body_shoulders": {"subs": [{"bone": "UpperChest", "pos": [-0.21, 0.17, 0.0]},
                                    {"bone": "UpperChest", "pos": [0.21, 0.17, 0.0]}],
                           "overflow": {"bone": "UpperChest", "pos": [0.0, 0.17, 0.08]}},
        "body_back": {"subs": [{"bone": "UpperChest", "pos": [0.0, 0.06, 0.17]},
                               {"bone": "Spine", "pos": [0.0, -0.02, 0.15]}],
                      "overflow": {"bone": "Hips", "pos": [0.14, 0.02, 0.1]}},
        "body_head": {"subs": [{"bone": "Head", "pos": [0.0, 0.14, 0.0]}],
                      "overflow": {"bone": "UpperChest", "pos": [0.0, 0.2, 0.15]}},
        "body_legs": {"subs": [{"bone": "LowerLeg_L", "along": ["Foot_L", 0.4], "pos": [0.0, 0.0, 0.05]},
                               {"bone": "LowerLeg_R", "along": ["Foot_R", 0.4], "pos": [0.0, 0.0, 0.05]}],
                      "overflow": {"bone": "UpperLeg_L", "along": ["LowerLeg_L", 0.5], "pos": [-0.06, 0.0, 0.0]}},
        "body_forearm": {"subs": [{"bone": "LowerArm_L", "along": ["Hand_L", 0.5], "pos": [0.0, 0.0, 0.0]},
                                  {"bone": "LowerArm_R", "along": ["Hand_R", 0.5], "pos": [0.0, 0.0, 0.0]}],
                         "overflow": {"bone": "UpperArm_L", "along": ["LowerArm_L", 0.5], "pos": [0.0, 0.0, 0.0]},
                         "fp": True},
    },
    "badge": {"bone": "UpperChest", "pos": [0.0, 0.0, 0.2], "step": [0.045, 0.0, 0.0]},
    # Model-space bone origins for models without a skeleton (procedural stand-ins).
    "bone_fallback": {
        "Hips": [0, 0.98, 0], "Spine": [0, 1.12, 0], "UpperChest": [0, 1.38, 0], "Head": [0, 1.62, 0],
        "UpperLeg_L": [-0.1, 0.9, 0], "LowerLeg_L": [-0.1, 0.5, 0], "LowerLeg_R": [0.1, 0.5, 0],
        "Foot_L": [-0.1, 0.08, 0], "Foot_R": [0.1, 0.08, 0],
        "UpperArm_L": [-0.2, 1.4, 0], "LowerArm_L": [-0.3, 1.15, 0], "LowerArm_R": [0.3, 1.15, 0],
        "Hand_L": [-0.32, 0.92, 0], "Hand_R": [0.32, 0.92, 0],
    },
    # Gun sockets for rigged heroes whose glb carries the gun mesh (no
    # WeaponModel): offsets from the hand bone, model axes; 3P scale 1.3x (art bible §7.1).
    "gun": {"bone": "Hand_R", "scale": 1.3,
            "socket_core": [0.0, 0.07, -0.2], "socket_barrel": [0.0, 0.04, -0.5],
            "socket_frame": [-0.03, 0.0, -0.08], "socket_chamber": [0.0, -0.04, -0.18]},
    # Mana guns: Liora, Vesper, Sable, Hex; Mechanical: Ryker, Brannoc, Juniper
    # (weapons-and-mods.md §3.5). Picks the Crystal or Chip form (§3.3).
    "heroes": {
        "default": {"spread": 1.0, "gear_scale": 1.0, "nudge": {}, "mana": True},
        "brannoc": {"mana": False, "spread": 1.3, "gear_scale": 1.3,
                    "nudge": {"body_shoulders": [0.0, 0.03, 0.0], "body_back": [0.0, 0.0, 0.05]}},
        "ryker": {"mana": False, "spread": 1.08, "gear_scale": 1.05, "nudge": {}},
        "juniper": {"mana": False, "spread": 0.95, "gear_scale": 0.95, "nudge": {}},
        "liora": {"mana": True, "spread": 0.95, "gear_scale": 0.95, "nudge": {}},
        "sable": {"mana": True, "spread": 0.95, "gear_scale": 0.95, "nudge": {}},
        "vesper": {"mana": True, "spread": 0.97, "gear_scale": 0.97, "nudge": {}},
        "hex": {"mana": True, "spread": 0.92, "gear_scale": 0.92, "nudge": {"body_head": [0.0, 0.03, 0.0]}},
    },
}

if __name__ == "__main__":
    path = os.path.join("assets", "data", "visuals", "armory_visuals.json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(DATA, f, indent=1)
        f.write("\n")
    print(path)
