extends GdUnitTestSuite
## E13 Armory rules without a world (weapons-and-mods.md §3.6.4, §4.7;
## wardlings-and-economy.md §7, §19): pad gate, funds, family, upgrade in place,
## swap auto-sell, 100% / 60% sell, mount modifiers on real weapon numbers,
## ammo effects, Squad Expansion cap, Med-Pack carry limit.

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


func _buy(p: HeroProgress, h: HeroBody, id: StringName, tier: int = 0) -> int:
	return Armory.buy(p, h.combat, _cat, _cat.index_of(id), tier, _r)


func test_buy_only_on_the_armory_pad_and_with_funds() -> void:
	var h := _hero(CombatFixtures.vesper())
	var away := _wallet(500, false)
	assert_int(_buy(away, h, &"ember_heart", 1)).is_equal(HeroProgress.Result.NOT_AT_ARMORY)
	assert_int(away.lumen).is_equal(500)
	var p := _wallet(350)
	assert_int(_buy(p, h, &"ember_heart", 1)).is_equal(HeroProgress.Result.NO_FUNDS)
	assert_int(p.lumen).is_equal(350)
	assert_int(p.mounts.size()).is_equal(0)
	p.lumen = 500
	assert_int(_buy(p, h, &"ember_heart", 1)).is_equal(HeroProgress.Result.OK)
	assert_int(p.lumen).is_equal(100)
	h.combat.dead = true
	p.lumen = 5000
	assert_int(_buy(p, h, &"med_pack")).is_equal(HeroProgress.Result.DEAD)


func test_crystals_fit_mana_guns_and_chips_fit_mechanical_guns() -> void:
	var vesper := _hero(CombatFixtures.vesper())
	var brannoc := _hero(CombatFixtures.brannoc())
	var p := _wallet(5000)
	assert_int(_buy(p, vesper, &"overclock", 1)).is_equal(HeroProgress.Result.WRONG_FAMILY)
	assert_int(_buy(p, brannoc, &"ember_heart", 1)).is_equal(HeroProgress.Result.WRONG_FAMILY)
	assert_int(_buy(p, brannoc, &"overclock", 1)).is_equal(HeroProgress.Result.OK)
	assert_int(p.lumen).is_equal(4600)


func test_core_mount_raises_weapon_damage_per_tier() -> void:
	var h := _hero(CombatFixtures.vesper())
	var wd := h.combat.weapon.def
	var base := DamageMath.hit_damage(wd, 10.0, false) * h.combat.weapon_damage_mult()
	assert_float(base).is_equal_approx(29.0, 1e-4)
	var p := _wallet(5000)
	assert_int(_buy(p, h, &"ember_heart", 1)).is_equal(HeroProgress.Result.OK)
	assert_float(DamageMath.hit_damage(wd, 10.0, false) * h.combat.weapon_damage_mult()).is_equal_approx(29.0 * 1.06, 1e-3)
	# Upgrade in place pays list(II) − list(I) = 500; III pays 900 (§4.7).
	assert_int(_buy(p, h, &"ember_heart")).is_equal(HeroProgress.Result.OK)
	assert_int(p.lumen).is_equal(5000 - 400 - 500)
	assert_int(_buy(p, h, &"ember_heart")).is_equal(HeroProgress.Result.OK)
	assert_int(p.lumen).is_equal(5000 - 1800)
	assert_int(p.mount(ArmoryItemDef.Socket.CORE).tier).is_equal(3)
	assert_int(p.mount(ArmoryItemDef.Socket.CORE).paid).is_equal(1800)
	assert_float(h.combat.weapon_damage_mult()).is_equal_approx(1.16, 1e-5)
	assert_int(_buy(p, h, &"ember_heart")).is_equal(HeroProgress.Result.MAXED)
	# M_dmg is capped at +0.25 (§4.1) by the stat limit.
	h.combat.stats.add_modifier(Modifier.make(StatCatalog.MOD_DAMAGE, Modifier.Op.ADD, 0.5, 99))
	assert_float(h.combat.weapon_damage_mult()).is_equal_approx(1.25, 1e-5)


func test_sell_refunds_100_percent_same_visit_and_60_percent_after() -> void:
	var h := _hero(CombatFixtures.vesper())
	var p := _wallet(1000)
	assert_int(_buy(p, h, &"ember_heart", 1)).is_equal(HeroProgress.Result.OK)
	assert_int(Armory.sell(p, h.combat, ArmoryItemDef.Socket.CORE, _r)).is_equal(HeroProgress.Result.OK)
	assert_int(p.lumen).is_equal(1000)  # undo
	assert_float(h.combat.weapon_damage_mult()).is_equal_approx(1.0, 1e-6)
	assert_int(_buy(p, h, &"ember_heart", 1)).is_equal(HeroProgress.Result.OK)
	p.end_visit()  # left the zone
	assert_int(Armory.sell(p, h.combat, ArmoryItemDef.Socket.CORE, _r)).is_equal(HeroProgress.Result.NOT_AT_ARMORY)
	p.at_armory = true  # next visit
	assert_int(Armory.sell(p, h.combat, ArmoryItemDef.Socket.CORE, _r)).is_equal(HeroProgress.Result.OK)
	assert_int(p.lumen).is_equal(600 + 240)
	assert_int(Armory.sell(p, h.combat, ArmoryItemDef.Socket.CORE, _r)).is_equal(HeroProgress.Result.NOT_OWNED)


func test_ammo_swap_auto_sells_and_effects_apply_to_damage() -> void:
	var h := _hero(CombatFixtures.brannoc())
	var p := _wallet(2000)
	assert_int(_buy(p, h, &"ammo_piercing")).is_equal(HeroProgress.Result.OK)
	assert_int(h.combat.ammo_type).is_equal(DamageMath.AMMO_PIERCING)
	p.end_visit()
	p.at_armory = true
	assert_int(_buy(p, h, &"ammo_sunder")).is_equal(HeroProgress.Result.OK)  # Piercing sells for 450
	assert_int(p.lumen).is_equal(2000 - 750 + 450 - 650)
	assert_int(h.combat.ammo_type).is_equal(DamageMath.AMMO_SUNDER)
	assert_float(DamageMath.ammo_mult(DamageMath.AMMO_SUNDER, DamageMath.TARGET_CONSTRUCT)).is_equal_approx(1.35, 1e-6)
	assert_float(DamageMath.ammo_mult(DamageMath.AMMO_SUNDER, DamageMath.TARGET_HERO)).is_equal_approx(0.9, 1e-6)
	assert_float(DamageMath.ammo_mult(DamageMath.AMMO_SUNDER, DamageMath.TARGET_UPLINK)).is_equal(1.0)
	assert_float(DamageMath.ammo_mult(DamageMath.AMMO_PIERCING, DamageMath.TARGET_CONSTRUCT, true)).is_equal_approx(1.25, 1e-6)
	# Piercing vs Brannoc (20% armor): 20% -> 12% (§3.7.1).
	var target := HealthComponent.new(1000.0, 0.20, 1)
	var plain := DamageInfo.make(100.0, 5, 0)
	assert_float(target.apply_damage(plain)).is_equal_approx(80.0, 1e-4)
	var pierce := DamageInfo.make(100.0, 5, 0)
	pierce.armor_pen = DamageMath.ammo_armor_pen(DamageMath.AMMO_PIERCING)
	assert_float(target.apply_damage(pierce)).is_equal_approx(88.0, 1e-4)


func test_frame_mounts_change_feed_numbers() -> void:
	var v := _hero(CombatFixtures.vesper())
	var p := _wallet(5000)
	assert_int(_buy(p, v, &"flux_coil", 3)).is_equal(HeroProgress.Result.OK)
	var feed := v.combat.weapon.feed
	assert_float(feed.regen_rate()).is_equal_approx(35.0 * 1.35, 1e-3)  # §4.6: 47.25
	assert_float(feed.regen_delay_s()).is_equal_approx(0.7, 1e-5)
	var b := _hero(CombatFixtures.brannoc())
	assert_int(_buy(p, b, &"quickload", 1)).is_equal(HeroProgress.Result.OK)
	assert_float(b.combat.weapon.feed.reload_time(0.45)).is_equal_approx(0.45 * 0.88, 1e-5)


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
	assert_int(_buy(p, h, &"ember_heart", 1)).is_equal(HeroProgress.Result.DISABLED)
	assert_int(p.lumen).is_equal(5000)
	assert_int(p.mounts.size()).is_equal(0)
