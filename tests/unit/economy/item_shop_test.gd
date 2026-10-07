extends GdUnitTestSuite
## Armory v2 server rules (items-and-armory.md §3.2–3.6, §4.1, §4.2, §4.4) on
## the v22 catalog: recipe prices with owned parts (the GDD worked examples),
## open-slot limit, Signature limit, one copy per id and spares, socket swap,
## Chamber rules, sell values, per-visit undo (per item and last) and
## atomic refusals. Stats: active items only, Mana / Mech Feed stats, item HP.

const HZ: int = 30

var _cat: ArmoryCatalogDef
var _r := EconomyRulesDef.new()
var _bodies: Array[HeroBody] = []


func before_test() -> void:
	_cat = load(ArmoryCatalogDef.DEFAULT_PATH) as ArmoryCatalogDef


func after_test() -> void:
	for b in _bodies:
		b.free()
	_bodies.clear()


func _combat(def: HeroDef = null) -> HeroCombat:
	var h := HeroBody.new()
	h.setup(MovementDef.new(), Vector3.ZERO, false)
	h.combat = HeroCombat.new(def if def != null else CombatFixtures.vesper(), 0, HZ, 1)
	_bodies.append(h)
	return h.combat


func _wallet(lumen: int) -> HeroProgress:
	var p := HeroProgress.new(1)
	p.lumen = lumen
	p.at_armory = true
	return p


func _i(id: StringName) -> int:
	return _cat.index_of(id)


func _buy(p: HeroProgress, c: HeroCombat, id: StringName) -> int:
	return ItemShop.buy(p, c, _cat, _i(id), _r)


func test_recipe_totals_and_the_gdd_remaining_cost_examples() -> void:
	assert_int(RecipeMath.total(_cat, _i(&"ember_heart"))).is_equal(2550)
	assert_int(RecipeMath.total(_cat, _i(&"bastion_plate"))).is_equal(2400)  # Example 2
	assert_int(RecipeMath.total(_cat, _i(&"breaker_sigil"))).is_equal(2400)  # Example 3
	var p := _wallet(10000)
	var c := _combat()
	assert_int(_buy(p, c, &"ember_facet")).is_equal(HeroProgress.Result.OK)  # 1,000 from nothing
	assert_int(p.lumen).is_equal(9000)
	assert_int(p.inv.index_at(ItemInventory.LOC_CORE)).is_equal(_i(&"ember_facet"))
	# Example 1: Ember Facet in Core, nothing loose -> 1,550; with a loose Ember Shard -> 1,150.
	assert_int(ItemShop.price_of(p, _cat, _i(&"ember_heart"))).is_equal(1550)
	_buy(p, c, &"ember_part")
	assert_int(ItemShop.price_of(p, _cat, _i(&"ember_heart"))).is_equal(1150)
	var before := p.lumen
	assert_int(_buy(p, c, &"ember_heart")).is_equal(HeroProgress.Result.OK)
	assert_int(before - p.lumen).is_equal(1150)
	assert_int(p.inv.index_at(ItemInventory.LOC_CORE)).is_equal(_i(&"ember_heart"))
	assert_int(p.inv.slots.size()).is_equal(0)  # the loose Ember Shard was used up


func test_open_slots_fill_up_and_a_combine_frees_them() -> void:
	var p := _wallet(20000)
	var c := _combat()
	for id in [&"plate_scale", &"vital_cell", &"null_thread", &"cadence_bead", &"stride_clip", &"lens_part"]:
		assert_int(_buy(p, c, id)).is_equal(HeroProgress.Result.OK)
	var lumen := p.lumen
	assert_int(_buy(p, c, &"tempo_part")).is_equal(HeroProgress.Result.INVENTORY_FULL)
	assert_int(p.lumen).is_equal(lumen)  # refused: nothing changed
	# §4.2 example: 6 - 2 + 1 = 5.
	assert_int(_buy(p, c, &"plate_harness")).is_equal(HeroProgress.Result.OK)
	assert_int(p.inv.slots.size()).is_equal(5)
	assert_int(lumen - p.lumen).is_equal(300)  # only the combine was missing
	# A weapon Assembly goes to its socket and frees the slot of its part.
	assert_int(_buy(p, c, &"longsight_ring")).is_equal(HeroProgress.Result.OK)
	assert_int(p.inv.slots.size()).is_equal(4)
	assert_int(p.inv.index_at(ItemInventory.LOC_BARREL)).is_equal(_i(&"longsight_ring"))


func test_signature_limit_and_one_copy_per_id() -> void:
	var p := _wallet(20000)
	var c := _combat()
	assert_int(_buy(p, c, &"ember_heart")).is_equal(HeroProgress.Result.OK)
	assert_int(_buy(p, c, &"bastion_plate")).is_equal(HeroProgress.Result.OK)
	assert_int(_buy(p, c, &"null_veil")).is_equal(HeroProgress.Result.SIGNATURE_LIMIT)
	assert_int(_buy(p, c, &"plate_harness")).is_equal(HeroProgress.Result.OK)
	assert_int(_buy(p, c, &"plate_harness")).is_equal(HeroProgress.Result.ALREADY_OWNED)
	assert_int(_buy(p, c, &"bastion_plate")).is_equal(HeroProgress.Result.ALREADY_OWNED)
	# Components may be bought again as spares; only the first copy gives stats.
	assert_int(_buy(p, c, &"vital_cell")).is_equal(HeroProgress.Result.OK)
	assert_int(_buy(p, c, &"vital_cell")).is_equal(HeroProgress.Result.OK)
	assert_int(p.inv.active_indices().count(_i(&"vital_cell"))).is_equal(1)


func test_stats_follow_active_items_and_item_hp_raises_current_hp() -> void:
	var p := _wallet(20000)
	var c := _combat()
	var hp0 := c.health.max_hp
	_buy(p, c, &"vital_cell")
	_buy(p, c, &"vital_cell")  # spare: no extra HP
	assert_float(c.health.max_hp).is_equal_approx(hp0 + 25.0, 0.01)
	assert_float(c.health.hp).is_equal_approx(hp0 + 25.0, 0.01)
	_buy(p, c, &"vital_core")  # uses both cells: +75
	assert_float(c.health.max_hp).is_equal_approx(hp0 + 75.0, 0.01)
	_buy(p, c, &"ember_part")
	assert_float(c.stats.get_value(StatCatalog.MOD_DAMAGE)).is_equal_approx(0.05, 0.001)
	_buy(p, c, &"ember_facet")  # the shard becomes part of the facet
	assert_float(c.stats.get_value(StatCatalog.MOD_DAMAGE)).is_equal_approx(0.10, 0.001)
	assert_float(c.stats.get_value(StatCatalog.FALLOFF_RANGE)).is_equal_approx(1.05, 0.001)


func test_feed_items_use_family_stats() -> void:
	var p := _wallet(5000)
	var mana := _combat(CombatFixtures.vesper())
	_buy(p, mana, &"feed_part")
	assert_float(mana.stats.get_value(StatCatalog.MANA_REGEN)).is_equal_approx(1.10, 0.001)
	var q := _wallet(5000)
	var mech := _combat(CombatFixtures.brannoc())
	_buy(q, mech, &"feed_part")
	assert_float(mech.stats.get_value(StatCatalog.RELOAD_TIME)).is_equal_approx(0.92, 0.001)
	assert_float(mech.stats.get_value(StatCatalog.MANA_REGEN)).is_equal_approx(1.0, 0.001)


func test_socket_swap_sells_the_held_part() -> void:
	var p := _wallet(10000)
	var c := _combat()
	_buy(p, c, &"ember_facet")
	var lumen := p.lumen
	# Pulse Facet does not build from Ember Facet: the facet is sold (60% of 1,000).
	assert_int(_buy(p, c, &"pulse_facet")).is_equal(HeroProgress.Result.OK)
	assert_int(lumen - p.lumen).is_equal(900 - 600)
	assert_int(p.inv.index_at(ItemInventory.LOC_CORE)).is_equal(_i(&"pulse_facet"))


func test_sell_values_are_sixty_percent_of_the_recipe_total() -> void:
	assert_int(RecipeMath.sell_value(_cat, _i(&"ember_heart"), _r)).is_equal(1530)
	assert_int(RecipeMath.sell_value(_cat, _i(&"ember_part"), _r)).is_equal(240)
	var p := _wallet(5000)
	var c := _combat()
	_buy(p, c, &"ember_part")
	p.inv.end_visit()
	var lumen := p.lumen
	assert_int(ItemShop.sell(p, c, _cat, ItemInventory.LOC_SLOT, _r)).is_equal(HeroProgress.Result.OK)
	assert_int(p.lumen - lumen).is_equal(240)
	assert_float(c.stats.get_value(StatCatalog.MOD_DAMAGE)).is_equal_approx(0.0, 0.001)
	assert_int(ItemShop.sell(p, c, _cat, ItemInventory.LOC_SLOT, _r)).is_equal(HeroProgress.Result.NOT_OWNED)


func test_undo_restores_parts_and_lumen_and_respects_later_purchases() -> void:
	var p := _wallet(10000)
	var c := _combat()
	_buy(p, c, &"ember_part")
	_buy(p, c, &"lens_part")
	var lumen := p.lumen
	_buy(p, c, &"ember_facet")  # uses both parts: pays only the 300 combine
	assert_int(lumen - p.lumen).is_equal(300)
	_buy(p, c, &"tempo_part")
	# The Ember Shard was used up by Ember Facet: it is gone, nothing to undo there.
	assert_int(ItemShop.undo_at(p, c, _cat, ItemInventory.LOC_CORE, _r)).is_equal(HeroProgress.Result.OK)
	assert_int(p.lumen).is_equal(lumen - 350)  # the facet's 300 back, the tempo still bought
	assert_int(p.inv.index_at(ItemInventory.LOC_CORE)).is_equal(-1)
	assert_int(p.inv.slots.size()).is_equal(3)  # ember, lens back + tempo
	# Undo last: the Tempo Shard.
	assert_int(ItemShop.undo_last(p, c, _cat, _r)).is_equal(HeroProgress.Result.OK)
	assert_int(p.inv.slots.size()).is_equal(2)
	assert_int(p.lumen).is_equal(lumen)


func test_an_item_a_later_buy_used_up_cannot_be_undone_alone() -> void:
	var p := _wallet(10000)
	var c := _combat()
	_buy(p, c, &"ember_facet")
	_buy(p, c, &"ember_heart")  # uses the facet
	# The facet is no longer at any location; the Heart's undo restores it.
	assert_int(ItemShop.undo_at(p, c, _cat, ItemInventory.LOC_CORE, _r)).is_equal(HeroProgress.Result.OK)
	assert_int(p.inv.index_at(ItemInventory.LOC_CORE)).is_equal(_i(&"ember_facet"))
	# A part used by a later buy in the slots: the earlier buy is blocked.
	var q := _wallet(10000)
	_buy(q, c, &"vital_cell")
	_buy(q, c, &"plate_scale")
	_buy(q, c, &"plate_harness")
	var k := 0  # first transaction placed the cell, which the harness used up
	assert_bool(q.inv.is_blocked(k)).is_true()


func test_chamber_rules() -> void:
	var p := _wallet(10000)
	var c := _combat()
	assert_int(_buy(p, c, &"mod_lingering")).is_equal(HeroProgress.Result.REQUIRES)
	assert_int(_buy(p, c, &"ammo_incendiary")).is_equal(HeroProgress.Result.OK)
	assert_int(c.ammo_type).is_equal(_cat.at(_i(&"ammo_incendiary")).ammo_type)
	assert_int(_buy(p, c, &"mod_lingering")).is_equal(HeroProgress.Result.OK)
	assert_int(_buy(p, c, &"ammo_incendiary")).is_equal(HeroProgress.Result.ALREADY_OWNED)
	# Piercing does not take Lingering: the swap sells both (60% each).
	var lumen := p.lumen
	assert_int(_buy(p, c, &"ammo_piercing")).is_equal(HeroProgress.Result.OK)
	assert_int(p.lumen - lumen).is_equal(480 + 180 - 750)
	assert_int(p.inv.index_at(ItemInventory.LOC_MOD)).is_equal(-1)
	assert_int(c.ammo_mod).is_equal(0)
	assert_int(_buy(p, c, &"mod_lingering")).is_equal(HeroProgress.Result.INCOMPATIBLE)
	# Undo last brings the Incendiary + Lingering Chamber back.
	assert_int(ItemShop.undo_last(p, c, _cat, _r)).is_equal(HeroProgress.Result.OK)
	assert_int(p.inv.index_at(ItemInventory.LOC_MOD)).is_equal(_i(&"mod_lingering"))
	assert_int(p.lumen).is_equal(lumen)


func test_refusals_change_nothing_and_rows_still_work() -> void:
	var p := _wallet(500)
	var c := _combat()
	assert_int(_buy(p, c, &"ember_facet")).is_equal(HeroProgress.Result.NO_FUNDS)
	assert_int(p.lumen).is_equal(500)
	assert_int(p.inv.pool().size()).is_equal(0)
	p.at_armory = false
	assert_int(_buy(p, c, &"ember_part")).is_equal(HeroProgress.Result.NOT_AT_ARMORY)
	p.at_armory = true
	assert_int(ItemShop.buy(p, c, _cat, 999, _r)).is_equal(HeroProgress.Result.UNKNOWN_ITEM)
	assert_int(_buy(p, c, &"med_pack")).is_equal(HeroProgress.Result.OK)
	assert_int(p.medpacks).is_equal(1)
	assert_int(ItemShop.undo_row(p, c, _cat, _i(&"med_pack"), _r)).is_equal(HeroProgress.Result.OK)
	assert_int(p.medpacks).is_equal(0)
	assert_int(p.lumen).is_equal(500)
	p.end_visit()
	p.at_armory = true
	_buy(p, c, &"ember_part")
	p.end_visit()
	p.at_armory = true
	assert_int(ItemShop.undo_last(p, c, _cat, _r)).is_equal(HeroProgress.Result.NOT_OWNED)  # visit over
