extends GdUnitTestSuite
## W11-M1 Healing reduction status (StatusComponent HEAL_CUT -> HealthComponent.heal_mult)
## and the Bleed entry bookkeeping.

const HZ: int = 30


func _status() -> StatusComponent:
	var health := HealthComponent.new(250.0, 0.0, 0)
	var stats := StatCatalog.new_hero_block(6.0)
	return StatusComponent.new(stats, health, AbilityRulesDef.new(), HZ, 1)


func test_heal_cut_scales_heals_then_expires() -> void:
	var st := _status()
	st.health.hp = 100.0
	st.apply(StatusComponent.Kind.HEAL_CUT, 3 * HZ, 0.3, 11, 0)
	assert_float(st.health.heal(100.0)).is_equal_approx(70.0, 1e-3)
	st.step(3 * HZ)
	assert_float(st.health.heal(10.0)).is_equal_approx(10.0, 1e-3)


func test_heal_cut_sources_add_and_cap_at_full() -> void:
	var st := _status()
	st.health.hp = 10.0
	st.apply(StatusComponent.Kind.HEAL_CUT, 90, 0.6, 1, 0)
	st.apply(StatusComponent.Kind.HEAL_CUT, 90, 0.6, 2, 0)
	assert_float(st.health.heal(50.0)).is_equal(0.0)


func test_bleed_entry_keeps_attacker_and_refreshes_per_source() -> void:
	var st := _status()
	st.apply(StatusComponent.Kind.BLEED, 90, 10.0, 5, 0, 42)
	st.apply(StatusComponent.Kind.BLEED, 90, 12.0, 5, 30, 42)
	assert_int(st.entries.size()).is_equal(1)
	assert_float(st.entries[0].magnitude).is_equal(12.0)
	assert_int(st.entries[0].attacker_id).is_equal(42)
	assert_int(st.ticks_left(StatusComponent.Kind.BLEED, 30)).is_equal(90)


func test_mitigated_tallies_only_status_damage_reduction() -> void:
	var st := _status()
	st.health.stats = st.stats
	var before := st.health.mitigated
	st.health.apply_damage(DamageInfo.make(100.0, 9, 1, 0, DamageInfo.Type.SKILL))
	assert_float(st.health.mitigated - before).is_equal(0.0)  # no DR: nothing absorbed
	st.apply(StatusComponent.Kind.DR, 90, 0.4, 3, 0)
	var m := st.health.mitigated
	var hp := st.health.hp
	st.health.apply_damage(DamageInfo.make(100.0, 9, 1, 0, DamageInfo.Type.SKILL))
	assert_float(hp - st.health.hp).is_equal_approx(60.0, 1e-3)
	assert_float(st.health.mitigated - m).is_equal_approx(40.0, 1e-3)
