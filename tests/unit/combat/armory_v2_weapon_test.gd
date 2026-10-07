extends GdUnitTestSuite
## Armory v2 handling and feeds (items-and-armory.md §3.5, §3.7, §4.3;
## weapons-and-mods.md §3.7.1 Disrupted, §3.7.2 Overcharged, §5): fire rate
## combined with skill buffs, spread, capacity, Overcharged costs, Disrupted,
## Siphon mana, Chill slow inside the shared cap, Scorched.

const HZ: int = 60


func _stats(pairs: Dictionary) -> StatBlock:
	var b := StatCatalog.new_hero_block(6.0, 250.0)
	for k in pairs:
		b.add_modifier(Modifier.make(int(k), Modifier.Op.ADD, float(pairs[k]), 1))
	return b


func _fire_ticks(w: WeaponSim, ticks: int) -> int:
	var cmd := InputCommand.new()
	cmd.buttons = InputCommand.BTN_FIRE
	var n := 0
	for t in ticks:
		if w.step(cmd, t, true):
			n += 1
	return n


func test_item_fire_rate_combines_with_skill_rate() -> void:
	var gun := CombatFixtures.auto_gun(10.0)
	var base := WeaponSim.new(gun, HZ, 1)
	var items := WeaponSim.new(gun, HZ, 1)
	items.apply_item_stats(_stats({StatCatalog.FIRE_RATE_BONUS: 0.30}))  # capped at +0.15
	assert_float(items.item_rate_mult).is_equal_approx(1.15, 1e-6)
	items.rate_mult = 1.25  # Combat Stim keeps working on top
	assert_float(items.total_rate_mult()).is_equal_approx(1.4375, 1e-6)
	assert_int(_fire_ticks(base, 600)).is_equal(100)
	assert_int(_fire_ticks(items, 600)).is_between(142, 145)


func test_defaults_leave_weapon_unchanged() -> void:
	var w := WeaponSim.new(CombatFixtures.auto_gun(10.0), HZ, 1)
	w.apply_item_stats(StatCatalog.new_hero_block(6.0))
	assert_float(w.item_rate_mult).is_equal(1.0)
	assert_float(w.spread_mult).is_equal(1.0)


func test_spread_mult_scales_cone() -> void:
	var gun := CombatFixtures.auto_gun(10.0)
	gun.spread_base_deg = 0.4
	gun.spread_bloom_deg = 0.12
	gun.spread_max_deg = 2.2
	var w := WeaponSim.new(gun, HZ, 1)
	w.apply_item_stats(_stats({StatCatalog.SPREAD_MULT: -0.5}))
	_fire_ticks(w, 600)
	assert_float(w.spread_deg).is_equal_approx(1.1, 1e-4)
	assert_float(w.shot_spread_deg).is_less_equal(1.1 + 1e-4)


func test_mana_capacity_and_overcharged_cost() -> void:
	var gun := CombatFixtures.vesper().weapon  # pool 100, 6 / shot
	var f := ManaPoolFeed.new(gun, HZ)
	f.stats = _stats({StatCatalog.CAPACITY_MULT: 0.45})
	f.refill()
	assert_int(f.capacity()).is_equal(145)
	f.cost_mult = 1.2
	f.consume(0)
	assert_float(f.current()).is_equal_approx(145.0 - 7.2, 1e-4)
	# Selling the item clamps the pool (§5).
	f.stats = StatCatalog.new_hero_block(6.0)
	f.step(1)
	assert_float(f.current()).is_equal(100.0)


func test_magazine_capacity_round_down_min_plus_one() -> void:
	var f := MagazineFeed.new(CombatFixtures.rifle_mag(), HZ)
	f.stats = _stats({StatCatalog.CAPACITY_MULT: 0.15})
	f.refill()
	assert_int(f.capacity()).is_equal(34)  # floor(30 × 1.15)
	assert_int(f.reserve_count()).is_equal(172)
	var maw := WeaponDef.new()
	maw.feed_kind = WeaponDef.FeedKind.MAGAZINE
	maw.magazine = 6
	maw.reserve = 30
	var m := MagazineFeed.new(maw, HZ)
	m.stats = _stats({StatCatalog.CAPACITY_MULT: 0.15})
	assert_int(m.max_magazine()).is_equal(7)  # floor(6.9) = 6 -> min +1


func test_overcharged_reload_and_shock_disrupted_mech() -> void:
	var f := MagazineFeed.new(CombatFixtures.rifle_mag(), HZ)
	f.reload_mult = 1.15
	f.rounds = 10
	f.request_reload(0)
	assert_int(f.reload_end_tick).is_equal(ceili(1.6 * 1.15 * HZ - 1e-6))
	var before := f.reload_end_tick
	f.disrupt(5, f.ticks(1.0), f.ticks(0.5))  # current reload +0.5 s
	assert_int(f.reload_end_tick).is_equal(before + 30)
	var g := MagazineFeed.new(CombatFixtures.rifle_mag(), HZ)
	g.rounds = 10
	g.disrupt(0, g.ticks(1.0), g.ticks(0.5))  # next reload within the window
	g.request_reload(10)
	assert_int(g.reload_end_tick).is_equal(10 + g.ticks(1.6) + 30)


func test_shock_disrupted_mana_and_siphon_mana() -> void:
	var f := ManaPoolFeed.new(CombatFixtures.vesper().weapon, HZ)
	f.consume(0)
	f.disrupt(10, f.ticks(1.0), 0)
	assert_int(f.regen_resume_tick).is_equal(10 + f.ticks(1.0))  # delay 1.0 restarted
	assert_float(f.add_mana(3.0)).is_equal_approx(3.0, 1e-6)
	assert_float(f.add_mana(50.0)).is_equal_approx(3.0, 1e-6)  # no overfill
	assert_float(f.current()).is_equal(100.0)


func test_chill_slow_shares_the_40_percent_cap_and_scorched_cuts_heals() -> void:
	var stats := StatCatalog.new_hero_block(6.0)
	var health := HealthComponent.new(250.0, 0.0, 1)
	var st := StatusComponent.new(stats, health, AbilityRulesDef.new(), HZ, 1)
	st.apply(StatusComponent.Kind.SLOW, 120, 0.30, 77, 0)
	st.set_chill_slow(0.25, 0)
	assert_float(st.slow_total()).is_equal_approx(0.40, 1e-6)
	assert_float(stats.get_value(StatCatalog.MOVE_SPEED)).is_equal_approx(3.6, 1e-4)
	st.set_chill_slow(0.0, 1)
	assert_float(st.slow_total()).is_equal_approx(0.30, 1e-6)
	health.hp = 100.0
	st.set_scorched(0.30, 1)
	assert_float(health.heal(10.0)).is_equal_approx(7.0, 1e-4)
	st.set_scorched(0.0, 2)
	assert_float(health.heal(10.0)).is_equal_approx(10.0, 1e-4)


func test_premitigated_burn_skips_armor() -> void:
	var hc := HealthComponent.new(250.0, 0.20, 1)
	var info := DamageInfo.make(10.0, 3, 0, DamageInfo.FLAG_PREMITIGATED | DamageInfo.FLAG_AMMO_EFFECT)
	assert_float(hc.apply_damage(info)).is_equal_approx(10.0, 1e-6)
