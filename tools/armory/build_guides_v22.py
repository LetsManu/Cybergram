#!/usr/bin/env python3
"""Writes the Armory v2 hero guides (protocol 22) to
assets/data/economy/recommended_builds_v22.tres.

items-and-armory.md §3.10: a guide lists steps; each step names finished items
(the node's item plus `alts` = the 2-3 choices); BuildAdvisor works out the
parts and picks the choice closest to done. Every guide fills the full build:
a Core Signature, a Barrel and a Frame Assembly, the Chamber (type + mod), a
gear Signature and the other open slots, plus squad upgrades and Med-Packs.

Two archetypes (GDD §4.7 / AC 15-17):
  balanced  - squad upgrades and a gear Assembly come before the Core Signature
              (first Signature 15-19 min, 20-25% squad, 45-55% of the full build
              owned at 30:00 on the average curve);
  gun_first - the Core Signature comes first, a short squad list follows (first
              Signature 10-14 min, items up to 80%, 65-80% owned at 30:00).

Node tuple: (id, item, target, section, priority, requires, options)
options keys: alts, cond, reason, optional, fallback, skippable, core, min_s, max_s, expert, keep

Run: python3 tools/armory/build_guides_v22.py   (then --import and the validator test)
"""
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets/data/economy/recommended_builds_v22.tres")

SECTIONS = ["OPENING", "EARLY", "SPIKE", "CORE", "SQUAD", "CONSUMABLE", "DEFENSIVE", "OFFENSIVE",
            "UTILITY", "COUNTER", "LATE"]

# Squad steps: item -> (node id, advisor reason key). Prices: cores1 350, cores2 750, amp 700,
# exp1 800, exp2 1,500, tether 300, mint 250, bulwark 1,400.
SQUAD = {
    "reinforced_cores_1": ("sq_hp", "HUD_ADVICE_N_SQUAD"),
    "reinforced_cores_2": ("sq_hp2", ""),
    "amplifier_emitters": ("sq_dmg", "HUD_ADVICE_N_SQUAD"),
    "squad_expansion_1": ("sq_size", "HUD_ADVICE_N_SQUAD_SIZE"),
    "squad_expansion_2": ("sq_size2", "HUD_ADVICE_N_LUXURY"),
    "harmonic_tether": ("sq_tether", "HUD_ADVICE_N_TETHER"),
    "quick_mint": ("sq_mint", "HUD_ADVICE_N_QUICK_MINT"),
    "bulwark_protocol": ("sq_bulwark", "HUD_ADVICE_N_BULWARK"),
}
# Catalog requirements (the shop refuses a step without them).
SQUAD_NEEDS = {"reinforced_cores_2": "reinforced_cores_1", "squad_expansion_2": "squad_expansion_1"}


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


PRE_CORE_SQUAD = 2


def squad_nodes(items, first_prio, step, after, tail=(), split=0, split_prio=0, split_after=""):
    """Squad nodes in buying order: priorities first_prio, first_prio - step, ...
    The first one needs `after`; the next ones need the previous node and any catalog requirement.
    `tail` items are optional luxuries bought after the whole build."""
    out = []
    ids = {}
    prio = first_prio
    prev = after
    for k, item in enumerate(items):
        nid, reason = SQUAD[item]
        if split and k == split:
            prio = split_prio  # from here on the steps follow the Core Signature
            prev = prev + "," + split_after
        req = prev.split(",")
        need = SQUAD_NEEDS.get(item)
        if need and need in ids:
            req.append(ids[need])
        opts = dict(reason=reason) if reason else dict()
        out.append((nid, item, 1, "SQUAD", prio, req, opts))
        ids[item] = nid
        prev = nid
        prio -= step
    prio = 450
    for item in tail:
        nid, reason = SQUAD[item]
        req = [prev]
        need = SQUAD_NEEDS.get(item)
        if need and need in ids:
            req.append(ids[need])
        opts = dict(optional=True, core=False)
        if reason:
            opts["reason"] = reason
        out.append((nid, item, 1, "LATE", prio, req, opts))
        ids[item] = nid
        prev = nid
        prio -= 10
    return out


def guide(style, start, core, barrel, ammo, sig2, mod, gear, squad, tail=(), pre=PRE_CORE_SQUAD):
    """start / core / barrel / ammo / sig2 / mod: choice lists (first = default).
    gear: 6 distinct gear items for the open slots (one node each; the gear
    Signature uses up one of them, so 6 + the Signature fill the 6 slots).
    squad: items bought in the mid game; tail: optional luxuries after the build."""
    balanced = style == "balanced"
    n = [
        ("open", "med_pack", 1, "OPENING", 1000, [], dict(reason="HUD_ADVICE_N_OPEN")),
        # Keeps up to 3 Med-Packs in the bag: one is bought back after each use.
        ("restock", "med_pack", 3, "CONSUMABLE", 990, ["open"], dict(core=False, optional=True,
            reason="HUD_ADVICE_N_RESTOCK")),
        ("start", start[0], 1, "EARLY", 950, ["open"], dict(alts=start[1:], reason="HUD_ADVICE_N_FIRST_MOUNT")),
        ("core1", core[0], 1, "SPIKE", 880 if balanced else 900, ["start"], dict(alts=core[1:], reason="HUD_ADVICE_N_SPIKE")),
        ("def1", gear[0], 1, "CORE", 930 if balanced else 850, ["start"], dict()),
        ("barrel", barrel[0], 1, "CORE", 800, ["core1"], dict(alts=barrel[1:], reason="HUD_ADVICE_N_RANGE")),
        ("ammo", ammo[0], 1, "CORE", 760, ["core1"], dict(alts=ammo[1:])),
        ("frame", "wellframe", 1, "CORE", 740, ["core1"], dict()),
        ("sig2", sig2[0], 1, "LATE", 700, ["core1", "def1"], dict(alts=sig2[1:])),
        ("mod", mod[0], 1, "LATE", 650, ["ammo"], dict(alts=mod[1:], optional=True, core=False)),
    ]
    for k, g in enumerate(gear[1:]):
        n.append(("gear%d" % (k + 2), g, 1, "LATE", 620 - 20 * k, ["sig2"], dict(optional=True, core=False,
            keep=True, reason="HUD_ADVICE_N_LUXURY")))
    if balanced:
        # The first PRE_CORE_SQUAD steps come before the Core Signature, the rest after it.
        n += squad_nodes(squad, 940, 10, "start", tail, split=pre, split_prio=870, split_after="core1")
    else:
        n += squad_nodes(squad, 870, 10, "core1", tail)
    return n + situational()


MANA_GEAR = ["vital_core", "cadence_circlet", "null_cowl", "stride_rig", "plate_harness", "vital_cell"]

GUIDES = [
    ("hero_vesper_loom", "Loom Weaver", "HUD_ADVICE_B_VESPER", ["commander"], guide(
        "balanced", ["ember_part", "vital_cell"], ["ember_heart", "tempest_heart", "prism_eye"],
        ["longsight_ring", "bore_ring"], ["ammo_shock", "ammo_cryo"],
        ["cadence_crown", "barrier_lattice", "vigil_core"], ["mod_saturated", "mod_lingering"],
        ["vital_core", "cadence_circlet", "null_cowl", "stride_rig", "plate_harness", "vital_cell"],
        ["reinforced_cores_1", "amplifier_emitters", "squad_expansion_1"],
        ["harmonic_tether", "quick_mint", "reinforced_cores_2", "squad_expansion_2", "bulwark_protocol"])),
    ("hero_sable", "Shadow Edge", "HUD_ADVICE_B_SABLE", ["infiltrator"], guide(
        "gun_first", ["stride_clip", "ember_part"], ["prism_eye", "ember_heart", "tempest_heart"], ["longsight_ring", "bore_ring"],
        ["ammo_cryo", "ammo_siphon"], ["longsight_lens", "breaker_sigil"],
        ["mod_overcharged", "mod_saturated"],
        ["vital_core", "null_cowl", "stride_rig", "plate_harness", "cadence_circlet", "plate_scale"],
        ["reinforced_cores_1", "quick_mint", "harmonic_tether"], ["amplifier_emitters"])),
    ("hero_hex", "Static Overload", "HUD_ADVICE_B_HEX", ["hacker"], guide(
        "balanced", ["cadence_bead", "ember_part"], ["tempest_heart", "ember_heart", "prism_eye"],
        ["longsight_ring", "bore_ring"], ["ammo_shock", "ammo_incendiary"],
        ["flux_coil", "reservoir_frame"], ["mod_lingering", "mod_saturated"],
        ["cadence_circlet", "null_cowl", "vital_core", "stride_rig", "plate_harness", "vital_cell"],
        ["reinforced_cores_1", "amplifier_emitters", "squad_expansion_1"], ["quick_mint", "harmonic_tether"])),
    ("hero_liora_vale", "Steady Light", "HUD_ADVICE_B_LIORA", ["healer"], guide(
        "balanced", ["feed_part", "vital_cell"], ["tempest_heart", "ember_heart", "prism_eye"],
        ["longsight_ring", "bore_ring"], ["ammo_siphon", "ammo_cryo"],
        ["reservoir_frame", "anchor_frame"], ["mod_volatile", "mod_saturated"],
        ["vital_core", "null_cowl", "cadence_circlet", "stride_rig", "plate_harness", "plate_scale"],
        ["reinforced_cores_1", "reinforced_cores_2", "squad_expansion_1"], ["harmonic_tether"], pre=1)),
    ("hero_brannoc", "Bulwark Gunner", "HUD_ADVICE_B_BRANNOC", ["tank"], guide(
        "balanced", ["vital_cell", "plate_scale"], ["ember_heart", "tempest_heart", "prism_eye"],
        ["bore_ring", "longsight_ring"], ["ammo_sunder", "ammo_piercing"],
        ["bastion_plate", "vigil_core", "anchor_frame"], ["mod_saturated", "mod_volatile"],
        ["plate_harness", "vital_core", "null_cowl", "stride_rig", "cadence_circlet", "null_thread"],
        ["reinforced_cores_1", "reinforced_cores_2", "squad_expansion_1"], ["bulwark_protocol", "squad_expansion_2"])),
    ("hero_ryker_vance", "Line Breaker", "HUD_ADVICE_B_RYKER", ["soldier"], guide(
        "gun_first", ["ember_part", "tempo_part"], ["ember_heart", "prism_eye", "tempest_heart"],
        ["bore_ring", "longsight_ring"], ["ammo_piercing", "ammo_incendiary"],
        ["breaker_bore", "vigil_core"], ["mod_overcharged", "mod_saturated"],
        ["plate_harness", "vital_core", "stride_rig", "null_cowl", "cadence_circlet", "null_thread"],
        ["reinforced_cores_1", "amplifier_emitters"], ["squad_expansion_1"])),
    ("hero_juniper_quill", "Snare Field", "HUD_ADVICE_B_JUNIPER", ["trapper"], guide(
        "balanced", ["cadence_bead", "ember_part"], ["tempest_heart", "ember_heart", "prism_eye"],
        ["longsight_ring", "bore_ring"], ["ammo_cryo", "ammo_shock"],
        ["breaker_sigil", "null_veil"], ["mod_tracer", "mod_lingering"],
        ["cadence_circlet", "plate_harness", "vital_core", "null_cowl", "stride_rig", "vital_cell"],
        ["reinforced_cores_1", "squad_expansion_1", "amplifier_emitters"], ["harmonic_tether", "quick_mint"])),
]


def arr_s(xs):
    return "PackedStringArray(" + ", ".join('"%s"' % x for x in xs) + ")"


def main(out_path=OUT):
    subs = []
    builds = []
    for gi, (hero, name, summary, roles, nodes) in enumerate(GUIDES):
        node_refs = []
        simple = []
        for ni, (nid, item, target, sec, prio, req, o) in enumerate(nodes):
            rid = "n_%d_%d" % (gi, ni)
            node_refs.append('SubResource("%s")' % rid)
            lines = ['[sub_resource type="Resource" id="%s"]' % rid, 'script = ExtResource("3")',
                     'id = &"%s"' % nid, 'item_id = &"%s"' % item, 'target = %d' % target,
                     'section = %d' % SECTIONS.index(sec), 'priority = %d' % prio]
            if req:
                lines.append('requires = ' + arr_s(req))
            if o.get("alts"):
                lines.append('alternatives = ' + arr_s(o["alts"]))
            if o.get("cond"):
                lines.append('conditions = ' + arr_s(o["cond"]))
            if o.get("reason"):
                lines.append('reason_key = "%s"' % o["reason"])
            if o.get("core") is False:
                lines.append('core = false')
            for flag in ("optional", "fallback", "skippable", "expert", "keep"):
                if o.get(flag):
                    lines.append('%s = true' % flag)
            if o.get("min_s"):
                lines.append('min_s = %d' % o["min_s"])
            if o.get("max_s"):
                lines.append('max_s = %d' % o["max_s"])
            subs.append("\n".join(lines))
            if not o.get("cond") and not o.get("optional"):
                simple.append((-prio, ni, item, target))
        simple.sort()
        simple_ids = [x[2] for x in simple]
        simple_t = [x[3] for x in simple]
        bid = "build_%d" % gi
        subs.append("\n".join([
            '[sub_resource type="Resource" id="%s"]' % bid, 'script = ExtResource("1")',
            'hero_id = &"%s"' % hero, 'display_name = "%s"' % name,
            'item_ids = ' + arr_s(simple_ids),
            'targets = PackedInt32Array(' + ", ".join(str(t) for t in simple_t) + ')',
            'nodes = Array[ExtResource("3")]([' + ", ".join(node_refs) + '])',
            'roles = ' + arr_s(roles), 'summary_key = "%s"' % summary]))
        builds.append('SubResource("%s")' % bid)
    head = ['[gd_resource type="Resource" script_class="RecommendedBuildsDef" format=3]', '',
            '[ext_resource type="Script" path="res://src/gameplay/data/recommended_build_def.gd" id="1"]',
            '[ext_resource type="Script" path="res://src/gameplay/data/recommended_builds_def.gd" id="2"]',
            '[ext_resource type="Script" path="res://src/gameplay/data/build_node_def.gd" id="3"]', '']
    body = "\n\n".join(subs)
    tail = '\n\n[resource]\nscript = ExtResource("2")\nbuilds = Array[ExtResource("1")]([' + ", ".join(builds) + '])\n'
    with open(out_path, "w") as f:
        f.write("\n".join(head) + "\n" + body + tail)
    print("wrote", out_path, len(GUIDES), "guides")


if __name__ == "__main__":
    main()
