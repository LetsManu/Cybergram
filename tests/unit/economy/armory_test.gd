extends GdUnitTestSuite
## Armory rules without a world on the v22 catalog (items-and-armory.md §3.6;
## wardlings-and-economy.md §7, §19): pad gate, funds, Signature modifiers on
## real weapon numbers, Squad Expansion cap, Med-Pack carry limit, level
## scaling, disabled items. Recipe, slot and undo rules: item_shop_test.gd.

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


func _hero(def: HeroDef) -> HeroBody:
	var h := HeroBody.new()
	h.setup(MovementDef.new(), Vector3.ZERO, false)
	h.combat = HeroCombat.new(def, 0, HZ, 1)
	_bodies.append(h)
	return h


func _wallet(lumen: int, at_armory: bool = true) -> HeroProgress:
	var p := HeroProgress.new(1)
	p.lumen = lumen
	p.at_armory = at_armory
	return p


func _buy(p: HeroProgress, h: HeroBody, id: StringName) -> int:
	return ItemShop.buy(p, h.combat, _cat, _cat.index_of(id), _r)


func test_buy_only_on_the_armory_pad_and_with_funds() -> void:
	var h := _hero(CombatFixtures.vesper())
	var cost := RecipeMath.total(_cat, _cat.index_of(&"ember_heart"))
	var away := _wallet(cost + 500, false)
	assert_int(_buy(away, h, &"ember_heart")).is_equal(HeroProgress.Result.NOT_AT_ARMORY)
	assert_int(away.lumen).is_equal(cost + 500)
	var p := _wallet(cost - 1)
	assert_int(_buy(p, h, &"ember_heart")).is_equal(HeroProgress.Result.NO_FUNDS)
	assert_int(p.lumen).is_equal(cost - 1)
	assert_int(p.inv.slots.size()).is_equal(0)
	p.lumen = cost
	assert_int(_buy(p, h, &"ember_heart")).is_equal(HeroProgress.Result.OK)
	assert_int(p.lumen).is_equal(0)
	h.combat.dead = true
	p.lumen = 5000
	assert_int(_buy(p, h, &"med_pack")).is_equal(HeroProgress.Result.DEAD)


func test_a_signature_raises_weapon_damage_and_selling_it_restores_the_base() -> void:
	var h := _hero(CombatFixtures.vesper())
	var base := h.combat.weapon_damage_mult()
	var p := _wallet(8000)
	assert_int(_buy(p, h, &"ember_heart")).is_equal(HeroProgress.Result.OK)
	assert_float(h.combat.weapon_damage_mult()).is_greater(base)
	# M_dmg is capped at +0.25 (§4.1) by the stat limit.
	h.combat.stats.add_modifier(Modifier.make(StatCatalog.MOD_DAMAGE, Modifier.Op.ADD, 0.5, 99))
	assert_float(h.combat.weapon_damage_mult()).is_equal_approx(1.25, 1e-5)
	h.combat.stats.remove_by_source(99)
	var loc: int = p.inv.pool()[0]["loc"]
	assert_int(ItemShop.sell(p, h.combat, _cat, loc, _r)).is_equal(HeroProgress.Result.OK)
	assert_float(h.combat.weapon_damage_mult()).is_equal_approx(base, 1e-6)


func test_squad_expansion_raises_the_cap_and_needs_tier_one_first() -> void:
	var h := _hero(CombatFixtures.base_commander())
	var p := _wallet(5000)
	assert_int(MinionmancerHooks.capacity_bonus(h)).is_equal(0)
	assert_int(_buy(p, h, &"squad_expansion_2")).is_equal(HeroProgress.Result.REQUIRES)
	assert_int(_buy(p, h, &"squad_expansion_1")).is_equal(HeroProgress.Result.OK)
	assert_int(MinionmancerHooks.capacity_bonus(h)).is_equal(1)
	assert_int(_buy(p, h, &"squad_expansion_1")).is_equal(HeroProgress.Result.LIMIT)
	assert_int(_buy(p, h, &"squad_expansion_2")).is_equal(HeroProgress.Result.OK)
	assert_int(MinionmancerHooks.capacity_bonus(h)).is_equal(2)  # squad 3 -> 5 (§7)
	assert_int(p.lumen).is_equal(5000 - 800 - 1500)
	assert_int(_buy(p, h, &"amplifier_emitters")).is_equal(HeroProgress.Result.OK)
	assert_float(h.combat.stats.get_value(StatCatalog.WARDLING_DAMAGE_MULT)).is_equal_approx(1.2, 1e-5)
	assert_int(_buy(p, h, &"reinforced_cores_1")).is_equal(HeroProgress.Result.OK)
	assert_int(_buy(p, h, &"reinforced_cores_2")).is_equal(HeroProgress.Result.OK)
	assert_float(h.combat.stats.get_value(StatCatalog.WARDLING_HP_MULT)).is_equal_approx(1.4, 1e-5)


func test_med_pack_carry_limit() -> void:
	var h := _hero(CombatFixtures.vesper())
	var p := _wallet(1000)
	for i in 3:
		assert_int(_buy(p, h, &"med_pack")).is_equal(HeroProgress.Result.OK)
	assert_int(_buy(p, h, &"med_pack")).is_equal(HeroProgress.Result.LIMIT)
	assert_int(p.medpacks).is_equal(3)
	assert_int(p.lumen).is_equal(700)


func test_level_scaling_goes_through_the_stat_block() -> void:
	var h := _hero(CombatFixtures.vesper())
	var c := h.combat
	c.apply_level(5)
	assert_float(c.stats.get_value(StatCatalog.MAX_HP)).is_equal_approx(250.0 * 1.16, 1e-3)
	assert_float(c.health.max_hp).is_equal_approx(290.0, 1e-3)
	assert_float(c.health.hp).is_equal_approx(290.0, 1e-3)
	assert_float(c.weapon_damage_mult()).is_equal_approx(1.10, 1e-5)
	assert_float(c.skill_power()).is_equal_approx(1.08, 1e-5)
	c.apply_level(15)  # heroes.md §3.3: HP ×1.56, weapon ×1.35, skill ×1.28
	assert_float(c.health.max_hp).is_equal_approx(390.0, 1e-3)
	assert_float(c.weapon_damage_mult()).is_equal_approx(1.35, 1e-5)
	assert_float(c.skill_power()).is_equal_approx(1.28, 1e-5)
	c.reset_for_respawn()
	assert_float(c.health.hp).is_equal_approx(390.0, 1e-3)


func test_disabled_item_is_refused_and_changes_nothing() -> void:
	_cat = _cat.duplicate(true) as ArmoryCatalogDef
	_cat.find(&"ember_heart").disabled = true
	var h := _hero(CombatFixtures.vesper())
	var p := _wallet(5000)
	assert_int(_buy(p, h, &"ember_heart")).is_equal(HeroProgress.Result.DISABLED)
	assert_int(p.lumen).is_equal(5000)
	assert_int(p.inv.pool().size()).is_equal(0)
