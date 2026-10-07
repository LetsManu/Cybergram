#!/usr/bin/env python3
"""Writes the Armory v2 catalog (protocol 22) from the approved GDD tables.

Source of truth: design/gdd/items-and-armory.md §3.5 (content), §3.11 (order =
wire id). Catalog order is append-only from v22 on. The Med-Pack and the 8
squad upgrades are copied unchanged from the v1 catalog (same fields, new
order for Tether / Quick Mint / Bulwark).

Run:  python3 tools/armory/build_catalog.py   (then $GODOT --headless --path . --import)
"""
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
V1 = os.path.join(ROOT, "assets/data/economy/armory_catalog_slice.tres")
OUT = os.path.join(ROOT, "assets/data/economy/armory_catalog_v22.tres")

# ArmoryItemDef enums
CONSUMABLE, SQUAD, MOUNT, AMMO, AMMO_MOD, GEAR = range(6)
NONE_SOCKET, CORE, BARREL, FRAME, CHAMBER = range(5)
T_NONE, COMPONENT, ASSEMBLY, SIGNATURE = range(4)
ADD = 0
# DamageMath ammo types / mods (C2 implements the new ones).
AMMO_IDS = {"piercing": 1, "sunder": 2, "incendiary": 3, "shock": 4, "siphon": 5, "cryo": 6}
MOD_IDS = {"saturated": 1, "lingering": 2, "volatile": 3, "tracer": 4, "overcharged": 5}

V1_KEEP = ["med_pack", "squad_expansion_1", "squad_expansion_2", "reinforced_cores_1", "reinforced_cores_2",
           "amplifier_emitters", "harmonic_tether", "quick_mint", "bulwark_protocol"]

HUES = {
    "ember": (1.0, 0.62, 0.2), "tempo": (0.66, 0.45, 1.0), "lens": (0.92, 0.95, 1.0),
    "steady": (0.35, 0.85, 0.7), "feed": (0.4, 0.95, 0.45), "bore": (0.95, 0.3, 0.75),
    "vital": (1.0, 0.45, 0.45), "plate": (0.75, 0.78, 0.82), "null": (0.6, 0.9, 1.0),
    "cadence": (1.0, 0.85, 0.4), "stride": (0.95, 0.95, 0.6), "breaker": (1.0, 0.32, 0.28),
}


def S(*pairs):
    """[(stat, value), ...] -> (ids, ops, values)."""
    return [p[0] for p in pairs], [ADD] * len(pairs), [p[1] for p in pairs]


# id, crystal name, chip name, kind, tier, socket, price (components) or combine, recipe,
# stats, mech stats, passive, anchor, hue, category, tags, counter_tags
ITEMS = []


def item(id_, name, chip, kind, tier, socket, price, recipe, stats, mech=None, passive="", anchor="",
         hue="ember", category="offense", tags=(), counters=(), effect=""):
    ITEMS.append(dict(id=id_, name=name, chip=chip, kind=kind, tier=tier, socket=socket, price=price,
                      recipe=list(recipe), stats=stats, mech=mech, passive=passive, anchor=anchor, hue=hue,
                      category=category, tags=list(tags), counters=list(counters), effect=effect))


# --- Components (9-18) ---
item("ember_part", "Ember Shard", "Ember Chip", MOUNT, COMPONENT, NONE_SOCKET, 400, [],
     S(("mod_damage", 0.05)), anchor="body_belt", hue="ember", tags=["starter", "offensive"],
     effect="Weapon damage +5%.")
item("tempo_part", "Tempo Shard", "Tempo Chip", MOUNT, COMPONENT, NONE_SOCKET, 350, [],
     S(("fire_rate_bonus", 0.04)), anchor="body_belt", hue="tempo", tags=["starter", "offensive"],
     effect="Fire rate +4%.")
item("lens_part", "Lens Shard", "Lens Chip", MOUNT, COMPONENT, NONE_SOCKET, 300, [],
     S(("falloff_range", 0.10)), anchor="body_belt", hue="lens", tags=["starter"], effect="Falloff range +10%.")
item("steady_part", "Steady Shard", "Steady Chip", MOUNT, COMPONENT, NONE_SOCKET, 250, [],
     S(("spread_mult", -0.10), ("recoil_mult", -0.10)), anchor="body_belt", hue="steady", category="utility",
     tags=["starter"], effect="Spread and recoil -10%.")
item("feed_part", "Feed Shard", "Feed Chip", MOUNT, COMPONENT, NONE_SOCKET, 350, [],
     S(("mana_regen", 0.10)), mech=S(("reload_time", -0.08)), anchor="body_belt", hue="feed", category="utility",
     tags=["starter"], effect="Mana regen +10% / reload time -8%.")
item("vital_cell", "Vital Cell", "", GEAR, COMPONENT, NONE_SOCKET, 300, [],
     S(("item_max_hp", 25.0)), anchor="body_chest", hue="vital", category="defense", tags=["starter", "defensive"],
     effect="Max HP +25.")
item("plate_scale", "Plate Scale", "", GEAR, COMPONENT, NONE_SOCKET, 300, [],
     S(("gear_armor", 0.08)), anchor="body_shoulders", hue="plate", category="defense", tags=["defensive"],
     counters=["weapon_dps", "burst"], effect="Armor +8% (weapon damage).")
item("null_thread", "Null Thread", "", GEAR, COMPONENT, NONE_SOCKET, 300, [],
     S(("gear_resist", 0.09)), anchor="body_back", hue="null", category="defense", tags=["defensive"],
     counters=["skill_dps", "zone", "cc"], effect="Resist +9% (skill damage).")
item("cadence_bead", "Cadence Bead", "", GEAR, COMPONENT, NONE_SOCKET, 350, [],
     S(("cooldown_reduction", 0.05)), anchor="body_head", hue="cadence", category="utility", tags=["utility"],
     effect="Skill cooldowns -5%.")
item("stride_clip", "Stride Clip", "", GEAR, COMPONENT, NONE_SOCKET, 250, [],
     S(("item_move_speed", 0.03), ("cell_carry_speed", 0.15)), anchor="body_legs", hue="stride", category="utility",
     tags=["utility"], effect="Move speed +3%; +15% carrying a Mana Cell.")

# --- Assemblies (19-28) ---
item("ember_facet", "Ember Facet", "Ember Board", MOUNT, ASSEMBLY, CORE, 300, ["ember_part", "lens_part"],
     S(("mod_damage", 0.10), ("falloff_range", 0.05)), hue="ember", tags=["core", "offensive"],
     effect="Damage +10%, falloff +5%.")
item("pulse_facet", "Pulse Facet", "Pulse Board", MOUNT, ASSEMBLY, CORE, 300, ["tempo_part", "steady_part"],
     S(("fire_rate_bonus", 0.08), ("spread_mult", -0.05)), hue="tempo", tags=["core", "offensive"],
     effect="Fire rate +8%, spread -5%.")
item("longsight_ring", "Longsight Ring", "Longsight Rail", MOUNT, ASSEMBLY, BARREL, 300, ["lens_part", "steady_part"],
     S(("falloff_range", 0.18), ("spread_mult", -0.08)), hue="lens", tags=["core"],
     effect="Falloff +18%, spread -8%.")
item("bore_ring", "Bore Ring", "Bore Rail", MOUNT, ASSEMBLY, BARREL, 300, ["ember_part", "steady_part"],
     S(("armor_pen_bonus", 0.15), ("mod_damage", 0.03)), hue="bore", tags=["counter"], counters=["frontline"],
     effect="Armor pen +15%, damage +3%.")
item("wellframe", "Wellframe", "", MOUNT, ASSEMBLY, FRAME, 250, ["feed_part", "steady_part"],
     S(("capacity_mult", 0.15), ("mana_regen", 0.08), ("recoil_mult", -0.08)),
     mech=S(("capacity_mult", 0.15), ("reload_time", -0.06), ("recoil_mult", -0.08)), hue="feed", category="utility",
     tags=["core"], effect="Pool / magazine +15%, regen +8% / reload -6%, recoil -8%.")
item("vital_core", "Vital Core", "", GEAR, ASSEMBLY, NONE_SOCKET, 300, ["vital_cell", "vital_cell"],
     S(("item_max_hp", 75.0)), anchor="body_chest", hue="vital", category="defense", tags=["defensive"],
     effect="Max HP +75.")
item("plate_harness", "Plate Harness", "", GEAR, ASSEMBLY, NONE_SOCKET, 300, ["plate_scale", "vital_cell"],
     S(("gear_armor", 0.13), ("item_max_hp", 25.0)), anchor="body_shoulders", hue="plate", category="defense",
     tags=["defensive"], counters=["weapon_dps", "burst"], effect="Armor +13%, max HP +25.")
item("null_cowl", "Null Cowl", "", GEAR, ASSEMBLY, NONE_SOCKET, 300, ["null_thread", "vital_cell"],
     S(("gear_resist", 0.15), ("item_max_hp", 25.0)), anchor="body_back", hue="null", category="defense",
     tags=["defensive"], counters=["skill_dps", "zone", "cc"], effect="Resist +15%, max HP +25.")
item("cadence_circlet", "Cadence Circlet", "", GEAR, ASSEMBLY, NONE_SOCKET, 300, ["cadence_bead", "null_thread"],
     S(("cooldown_reduction", 0.10), ("gear_resist", 0.06)), anchor="body_head", hue="cadence", category="utility",
     tags=["utility"], effect="Skill cooldowns -10%, resist +6%.")
item("stride_rig", "Stride Rig", "", GEAR, ASSEMBLY, NONE_SOCKET, 250, ["stride_clip", "plate_scale"],
     S(("item_move_speed", 0.04), ("ooc_move_speed", 0.08), ("gear_armor", 0.04), ("cell_carry_speed", 0.15)),
     anchor="body_legs", hue="stride", category="utility", tags=["utility"],
     effect="Move speed +4% (+8% out of combat), armor +4%.")

# --- Signatures (29-42) ---
item("ember_heart", "Ember Heart", "Overclock Core", MOUNT, SIGNATURE, CORE, 800,
     ["ember_facet", "ember_part", "tempo_part"], S(("mod_damage", 0.16), ("fire_rate_bonus", 0.03)),
     passive="kindle", hue="ember", tags=["core", "offensive"], effect="Damage +16%, fire rate +3%. Kindle.")
item("tempest_heart", "Tempest Heart", "Cyclic Governor", MOUNT, SIGNATURE, CORE, 750,
     ["pulse_facet", "tempo_part", "ember_part"],
     S(("fire_rate_bonus", 0.12), ("mod_damage", 0.03), ("spread_mult", -0.05)), passive="overdrive_loop",
     hue="tempo", tags=["core", "offensive"], effect="Fire rate +12%, damage +3%, spread -5%. Overdrive Loop.")
item("prism_eye", "Prism Eye", "Ballistic Solver", MOUNT, SIGNATURE, CORE, 950,
     ["ember_facet", "lens_part", "steady_part"], S(("mod_damage", 0.06), ("headshot_bonus", 0.30)),
     passive="true_line", hue="lens", tags=["core", "offensive"], effect="Damage +6%, headshot +0.30. True Line.")
item("longsight_lens", "Longsight Lens", "Longsight Rifling", MOUNT, SIGNATURE, BARREL, 1000,
     ["longsight_ring", "lens_part", "steady_part"], S(("falloff_range", 0.30), ("spread_mult", -0.15)),
     passive="long_reach", hue="lens", tags=["core"], counters=["mobility"],
     effect="Falloff +30%, spread -15%. Long Reach.")
item("breaker_bore", "Breaker Bore", "", MOUNT, SIGNATURE, BARREL, 850,
     ["bore_ring", "ember_part", "lens_part"],
     S(("armor_pen_bonus", 0.25), ("mod_damage", 0.04), ("falloff_range", 0.05)), passive="rend", hue="bore",
     tags=["counter"], counters=["frontline"], effect="Armor pen +25%, damage +4%, falloff +5%. Rend.")
item("reservoir_frame", "Reservoir Frame", "Extended Frame", MOUNT, SIGNATURE, FRAME, 950,
     ["wellframe", "feed_part", "steady_part"], S(("capacity_mult", 0.45)), passive="deep_reserve", hue="feed",
     category="utility", tags=["core"], effect="Pool / magazine +45%. Deep Reserve.")
item("flux_coil", "Flux Coil", "Quickload Coil", MOUNT, SIGNATURE, FRAME, 900,
     ["wellframe", "feed_part", "tempo_part"], S(("mana_regen", 0.30), ("regen_delay", -0.3)),
     mech=S(("reload_time", -0.28)), passive="cold_start", hue="tempo", category="utility", tags=["core"],
     effect="Mana regen +30%, regen delay -0.3 s / reload -28%. Cold Start.")
item("anchor_frame", "Anchor Frame", "Gyro Frame", MOUNT, SIGNATURE, FRAME, 1000,
     ["wellframe", "steady_part", "lens_part"],
     S(("recoil_mult", -0.35), ("spread_mult", -0.15), ("capacity_mult", 0.15)), passive="planted", hue="ember",
     category="utility", tags=["core"], effect="Recoil -35%, spread -15%, pool / magazine +15%. Planted.")
item("bastion_plate", "Bastion Plate", "", GEAR, SIGNATURE, NONE_SOCKET, 900,
     ["plate_harness", "plate_scale", "vital_cell"], S(("gear_armor", 0.20), ("item_max_hp", 60.0)),
     passive="brace", anchor="body_shoulders", hue="plate", category="defense", tags=["defensive"],
     counters=["weapon_dps", "burst"], effect="Armor +20%, max HP +60. Brace.")
item("null_veil", "Null Veil", "", GEAR, SIGNATURE, NONE_SOCKET, 900,
     ["null_cowl", "null_thread", "vital_cell"], S(("gear_resist", 0.22), ("item_max_hp", 60.0)),
     passive="grounding", anchor="body_back", hue="null", category="defense", tags=["defensive"],
     counters=["skill_dps", "zone", "cc"], effect="Resist +22% (capped at 20%), max HP +60. Grounding.")
item("vigil_core", "Vigil Core", "", GEAR, SIGNATURE, NONE_SOCKET, 900,
     ["vital_core", "vital_cell", "plate_scale"], S(("item_max_hp", 130.0), ("gear_armor", 0.04)),
     passive="regrowth", anchor="body_chest", hue="vital", category="defense", tags=["defensive"],
     counters=["burst"], effect="Max HP +130, armor +4%. Regrowth.")
item("barrier_lattice", "Barrier Lattice", "", GEAR, SIGNATURE, NONE_SOCKET, 900,
     ["vital_core", "null_thread", "vital_cell"], S(("item_max_hp", 60.0), ("gear_resist", 0.08)),
     passive="lattice", anchor="body_back", hue="null", category="defense", tags=["defensive"],
     counters=["burst", "skill_dps"], effect="Max HP +60, resist +8%. Lattice overshield.")
item("cadence_crown", "Cadence Crown", "", GEAR, SIGNATURE, NONE_SOCKET, 900,
     ["cadence_circlet", "cadence_bead", "null_thread"], S(("cooldown_reduction", 0.18), ("gear_resist", 0.08)),
     passive="resonant_cast", anchor="body_head", hue="cadence", category="utility", tags=["utility"],
     effect="Skill cooldowns -18%, resist +8%. Resonant Cast.")
item("breaker_sigil", "Breaker Sigil", "", GEAR, SIGNATURE, NONE_SOCKET, 700,
     ["stride_rig", "plate_harness"],
     S(("item_max_hp", 60.0), ("gear_armor", 0.06), ("item_move_speed", 0.04)), passive="siegebreaker",
     anchor="body_forearm", hue="breaker", category="utility", tags=["utility"],
     effect="Max HP +60, armor +6%, move speed +4%. Siegebreaker.")

# --- Ammo Types (43-48) and Mods (49-53): weapons-and-mods.md §3.7, prices §3.8 ---
AMMO_ITEMS = [
    ("ammo_piercing", "Piercing", 750, "piercing", ["frontline"], "Ignores 40% of target armor."),
    ("ammo_incendiary", "Incendiary", 800, "incendiary", ["sustain"], "Burn + Scorched (-30% healing)."),
    ("ammo_shock", "Shock", 800, "shock", ["squad"], "Charge -> Overload arcs; Disrupts the target's weapon."),
    ("ammo_siphon", "Siphon", 850, "siphon", [], "Heals you for 8% of damage to heroes."),
    ("ammo_cryo", "Cryo", 750, "cryo", ["mobility"], "Chill slows up to 25%; full meter = Brittle."),
    ("ammo_sunder", "Sunder", 650, "sunder", ["squad"], "+35% vs constructs, +20% vs structures, -10% vs heroes."),
]
# Last field: Ammo Types the mod works with (weapons-and-mods.md §3.7.2 table; [] = all).
MOD_ITEMS = [
    ("mod_saturated", "Saturated", 350, "saturated", "Ammo effect potency x1.3.", []),
    ("mod_lingering", "Lingering", 300, "lingering", "Ammo effect duration x1.5.", ["incendiary", "shock", "cryo"]),
    ("mod_volatile", "Volatile", 400, "volatile", "On kill, the ammo effect bursts to enemies within 4 m.",
     ["incendiary", "shock", "siphon", "cryo", "sunder"]),
    ("mod_tracer", "Tracer", 300, "tracer", "Affected targets are marked for your team for 1.5 s.", []),
    ("mod_overcharged", "Overcharged", 350, "overcharged", "Potency x1.5; mana cost +20% / reload +15%.", []),
]


def v1_blocks():
    """id -> list of property lines of the v1 sub_resource."""
    text = open(V1).read().split("\n[resource]")[0]
    out = {}
    for blk in re.split(r"\n(?=\[sub_resource )", text):
        if not blk.startswith("[sub_resource"):
            continue
        lines = blk.strip().split("\n")[1:]
        m = re.search(r'^id = &"([^"]+)"', "\n".join(lines), re.M)
        if m:
            out[m.group(1)] = [l for l in lines if l.strip()]
    return out


def gd_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def psa(xs):
    return "PackedStringArray(" + ", ".join(gd_str(x) for x in xs) + ")"


def pia(xs):
    return "PackedInt32Array(" + ", ".join(str(int(x)) for x in xs) + ")"


def pfa(xs):
    return "PackedFloat32Array(" + ", ".join(repr(float(x)) for x in xs) + ")"


def color(c):
    return "Color(%s, %s, %s, 1)" % c


def totals():
    by = {it["id"]: it for it in ITEMS}
    memo = {}

    def total(i):
        if i in memo:
            return memo[i]
        it = by[i]
        t = it["price"] if it["tier"] == COMPONENT else it["price"] + sum(total(p) for p in it["recipe"])
        memo[i] = t
        return t

    return {i: total(i) for i in by}


def main():
    v1 = v1_blocks()
    tot = totals()
    lines = ['[gd_resource type="Resource" script_class="ArmoryCatalogDef" format=3]', "",
             '[ext_resource type="Script" path="res://src/gameplay/data/armory_item_def.gd" id="1"]',
             '[ext_resource type="Script" path="res://src/gameplay/data/armory_catalog_def.gd" id="2"]', ""]
    idx = 0
    for vid in V1_KEEP:
        if vid not in v1:
            sys.exit("v1 item missing: " + vid)
        lines += ['[sub_resource type="Resource" id="item_%d"]' % idx] + v1[vid] + [""]
        idx += 1
    for it in ITEMS:
        L = ['[sub_resource type="Resource" id="item_%d"]' % idx, 'script = ExtResource("1")',
             'id = &"%s"' % it["id"], "display_name = " + gd_str(it["name"]),
             "effect_text = " + gd_str(it["effect"]), "kind = %d" % it["kind"], "socket = %d" % it["socket"],
             "family = 0", "prices = " + pia([tot[it["id"]]])]
        ids, ops, vals = it["stats"]
        L += ["hue = " + color(HUES[it["hue"]]), "category = &\"%s\"" % it["category"]]
        if it["tags"]:
            L.append("tags = " + psa(it["tags"]))
        if it["counters"]:
            L.append("counter_tags = " + psa(it["counters"]))
        L += ["tier = %d" % it["tier"]]
        if it["recipe"]:
            L += ["recipe = " + psa(it["recipe"]), "combine_cost = %d" % it["price"]]
        L += ["stat_ids = " + psa(ids), "stat_ops = " + pia(ops), "stat_values = " + pfa(vals)]
        if it["mech"]:
            mi, mo, mv = it["mech"]
            L += ["mech_stat_ids = " + psa(mi), "mech_stat_ops = " + pia(mo), "mech_stat_values = " + pfa(mv)]
        if it["passive"]:
            L.append('passive = &"%s"' % it["passive"])
        if it["anchor"]:
            L.append('body_anchor = &"%s"' % it["anchor"])
        if it["chip"]:
            L.append("chip_name = " + gd_str(it["chip"]))
        lines += L + [""]
        idx += 1
    for aid, name, price, kind_name, counters, eff in AMMO_ITEMS:
        L = ['[sub_resource type="Resource" id="item_%d"]' % idx, 'script = ExtResource("1")', 'id = &"%s"' % aid,
             "display_name = " + gd_str(name), "effect_text = " + gd_str(eff), "kind = %d" % AMMO,
             "socket = %d" % CHAMBER, "family = 0", "prices = " + pia([price]),
             "ammo_type = %d" % AMMO_IDS[kind_name], "hue = " + color((0.7, 0.8, 1.0)), 'category = &"offense"',
             'tags = PackedStringArray("counter")']
        if counters:
            L.append("counter_tags = " + psa(counters))
        lines += L + [""]
        idx += 1
    for mid, name, price, mod_name, eff, fits in MOD_ITEMS:
        L = ['[sub_resource type="Resource" id="item_%d"]' % idx, 'script = ExtResource("1")', 'id = &"%s"' % mid,
             "display_name = " + gd_str(name), "effect_text = " + gd_str(eff), "kind = %d" % AMMO_MOD,
             "socket = %d" % CHAMBER, "family = 0", "prices = " + pia([price]),
             "ammo_mod = %d" % MOD_IDS[mod_name], "hue = " + color((0.85, 0.75, 1.0)), 'category = &"offense"',
             'tags = PackedStringArray("luxury")']
        if fits:
            L.append("fits_ammo = " + pia([AMMO_IDS[f] for f in fits]))
        lines += L + [""]
        idx += 1
    lines += ["[resource]", 'script = ExtResource("2")',
              "items = Array[ExtResource(\"1\")]([" + ", ".join('SubResource("item_%d")' % i for i in range(idx)) + "])",
              ""]
    open(OUT, "w").write("\n".join(lines))
    print("wrote", OUT, idx, "items")
    for k in ("ember_heart", "tempest_heart", "bastion_plate", "breaker_sigil", "vital_core"):
        print("  total", k, tot[k])


if __name__ == "__main__":
    main()
