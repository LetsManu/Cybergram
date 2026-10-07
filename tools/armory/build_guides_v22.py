#!/usr/bin/env python3
"""Writes the Armory v2 hero guides (protocol 22) to
assets/data/economy/recommended_builds_v22.tres.

items-and-armory.md §3.10: a guide lists steps; each step names finished items
(the node's item plus `alts` = the 2-3 choices); BuildAdvisor works out the
parts and picks the choice closest to done. Every guide fills the full build:
a Core Signature, a Barrel and a Frame Assembly, the Chamber (type + mod), a
gear Signature and the other open slots, plus squad upgrades and Med-Packs.

Run: python3 tools/armory/build_guides_v22.py   (then --import and the validator test)
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_guides as v1  # noqa: E402  (shared writer helpers and squad node lists)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets/data/economy/recommended_builds_v22.tres")


def situational():
    return [
        ("heal_pack", "med_pack", 2, "DEFENSIVE", 520, [], dict(cond=["low_health", "died_often", "taking_weapon_damage",
            "taking_skill_damage"], skippable=True, core=False, reason="HUD_ADVICE_N_HEAL_PACK")),
        ("vs_guns", "bastion_plate", 1, "DEFENSIVE", 690, ["core1"], dict(cond=["taking_weapon_damage",
            "enemy_weapon_dps", "enemy_burst"], skippable=True, core=False, alts=["plate_harness"],
            reason="HUD_ADVICE_N_VS_GUNS")),
        ("vs_skills", "null_veil", 1, "DEFENSIVE", 685, ["core1"], dict(cond=["taking_skill_damage",
            "enemy_skill_dps", "enemy_cc", "enemy_zone"], skippable=True, core=False,
            alts=["null_cowl", "barrier_lattice"], reason="HUD_ADVICE_N_VS_SKILLS")),
        ("vs_armor", "ammo_piercing", 1, "COUNTER", 680, ["core1"], dict(cond=["enemy_frontline"], skippable=True,
            core=False, alts=["bore_ring"], reason="HUD_ADVICE_N_VS_ARMOR")),
        ("vs_sustain", "ammo_incendiary", 1, "COUNTER", 670, ["core1"], dict(cond=["enemy_sustain"], skippable=True,
            core=False)),
        ("vs_squads", "ammo_shock", 1, "COUNTER", 660, ["core1"], dict(cond=["enemy_squad"], skippable=True,
            core=False, alts=["ammo_sunder"], reason="HUD_ADVICE_N_VS_SQUADS")),
        ("siege", "breaker_sigil", 1, "UTILITY", 600, ["core1"], dict(cond=["objective_soon"], skippable=True,
            core=False, optional=True)),
    ]


# v1 squad node lists name v1 steps in `requires`; map them onto v22 steps.
V1_STEP = {"c1": "core1", "f1": "start", "c2": "core1", "c3": "sig2"}


def remap(squad):
    out = []
    for nid, item, target, sec, prio, req, o in squad:
        out.append((nid, item, target, sec, prio, [V1_STEP.get(r, r) for r in req], o))
    return out


def guide(start, core, barrel, ammo, sig2, mod, gear, squad):
    """start / core / barrel / ammo / sig2 / mod: choice lists (first = default).
    gear: 6 distinct gear items for the open slots (one node each; the gear
    Signature uses up one of them, so 6 + the Signature fill the 6 slots)."""
    n = [
        ("open", "med_pack", 1, "OPENING", 1000, [], dict(reason="HUD_ADVICE_N_OPEN")),
        ("start", start[0], 1, "EARLY", 950, ["open"], dict(alts=start[1:], reason="HUD_ADVICE_N_FIRST_MOUNT")),
        ("core1", core[0], 1, "SPIKE", 900, ["start"], dict(alts=core[1:], reason="HUD_ADVICE_N_SPIKE")),
        ("def1", gear[0], 1, "CORE", 850, ["start"], dict()),
        ("barrel", barrel[0], 1, "CORE", 800, ["core1"], dict(alts=barrel[1:], reason="HUD_ADVICE_N_RANGE")),
        ("ammo", ammo[0], 1, "CORE", 760, ["core1"], dict(alts=ammo[1:])),
        ("frame", "wellframe", 1, "CORE", 740, ["core1"], dict()),
        ("sig2", sig2[0], 1, "LATE", 700, ["core1", "def1"], dict(alts=sig2[1:])),
        ("mod", mod[0], 1, "LATE", 650, ["ammo"], dict(alts=mod[1:], optional=True, core=False)),
    ]
    for k, g in enumerate(gear[1:]):
        n.append(("gear%d" % (k + 2), g, 1, "LATE", 620 - 20 * k, ["sig2"], dict(optional=True, core=False,
            keep=True, reason="HUD_ADVICE_N_LUXURY")))
    return n + remap(squad) + situational()


GUIDES = [
    ("hero_vesper_loom", "Loom Weaver", "HUD_ADVICE_B_VESPER", ["commander"], guide(
        ["ember_part", "vital_cell"], ["ember_heart", "tempest_heart", "prism_eye"], ["longsight_ring", "bore_ring"],
        ["ammo_shock", "ammo_cryo"], ["barrier_lattice", "vigil_core", "cadence_crown"],
        ["mod_saturated", "mod_lingering"],
        ["vital_core", "cadence_circlet", "null_cowl", "stride_rig", "plate_harness", "vital_cell"], v1.SQUAD_COMMANDER)),
    ("hero_sable", "Shadow Edge", "HUD_ADVICE_B_SABLE", ["infiltrator"], guide(
        ["ember_part"], ["prism_eye", "ember_heart", "tempest_heart"], ["bore_ring", "longsight_ring"],
        ["ammo_cryo", "ammo_siphon"], ["cadence_crown", "vigil_core", "breaker_sigil"],
        ["mod_overcharged", "mod_saturated"],
        ["vital_core", "null_cowl", "stride_rig", "plate_harness", "cadence_circlet", "plate_scale"], v1.SQUAD_LIGHT)),
    ("hero_hex", "Static Overload", "HUD_ADVICE_B_HEX", ["hacker"], guide(
        ["cadence_bead", "ember_part"], ["tempest_heart", "ember_heart", "prism_eye"], ["longsight_ring", "bore_ring"],
        ["ammo_shock", "ammo_incendiary"], ["cadence_crown", "barrier_lattice", "null_veil"],
        ["mod_lingering", "mod_saturated"],
        ["cadence_circlet", "null_cowl", "vital_core", "stride_rig", "plate_harness", "vital_cell"], v1.SQUAD_LIGHT)),
    ("hero_liora_vale", "Steady Light", "HUD_ADVICE_B_LIORA", ["healer"], guide(
        ["feed_part", "vital_cell"], ["tempest_heart", "ember_heart", "prism_eye"], ["longsight_ring", "bore_ring"],
        ["ammo_siphon", "ammo_cryo"], ["barrier_lattice", "cadence_crown", "vigil_core"],
        ["mod_saturated", "mod_volatile"],
        ["vital_core", "null_cowl", "cadence_circlet", "stride_rig", "plate_harness", "plate_scale"], v1.SQUAD_LIGHT)),
    ("hero_brannoc", "Bulwark Gunner", "HUD_ADVICE_B_BRANNOC", ["tank"], guide(
        ["vital_cell", "plate_scale"], ["ember_heart", "tempest_heart", "prism_eye"], ["bore_ring", "longsight_ring"],
        ["ammo_sunder", "ammo_piercing"], ["bastion_plate", "vigil_core", "breaker_sigil"],
        ["mod_saturated", "mod_volatile"],
        ["plate_harness", "vital_core", "null_cowl", "stride_rig", "cadence_circlet", "null_thread"], v1.SQUAD_FRONTLINE)),
    ("hero_ryker_vance", "Line Breaker", "HUD_ADVICE_B_RYKER", ["soldier"], guide(
        ["ember_part", "tempo_part"], ["ember_heart", "prism_eye", "tempest_heart"], ["longsight_ring", "bore_ring"],
        ["ammo_piercing", "ammo_incendiary"], ["vigil_core", "bastion_plate", "breaker_sigil"],
        ["mod_overcharged", "mod_saturated"],
        ["plate_harness", "vital_core", "stride_rig", "null_cowl", "cadence_circlet", "null_thread"], v1.SQUAD_LIGHT)),
    ("hero_juniper_quill", "Snare Field", "HUD_ADVICE_B_JUNIPER", ["trapper"], guide(
        ["cadence_bead", "ember_part"], ["tempest_heart", "ember_heart", "prism_eye"], ["longsight_ring", "bore_ring"],
        ["ammo_cryo", "ammo_shock"], ["cadence_crown", "barrier_lattice", "vigil_core"],
        ["mod_lingering", "mod_tracer"],
        ["cadence_circlet", "plate_harness", "vital_core", "null_cowl", "stride_rig", "vital_cell"], v1.SQUAD_LIGHT)),
]


def main():
    v1.GUIDES[:] = GUIDES
    v1.situational = lambda _core: []  # v22 guides carry their own situational list
    v1.main(OUT)


if __name__ == "__main__":
    main()
