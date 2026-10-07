extends GdUnitTestSuite
## ArmoryValidator: the shipped catalog, heroes and recommended builds are
## clean, and each class of data mistake is reported (unknown ids, bad tiers,
## requirement / prerequisite cycles, wire-index limits, wrong family,
## disabled items, unknown hero / mode / condition, unique groups).

const HERO_DIR := "res://assets/data/heroes"


func _heroes() -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(HERO_DIR):
		if f.ends_with(".tres"):
			out.append(load(HERO_DIR.path_join(f)))
	return out


func _hero(id: StringName) -> HeroDef:
	for h in _heroes():
		if h.id == id:
			return h
	return null


func _item(id: StringName, kind := ArmoryItemDef.Kind.MOUNT, prices := PackedInt32Array([300, 700, 1500])) -> ArmoryItemDef:
	var it := ArmoryItemDef.new()
	it.id = id
	it.kind = kind
	it.prices = prices
	if kind == ArmoryItemDef.Kind.MOUNT:
		it.socket = ArmoryItemDef.Socket.CORE
		it.stat = &"mod_damage"
		it.values = PackedFloat32Array([0.05, 0.1, 0.15])
	elif kind == ArmoryItemDef.Kind.CONSUMABLE:
		it.carry_limit = 3
	return it


func _cat(items: Array) -> ArmoryCatalogDef:
	var c := ArmoryCatalogDef.new()
	for i in items:
		c.items.append(i)
	return c


func _simple_build(hero: StringName, ids: Array, targets: Array) -> RecommendedBuildsDef:
	var b := RecommendedBuildDef.new()
	b.hero_id = hero
	b.display_name = "T"
	b.item_ids = PackedStringArray(ids)
	b.targets = PackedInt32Array(targets)
	var bs := RecommendedBuildsDef.new()
	bs.builds.append(b)
	return bs


func _node(id: StringName, item: StringName, target := 1, requires: Array = []) -> BuildNodeDef:
	var n := BuildNodeDef.new()
	n.id = id
	n.item_id = item
	n.target = target
	n.requires = PackedStringArray(requires)
	return n


func _errors(r: Dictionary) -> String:
	return "\n".join(r["errors"])


func test_shipped_data_has_no_errors() -> void:
	var cat := load(ArmoryCatalogDef.DEFAULT_PATH) as ArmoryCatalogDef
	var builds := load(RecommendedBuildsDef.DEFAULT_PATH) as RecommendedBuildsDef
	var r := ArmoryValidator.check(cat, builds, _heroes())
	assert_array(r["errors"]).override_failure_message(_errors(r)).is_empty()


func test_every_hero_has_a_known_role_and_matches_the_menu_role() -> void:
	for h: HeroDef in _heroes():
		assert_bool(h.roles.is_empty()).override_failure_message("%s has no role" % h.id).is_false()
		var stem := String(h.id).trim_prefix("hero_")
		var menu_key := String(HeroShowcase.ROLE_KEYS.get(stem, ""))
		assert_str(menu_key).is_equal("HUD_ROLE_" + h.roles[0].to_upper())


func test_unknown_item_bad_tier_and_count_are_errors() -> void:
	var cat := _cat([_item(&"core_a"), _item(&"pack", ArmoryItemDef.Kind.CONSUMABLE, PackedInt32Array([100]))])
	var r := ArmoryValidator.check(cat, _simple_build(&"h", ["nope", "core_a", "pack"], [1, 4, 5]))
	var e := _errors(r)
	assert_str(e).contains("unknown item nope")
	assert_str(e).contains("core_a tier 4 outside 1..3")
	assert_str(e).contains("pack count 5 outside 1..3")


func test_item_and_target_lists_must_match() -> void:
	var r := ArmoryValidator.check(_cat([_item(&"core_a")]), _simple_build(&"h", ["core_a"], [1, 2]))
	assert_str(_errors(r)).contains("1 item_ids but 2 targets")


func test_requirement_cycles_and_unknown_requirements() -> void:
	var a := _item(&"a", ArmoryItemDef.Kind.SQUAD, PackedInt32Array([300]))
	var b := _item(&"b", ArmoryItemDef.Kind.SQUAD, PackedInt32Array([300]))
	var c := _item(&"c", ArmoryItemDef.Kind.SQUAD, PackedInt32Array([300]))
	a.requires = &"b"
	b.requires = &"a"
	c.requires = &"missing"
	var e := _errors(ArmoryValidator.check(_cat([a, b, c])))
	assert_str(e).contains("item a: requirement cycle")
	assert_str(e).contains("requires unknown item missing")


func test_tier_prices_must_rise_and_values_match_tiers() -> void:
	var it := _item(&"flat", ArmoryItemDef.Kind.MOUNT, PackedInt32Array([500, 500, 900]))
	it.values = PackedFloat32Array([0.1, 0.2])
	var e := _errors(ArmoryValidator.check(_cat([it])))
	assert_str(e).contains("tier 2 price not above tier 1")
	assert_str(e).contains("2 values for 3 tiers")


func test_wire_index_limits_for_squad_and_mounts() -> void:
	var items: Array = []
	for i in 32:
		items.append(_item(StringName("pad_%d" % i), ArmoryItemDef.Kind.CONSUMABLE, PackedInt32Array([100])))
	items.append(_item(&"late_squad", ArmoryItemDef.Kind.SQUAD, PackedInt32Array([500])))
	assert_str(_errors(ArmoryValidator.check(_cat(items)))).contains("squad index above 31")


func test_disabled_and_wrong_family_items_in_a_guide_are_errors() -> void:
	var cat := load(ArmoryCatalogDef.DEFAULT_PATH).duplicate(true) as ArmoryCatalogDef
	cat.find(&"flux_coil").disabled = true
	var b := RecommendedBuildDef.new()
	b.hero_id = &"hero_brannoc"
	b.display_name = "G"
	b.nodes.append(_node(&"n1", &"ember_heart"))  # Crystal on a Mech gun
	b.nodes.append(_node(&"n2", &"overclock", 1, ["n1"]))
	var bs := RecommendedBuildsDef.new()
	bs.builds.append(b)
	var b2 := RecommendedBuildDef.new()
	b2.hero_id = &"hero_vesper_loom"
	b2.display_name = "D"
	b2.nodes.append(_node(&"n1", &"flux_coil"))
	bs.builds.append(b2)
	var e := _errors(ArmoryValidator.check(cat, bs, _heroes()))
	assert_str(e).contains("ember_heart does not fit hero_brannoc's gun")
	assert_str(e).contains("item flux_coil is disabled")


func test_fallback_node_may_name_another_family_without_error() -> void:
	var cat := load(ArmoryCatalogDef.DEFAULT_PATH) as ArmoryCatalogDef
	var b := RecommendedBuildDef.new()
	b.hero_id = &"hero_brannoc"
	b.display_name = "F"
	var n := _node(&"n1", &"ember_heart")
	n.fallback = true
	b.nodes.append(n)
	var bs := RecommendedBuildsDef.new()
	bs.builds.append(b)
	var r := ArmoryValidator.check(cat, bs, _heroes())
	assert_array(r["errors"]).is_empty()
	assert_str("\n".join(r["warnings"])).contains("does not fit")


func test_guide_node_cycles_unknown_nodes_and_conditions() -> void:
	var cat := load(ArmoryCatalogDef.DEFAULT_PATH) as ArmoryCatalogDef
	var b := RecommendedBuildDef.new()
	b.hero_id = &"hero_vesper_loom"
	b.display_name = "C"
	b.nodes.append(_node(&"a", &"ember_heart", 1, ["b"]))
	b.nodes.append(_node(&"b", &"flux_coil", 1, ["a"]))
	var c := _node(&"c", &"med_pack", 1, ["ghost"])
	c.conditions = PackedStringArray(["not_a_rule"])
	b.nodes.append(c)
	var bs := RecommendedBuildsDef.new()
	bs.builds.append(b)
	var e := _errors(ArmoryValidator.check(cat, bs, _heroes(), PackedStringArray(["core_tier_ready"])))
	assert_str(e).contains("node a: prerequisite cycle")
	assert_str(e).contains("requires unknown node ghost")
	assert_str(e).contains("unknown condition not_a_rule")


func test_guide_warns_when_a_catalog_prerequisite_is_never_bought() -> void:
	var cat := load(ArmoryCatalogDef.DEFAULT_PATH) as ArmoryCatalogDef
	var b := RecommendedBuildDef.new()
	b.hero_id = &"hero_vesper_loom"
	b.display_name = "P"
	b.nodes.append(_node(&"exp2", &"squad_expansion_2"))
	var bs := RecommendedBuildsDef.new()
	bs.builds.append(b)
	var r := ArmoryValidator.check(cat, bs, _heroes())
	assert_str("\n".join(r["warnings"])).contains("needs squad_expansion_1")


func test_unknown_hero_mode_and_tags() -> void:
	var cat := _cat([_item(&"core_a")])
	cat.items[0].tags = PackedStringArray(["shiny"])
	var bs := _simple_build(&"hero_nobody", ["core_a"], [1])
	bs.builds[0].modes = PackedStringArray(["4v4"])
	var e := _errors(ArmoryValidator.check(cat, bs, _heroes()))
	assert_str(e).contains("unknown tag shiny")
	assert_str(e).contains("unknown hero")
	assert_str(e).contains("unknown mode 4v4")


func test_unique_group_members_must_share_a_socket() -> void:
	var a := _item(&"a")
	var b := _item(&"b")
	b.socket = ArmoryItemDef.Socket.FRAME
	a.unique_group = &"g"
	b.unique_group = &"g"
	assert_str(_errors(ArmoryValidator.check(_cat([a, b])))).contains("unique group g")


func test_hero_roles_and_tags_from_data() -> void:
	var b := _hero(&"hero_brannoc")
	assert_array(Array(b.roles)).contains(["tank"])
	assert_array(Array(b.tags)).contains(["cc"])


# --- Armory v2 (v22 catalog) -------------------------------------------------------

func _v22() -> ArmoryCatalogDef:
	return (load(ArmoryCatalogDef.V22_PATH) as ArmoryCatalogDef).duplicate(true) as ArmoryCatalogDef


func _errors_of(cat: ArmoryCatalogDef) -> String:
	return "\n".join(ArmoryValidator.check(cat)["errors"])


func test_v22_catalog_is_clean() -> void:
	var r := ArmoryValidator.check(load(ArmoryCatalogDef.V22_PATH) as ArmoryCatalogDef)
	assert_array(Array(r["errors"])).is_empty()


func test_v22_recipe_mistakes_are_reported() -> void:
	var c := _v22()
	c.find(&"ember_heart").prices = PackedInt32Array([2500])  # not the recipe total 2,550
	c.find(&"pulse_facet").recipe = PackedStringArray(["tempo_part", "ghost_part"])
	c.find(&"vital_core").recipe = PackedStringArray(["vital_core", "vital_cell"])  # itself / not lower
	c.find(&"bastion_plate").passive = &""
	c.find(&"null_thread").stat_values = PackedFloat32Array([0.23])  # 3 points over the 0.20 cap
	c.find(&"plate_scale").body_anchor = &""
	c.find(&"bore_ring").socket = ArmoryItemDef.Socket.NONE
	var e := _errors_of(c)
	assert_str(e).contains("ember_heart").contains("recipe total 2550")
	assert_str(e).contains("recipe part ghost_part unknown")
	assert_str(e).contains("vital_core").contains("not a lower tier")
	assert_str(e).contains("bastion_plate").contains("needs a passive")
	assert_str(e).contains("null_thread").contains("over its cap")
	assert_str(e).contains("plate_scale").contains("body_anchor")
	assert_str(e).contains("bore_ring").contains("Core, Barrel or Frame")
	# Null Veil's +22% resist (2 points over) stays allowed.
	assert_str(e).not_contains("null_veil")
