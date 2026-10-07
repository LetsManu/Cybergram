#!/usr/bin/env python3
"""Writes assets/data/economy/recommended_builds_slice.tres from the guide spec
below (docs/armory.md "Adding a recommendation"). The .tres stays the runtime
source of truth and can be edited in the Godot editor; this script is the
compact way to author all heroes at once. Run, then `godot --headless --import`
and the validator test (tests/unit/economy/armory_validator_test.gd).

Node tuple: (id, item, target, section, priority, requires, options)
options keys: alts, cond, reason, optional, fallback, skippable, core, min_s, max_s, expert
"""
import os, sys

SECTIONS = ["OPENING", "EARLY", "SPIKE", "CORE", "SQUAD", "CONSUMABLE", "DEFENSIVE", "OFFENSIVE",
            "UTILITY", "COUNTER", "LATE"]

# Shared situational branches (appended to every guide).
def situational(core_item):
    return [
        ("heal_pack", "med_pack", 2, "DEFENSIVE", 520, [], dict(cond=["low_health", "died_often", "taking_weapon_damage", "taking_skill_damage"], skippable=True, core=False, reason="HUD_ADVICE_N_HEAL_PACK")),
        ("behind_pack", "med_pack", 3, "DEFENSIVE", 480, ["heal_pack"], dict(cond=["team_behind", "died_often"], skippable=True, core=False, optional=True)),
        ("vs_armor", "ammo_piercing", 1, "COUNTER", 560, ["c1"], dict(cond=["enemy_frontline", "counters_enemy"], skippable=True, core=False, alts=["ammo_sunder"], reason="HUD_ADVICE_N_VS_ARMOR")),
        ("vs_squads", "ammo_sunder", 1, "COUNTER", 540, ["c1"], dict(cond=["enemy_squad"], skippable=True, core=False, reason="HUD_ADVICE_N_VS_SQUADS")),
        # Defensive Frame weaves replace the damage Frame (same socket): offered
        # only while the matching threat shows, and the Frame path then
        # continues on the weave (see "alts" on the f-nodes).
        ("vs_guns", "bastion_weave", 1, "DEFENSIVE", 575, ["c1"], dict(cond=["taking_weapon_damage", "enemy_weapon_dps", "enemy_burst"], skippable=True, core=False, alts=["null_weave"], reason="HUD_ADVICE_N_VS_GUNS")),
        ("vs_skills", "null_weave", 1, "DEFENSIVE", 570, ["c1"], dict(cond=["taking_skill_damage", "enemy_skill_dps", "enemy_cc", "enemy_zone"], skippable=True, core=False, alts=["bastion_weave"], reason="HUD_ADVICE_N_VS_SKILLS")),
    ]

WEAVES = ["bastion_weave", "null_weave"]

def mana_core(extra_squad, barrel=True):
    n = [
        ("open", "med_pack", 1, "OPENING", 1000, [], dict(reason="HUD_ADVICE_N_OPEN")),
        ("c1", "ember_heart", 1, "EARLY", 900, ["open"], dict(reason="HUD_ADVICE_N_FIRST_MOUNT")),
        ("f1", "flux_coil", 1, "SPIKE", 800, ["c1"], dict(alts=WEAVES, reason="HUD_ADVICE_N_SPIKE")),
        ("c2", "ember_heart", 2, "CORE", 700, ["f1"], dict()),
        ("b1", "focus_lens", 1, "CORE", 660, ["c2"], dict(alts=[], reason="HUD_ADVICE_N_RANGE")),
        ("f2", "flux_coil", 2, "CORE", 640, ["c2"], dict(alts=WEAVES)),
        ("c3", "ember_heart", 3, "LATE", 600, ["f2"], dict()),
        ("b2", "focus_lens", 2, "LATE", 560, ["b1", "c3"], dict(alts=[])),
        ("f3", "flux_coil", 3, "LATE", 400, ["c3"], dict(alts=WEAVES, optional=True, core=False, reason="HUD_ADVICE_N_LUXURY")),
        ("b3", "focus_lens", 3, "LATE", 380, ["b2"], dict(alts=[], optional=True, core=False, reason="HUD_ADVICE_N_LUXURY")),
    ]
    if not barrel:  # GDD CR-5: Focus Lens is "Not Hex" (beam, no falloff)
        n = [x for x in n if not x[0].startswith("b")]
    return n + extra_squad

def mech_core(extra_squad):
    n = [
        ("open", "med_pack", 1, "OPENING", 1000, [], dict(reason="HUD_ADVICE_N_OPEN")),
        ("c1", "overclock", 1, "EARLY", 900, ["open"], dict(reason="HUD_ADVICE_N_FIRST_MOUNT")),
        ("f1", "quickload", 1, "SPIKE", 800, ["c1"], dict(alts=WEAVES, reason="HUD_ADVICE_N_SPIKE")),
        ("c2", "overclock", 2, "CORE", 700, ["f1"], dict()),
        ("b1", "rifling", 1, "CORE", 660, ["c2"], dict(alts=["penetrator"], reason="HUD_ADVICE_N_RANGE")),
        ("f2", "quickload", 2, "CORE", 640, ["c2"], dict(alts=WEAVES)),
        ("c3", "overclock", 3, "LATE", 600, ["f2"], dict()),
        ("b2", "rifling", 2, "LATE", 560, ["b1", "c3"], dict(alts=["penetrator"])),
        ("f3", "quickload", 3, "LATE", 400, ["c3"], dict(alts=WEAVES, optional=True, core=False, reason="HUD_ADVICE_N_LUXURY")),
        ("b3", "rifling", 3, "LATE", 380, ["b2"], dict(alts=["penetrator"], optional=True, core=False, reason="HUD_ADVICE_N_LUXURY")),
        # Penetrator (a Chip, so Mechanical guns only) swaps
        # out a held Rifling on purpose (a counter, not a path step).
        ("vs_armor_barrel", "penetrator", 1, "COUNTER", 530, ["c1"], dict(cond=["enemy_frontline"], skippable=True, core=False, reason="HUD_ADVICE_N_PENETRATOR")),
    ]
    return n + extra_squad

SQUAD_LIGHT = [
    ("sq_hp", "reinforced_cores_1", 1, "SQUAD", 560, ["f1"], dict(core=False, optional=True, reason="HUD_ADVICE_N_SQUAD")),
]
SQUAD_COMMANDER = [
    ("sq_hp", "reinforced_cores_1", 1, "SQUAD", 850, ["c1"], dict(reason="HUD_ADVICE_N_SQUAD")),
    ("sq_dmg", "amplifier_emitters", 1, "SQUAD", 750, ["f1"], dict(reason="HUD_ADVICE_N_SQUAD")),
    ("sq_size", "squad_expansion_1", 1, "SQUAD", 690, ["sq_dmg"], dict(reason="HUD_ADVICE_N_SQUAD_SIZE")),
    ("sq_hp2", "reinforced_cores_2", 1, "SQUAD", 560, ["sq_hp", "c2"], dict()),
    ("sq_mint", "quick_mint", 1, "SQUAD", 620, ["sq_size"], dict(reason="HUD_ADVICE_N_QUICK_MINT")),
    ("sq_tether", "harmonic_tether", 1, "SQUAD", 600, ["sq_size"], dict(reason="HUD_ADVICE_N_TETHER")),
    ("sq_bulwark", "bulwark_protocol", 1, "LATE", 540, ["sq_hp2", "c3"], dict(reason="HUD_ADVICE_N_BULWARK")),
    ("sq_size2", "squad_expansion_2", 1, "LATE", 520, ["sq_size", "c3"], dict(optional=True, core=False, reason="HUD_ADVICE_N_LUXURY")),
]
SQUAD_FRONTLINE = [
    ("sq_hp", "reinforced_cores_1", 1, "SQUAD", 760, ["f1"], dict(reason="HUD_ADVICE_N_SQUAD")),
    ("sq_size", "squad_expansion_1", 1, "SQUAD", 620, ["c2"], dict(reason="HUD_ADVICE_N_SQUAD_SIZE")),
    ("sq_bulwark", "bulwark_protocol", 1, "LATE", 550, ["sq_size", "c3"], dict(reason="HUD_ADVICE_N_BULWARK")),
]

GUIDES = [
    # hero, name, summary key, roles, nodes, simple list (old readers)
    ("hero_vesper_loom", "Loom Weaver", "HUD_ADVICE_B_VESPER", ["commander"], mana_core(SQUAD_COMMANDER)),
    ("hero_sable", "Shadow Edge", "HUD_ADVICE_B_SABLE", ["infiltrator"], mana_core(SQUAD_LIGHT)),
    ("hero_hex", "Static Overload", "HUD_ADVICE_B_HEX", ["hacker"], mana_core(SQUAD_LIGHT, barrel=False)),
    ("hero_liora_vale", "Steady Light", "HUD_ADVICE_B_LIORA", ["healer"], mana_core(SQUAD_LIGHT)),
    ("hero_brannoc", "Bulwark Gunner", "HUD_ADVICE_B_BRANNOC", ["tank"], mech_core(SQUAD_FRONTLINE)),
    ("hero_ryker_vance", "Line Breaker", "HUD_ADVICE_B_RYKER", ["soldier"], mech_core(SQUAD_LIGHT)),
    ("hero_juniper_quill", "Snare Field", "HUD_ADVICE_B_JUNIPER", ["trapper"], mech_core(SQUAD_LIGHT)),
]


def arr_s(xs):
    return "PackedStringArray(" + ", ".join('"%s"' % x for x in xs) + ")"


def main(out_path):
    subs = []
    builds = []
    for gi, (hero, name, summary, roles, nodes) in enumerate(GUIDES):
        nodes = nodes + situational(None)
        node_refs = []
        simple = []
        for ni, (nid, item, target, sec, prio, req, o) in enumerate(nodes):
            rid = "n_%d_%d" % (gi, ni)
            node_refs.append('SubResource("%s")' % rid)
            lines = ['[sub_resource type="Resource" id="%s"]' % rid, 'script = ExtResource("3")',
                     'id = &"%s"' % nid, 'item_id = &"%s"' % item, 'target = %d' % target,
                     'section = %d' % SECTIONS.index(sec), 'priority = %d' % prio]
            if req: lines.append('requires = ' + arr_s(req))
            if o.get("alts"): lines.append('alternatives = ' + arr_s(o["alts"]))
            if o.get("cond"): lines.append('conditions = ' + arr_s(o["cond"]))
            if o.get("reason"): lines.append('reason_key = "%s"' % o["reason"])
            if o.get("core") is False: lines.append('core = false')
            for flag in ("optional", "fallback", "skippable", "expert"):
                if o.get(flag): lines.append('%s = true' % flag)
            if o.get("min_s"): lines.append('min_s = %d' % o["min_s"])
            if o.get("max_s"): lines.append('max_s = %d' % o["max_s"])
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
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(root, "assets/data/economy/recommended_builds_slice.tres"))
