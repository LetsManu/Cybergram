extends GdUnitTestSuite
## Armory v2 shop model (ItemShopModel, design/gdd/items-and-armory.md §3.9):
## prices with owned parts (§4.1), greyed reasons that match the server
## (§3.6: Inventory full, Signature limit, Already owned, needs an Ammo Type,
## incompatible mod), sell values (§4.4), undo availability (§3.6 rule 8),
## spares, "(capped)" stats (§3.7), the recipe tree and the Recommended sections.

const VESPER := &"hero_vesper_loom"

var _cat: ArmoryCatalogDef
var _rules: EconomyRulesDef
var _guides: RecommendedBuildsDef


func before_test() -> void:
	_cat = load(ArmoryCatalogDef.DEFAULT_PATH) as ArmoryCatalogDef
	_rules = load(GameSession.ECONOMY_RULES) as EconomyRulesDef
	_guides = load(RecommendedBuildsDef.DEFAULT_PATH) as RecommendedBuildsDef


## A model over a progress block holding `places` ({place: item id}) and `lumen`.
func _model(places: Dictionary, lumen: int = 5000) -> ItemShopModel:
	var p := SnapshotData.ProgressState.new()
	p.lumen = lumen
	for k in places:
		p.inv_items[int(k)] = _cat.index_of(StringName(places[k]))
	var m := ItemShopModel.new(_cat, _rules, _guides, VESPER, CombatFixtures.vesper().weapon)
	m.update(p)
	return m


func _i(id: StringName) -> int:
	return _cat.index_of(id)


func test_price_uses_owned_parts_and_total_stays_full() -> void:
	var m := _model({ItemShopModel.P_SLOT: &"ember_part"})
	assert_int(m.total(_i(&"ember_facet"))).is_equal(1000)
	assert_int(m.cost(_i(&"ember_facet"))).is_equal(600)  # 300 lens + 300 combine
	assert_int(_model({}).cost(_i(&"ember_facet"))).is_equal(1000)
	# A component is always bought whole (a second copy is a spare).
	assert_int(m.cost(_i(&"ember_part"))).is_equal(400)


func test_recipe_tree_ticks_owned_parts() -> void:
	var m := _model({ItemShopModel.P_SLOT: &"ember_part", ItemShopModel.P_SLOT + 1: &"tempo_part"})
	var t := m.tree(_i(&"ember_heart"))
	assert_int(t[0]["index"]).is_equal(_i(&"ember_heart"))
	assert_bool(t[0]["owned"]).is_false()
	var owned := {}
	for e in t:
		if bool(e["owned"]):
			owned[_cat.at(int(e["index"])).id] = int(e["place"])
	# ember_part goes to the Assembly first (deepest first), tempo_part to the top recipe.
	assert_dict(owned).contains_keys([&"ember_part", &"tempo_part"])
	assert_array(m.builds_into(_i(&"ember_facet"))).contains([_i(&"ember_heart"), _i(&"prism_eye")])


func test_inventory_full_but_a_combine_that_frees_slots_is_allowed() -> void:
	var m := _model({ItemShopModel.P_SLOT: &"ember_part", ItemShopModel.P_SLOT + 1: &"lens_part", ItemShopModel.P_SLOT + 2: &"vital_cell",
		ItemShopModel.P_SLOT + 3: &"plate_scale", ItemShopModel.P_SLOT + 4: &"null_thread", ItemShopModel.P_SLOT + 5: &"cadence_bead"})
	assert_int(m.state(_i(&"tempo_part"))).is_equal(ItemShopModel.State.INVENTORY_FULL)
	assert_int(m.state(_i(&"ember_facet"))).is_equal(ItemShopModel.State.AVAILABLE)  # goes to the Core socket, frees 2
	assert_int(m.state(_i(&"plate_harness"))).is_equal(ItemShopModel.State.AVAILABLE)  # 2 parts out, 1 gear in
	assert_str(ItemShopModel.state_key(ItemShopModel.State.INVENTORY_FULL)).is_equal("HUD_SHOP2_INVENTORY_FULL")


func test_signature_limit_and_already_owned() -> void:
	var m := _model({ItemShopModel.P_CORE: &"ember_heart", ItemShopModel.P_SLOT: &"bastion_plate"})
	assert_object(m.signatures()).is_equal(Vector2i(2, 2))
	assert_int(m.state(_i(&"null_veil"))).is_equal(ItemShopModel.State.SIGNATURE_LIMIT)
	assert_int(m.state(_i(&"ember_heart"))).is_equal(ItemShopModel.State.ALREADY_OWNED)
	assert_int(m.state(_i(&"ember_facet"))).is_equal(ItemShopModel.State.AVAILABLE)  # Assemblies are not Signatures


func test_chamber_needs_ammo_and_incompatible_mod() -> void:
	var lingering := _cat.find(&"mod_lingering")
	var bad := ""
	var good := ""
	for it in _cat.items:
		if it.kind == ArmoryItemDef.Kind.AMMO:
			if lingering.fits_ammo.has(it.ammo_type):
				good = String(it.id)
			else:
				bad = String(it.id)
	assert_str(bad).is_not_empty()
	assert_int(_model({}).state(_i(&"mod_lingering"))).is_equal(ItemShopModel.State.NEEDS_AMMO)
	assert_int(_model({ItemShopModel.P_AMMO: StringName(bad)}).state(_i(&"mod_lingering"))).is_equal(ItemShopModel.State.INCOMPATIBLE)
	assert_int(_model({ItemShopModel.P_AMMO: StringName(good)}).state(_i(&"mod_lingering"))).is_equal(ItemShopModel.State.AVAILABLE)
	assert_int(_model({ItemShopModel.P_AMMO: StringName(good)}).state(_i(StringName(good)))).is_equal(ItemShopModel.State.ALREADY_OWNED)


func test_cant_afford_counts_the_swap_credit() -> void:
	var m := _model({ItemShopModel.P_BARREL: &"longsight_ring"}, 500)
	# Bore Ring does not build from Longsight Ring: it is sold (60% of 850 = 510).
	assert_int(m.swap_credit(_i(&"bore_ring"))).is_equal(510)
	assert_int(m.state(_i(&"bore_ring"))).is_equal(ItemShopModel.State.AVAILABLE)  # 950 <= 500 + 510
	var poor := _model({}, 500)
	assert_int(poor.state(_i(&"bore_ring"))).is_equal(ItemShopModel.State.CANT_AFFORD)
	assert_int(poor.shortfall(_i(&"bore_ring"))).is_equal(450)
	# Longsight Lens builds from the ring: no swap credit, the ring is used up.
	assert_int(m.swap_credit(_i(&"longsight_lens"))).is_equal(0)


func test_sell_value_and_undo_availability() -> void:
	var m := _model({ItemShopModel.P_CORE: &"ember_heart", ItemShopModel.P_SLOT: &"vital_cell"})
	assert_int(m.sell_value(ItemShopModel.P_CORE)).is_equal(1530)  # 60% of 2550
	assert_int(m.sell_arg(ItemShopModel.P_CORE)).is_equal(ItemInventory.LOC_CORE)
	assert_bool(m.can_undo(ItemShopModel.P_SLOT)).is_false()
	assert_int(m.undo_arg(ItemShopModel.P_SLOT)).is_equal(-1)
	assert_bool(m.undo_last_available()).is_false()
	m.progress.inv_undo_bits = 1 << ItemShopModel.P_SLOT
	m.progress.inv_txns = 2
	assert_int(m.undo_arg(ItemShopModel.P_SLOT)).is_equal(InputCommand.UNDO_ITEM_FLAG | ItemInventory.LOC_SLOT)
	assert_int(m.undo_arg(ItemShopModel.P_CORE)).is_equal(-1)  # bought earlier, or used by a later buy
	assert_bool(m.undo_last_available()).is_true()
	# Squad / Med-Pack row undo (§3.6 rule 8, unchanged rules).
	var med := _i(&"med_pack")
	assert_int(m.row_undo_arg(med)).is_equal(-1)
	m.progress.medpacks = 1
	m.progress.visit_medpacks = 1
	assert_int(m.row_undo_arg(med)).is_equal(InputCommand.UNDO_ITEM_FLAG | InputCommand.UNDO_ROW_FLAG | med)


func test_spares_give_nothing_and_capped_stats_show() -> void:
	var m := _model({ItemShopModel.P_SLOT: &"vital_cell", ItemShopModel.P_SLOT + 1: &"vital_cell"})
	assert_bool(m.is_spare(ItemShopModel.P_SLOT)).is_false()
	assert_bool(m.is_spare(ItemShopModel.P_SLOT + 1)).is_true()
	assert_float(m.current_stat("item_max_hp")).is_equal_approx(25.0, 0.01)
	assert_int(m.slots_used()).is_equal(2)
	# Bastion Plate is at the 0.20 armor cap: any more armor is wasted.
	var capped := _model({ItemShopModel.P_SLOT: &"bastion_plate"})
	var lines := capped.stat_lines(_i(&"plate_scale"))
	assert_str(String(lines[0]["id"])).is_equal("gear_armor")
	assert_bool(lines[0]["capped"]).is_true()
	assert_bool(_model({}).stat_lines(_i(&"plate_scale"))[0]["capped"]).is_false()
	assert_str(ItemShopModel.stat_text("item_max_hp", 25.0)).is_equal("+25")
	assert_str(ItemShopModel.stat_text("spread_mult", -0.1)).is_equal("-10%")


func test_filters_and_shelves() -> void:
	var m := _model({})
	var sh := m.shelves()
	assert_int(int(sh[0]["shelf"])).is_equal(ItemShopModel.Shelf.COMPONENT)
	assert_int(int(sh[1]["shelf"])).is_equal(ItemShopModel.Shelf.ASSEMBLY)
	assert_int(int(sh[2]["shelf"])).is_equal(ItemShopModel.Shelf.SIGNATURE)
	m.toggle_filter(&"armor")
	for s in m.shelves():
		for i in s["items"]:
			assert_bool(m.has_filter(i, &"armor")).is_true()
	m.toggle_filter(&"health")  # both: Plate Harness yes, Plate Scale no
	var all: Array = []
	for s in m.shelves():
		all.append_array(s["items"])
	assert_array(all).contains([_i(&"plate_harness")])
	assert_array(all).not_contains([_i(&"plate_scale")])


func test_names_follow_the_gun_family() -> void:
	var m := _model({})
	assert_str(m.name_of(_i(&"ember_part"))).is_equal(_cat.find(&"ember_part").label())
	var mech := ItemShopModel.new(_cat, _rules, _guides, VESPER, CombatFixtures.vesper().weapon.duplicate())
	mech.weapon.feed_kind = WeaponDef.FeedKind.MAGAZINE
	assert_str(mech.name_of(_i(&"ember_part"))).is_equal("Ember Chip")


func test_recommended_sections_have_choices_prices_and_next_part() -> void:
	var m := _model({}, 400)
	var s := m.sections()
	assert_array(s["starter"]).is_not_empty()
	assert_array(s["core"]).is_not_empty()
	assert_array(s["ammo"]).is_not_empty()
	var spike: Dictionary = {}
	for row in s["core"]:
		if (row["node"] as BuildNodeDef).id == &"core1":
			spike = row
	assert_int((spike["cards"] as Array).size()).is_equal(3)
	var c: Dictionary = spike["cards"][0]
	assert_int(int(c["goal"])).is_equal(_i(&"ember_heart"))
	assert_int(int(c["total"])).is_equal(2550)
	# With 400 Lumen the next part toward the Signature is a component that gives stats now.
	assert_int(_cat.at(int(c["next"])).tier).is_equal(ArmoryItemDef.Tier.COMPONENT)
	assert_int(int(c["next_cost"])).is_less_equal(400)
	assert_str(String(c["reason"])).is_not_empty()


func test_server_results_have_exact_texts() -> void:
	assert_str(ItemShopModel.result_key(HeroProgress.Result.INVENTORY_FULL)).is_equal("HUD_SHOP2_INVENTORY_FULL")
	assert_str(ItemShopModel.result_key(HeroProgress.Result.SIGNATURE_LIMIT)).is_equal("HUD_SHOP2_SIGNATURE_LIMIT")
	assert_str(ItemShopModel.result_key(HeroProgress.Result.UNDO_BLOCKED)).is_equal("HUD_SHOP2_R_UNDO_BLOCKED")
	assert_str(ItemShopModel.result_key(HeroProgress.Result.NO_FUNDS)).is_equal("HUD_SHOP_R_NO_FUNDS")
