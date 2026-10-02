extends GdUnitTestSuite
## The M1 kits' data against design/gdd/heroes.md §4.1 (Vesper Loom) and §4.5
## (Brannoc): Unlock / Rank 1 numbers, slots and gates, the passives, and that
## the authored Boost / Ult-rank nodes (E15) produce the GDD's next numbers
## purely as Modifiers on the skill's StatBlock.


func _skill(def: HeroDef, slot: int) -> SkillInstance:
	return SkillInstance.new(def.skills[slot], slot)


func _assert_params(s: SkillInstance, expected: Dictionary) -> void:
	for k in expected:
		assert_float(s.param(k)).override_failure_message("%s.%s" % [s.def.id, k]).is_equal_approx(float(expected[k]), 1e-4)


func _learn(s: SkillInstance, kind: int, level: int) -> void:
	for n in s.def.nodes:
		if n.kind == kind and n.required_level == level:
			s.learn(n)
			return
	fail("no node %d at L%d on %s" % [kind, level, s.def.id])


func test_vesper_kit_unlock_numbers() -> void:
	var v := CombatFixtures.vesper()
	assert_int(v.skills.size()).is_equal(4)
	var thread := _skill(v, 0)
	assert_str(String(thread.def.id)).is_equal("skill_vesper_marionette_thread")
	assert_int(thread.def.targeting).is_equal(SkillDef.TargetMode.PROJECTILE)
	_assert_params(thread, {&"damage": 40, &"range": 30, &"speed": 60, &"secondary_duration": 4, &"cooldown": 10})
	var beacon := _skill(v, 1)
	_assert_params(beacon, {&"heal_per_s": 15, &"dr": 0.2, &"radius": 10, &"hp": 200, &"duration": 30,
		&"cooldown": 18, &"range": 20})
	assert_bool(beacon.def.recast_effects.is_empty()).is_false()  # double-tap squad order
	var step := _skill(v, 2)
	assert_int(step.def.targeting).is_equal(SkillDef.TargetMode.ALLY_WARDLING)
	_assert_params(step, {&"range": 30, &"cooldown": 14})
	var rw := _skill(v, 3)
	assert_bool(rw.def.ultimate).is_true()
	assert_int(rw.def.required_level).is_equal(6)
	assert_bool(rw.def.interruptible).is_true()
	_assert_params(rw, {&"cast_time": 0.8, &"radius": 18, &"duration": 12, &"secondary_duration": 6, &"cooldown": 120})


func test_vesper_boost_and_ult_rank_nodes_reach_the_gdd_numbers() -> void:
	var v := CombatFixtures.vesper()
	var thread := _skill(v, 0)
	_learn(thread, SkillNodeDef.Kind.BOOST, 3)
	_assert_params(thread, {&"damage": 60, &"cooldown": 8})
	var beacon := _skill(v, 1)
	_learn(beacon, SkillNodeDef.Kind.BOOST, 3)
	_assert_params(beacon, {&"heal_per_s": 22, &"hp": 300})
	var step := _skill(v, 2)
	_learn(step, SkillNodeDef.Kind.BOOST, 3)
	_assert_params(step, {&"range": 40, &"cooldown": 11})
	var rw := _skill(v, 3)
	_learn(rw, SkillNodeDef.Kind.ULT_RANK, 6)
	assert_int(rw.rank).is_equal(1)
	_learn(rw, SkillNodeDef.Kind.ULT_RANK, 10)
	_assert_params(rw, {&"radius": 20, &"duration": 15, &"secondary_duration": 8, &"cooldown": 105})
	_learn(rw, SkillNodeDef.Kind.ULT_RANK, 14)
	_assert_params(rw, {&"radius": 22, &"duration": 18, &"secondary_duration": 10, &"cooldown": 90})
	assert_int(rw.rank).is_equal(3)


func test_vesper_conductor_passive() -> void:
	var v := CombatFixtures.vesper()
	var c := HeroCombat.new(v, 0, 30, 1)
	assert_float(c.stats.get_value(StatCatalog.SQUAD_CAPACITY_BONUS)).is_equal(2.0)
	assert_float(c.stats.get_value(StatCatalog.WARDLING_HP_MULT)).is_equal_approx(1.15, 1e-5)
	assert_float(c.stats.get_value(StatCatalog.WARDLING_AURA_DAMAGE)).is_equal_approx(0.10, 1e-5)
	assert_float(v.wardling_aura_radius_m).is_equal(15.0)
	assert_float(v.conduct_radius_m).is_equal(25.0)
	assert_float(c.skill_power()).is_equal(1.0)  # level 1


func test_brannoc_kit_unlock_numbers() -> void:
	var b := CombatFixtures.brannoc()
	assert_int(b.max_hp).is_equal(550)
	assert_float(b.armor).is_equal_approx(0.2, 1e-6)
	var wall := _skill(b, 0)
	assert_bool(wall.def.cooldown_on_end).is_true()
	_assert_params(wall, {&"hp": 1200, &"duration": 10, &"cooldown": 18, &"width": 6, &"height": 3, &"range": 20})
	var ram := _skill(b, 1)
	assert_int(ram.def.targeting).is_equal(SkillDef.TargetMode.DIRECTION)
	_assert_params(ram, {&"distance": 12, &"duration": 0.8, &"damage": 60, &"bonus_damage": 60, &"stun": 1.0,
		&"cooldown": 14, &"cast_time": 0.2})
	var fort := _skill(b, 2)
	assert_bool(fort.def.cooldown_on_end).is_true()
	_assert_params(fort, {&"dr": 0.4, &"duration": 3, &"slow": 0.25, &"cooldown": 20})
	var quake := _skill(b, 3)
	assert_bool(quake.def.ultimate).is_true()
	assert_int(quake.def.required_level).is_equal(6)
	_assert_params(quake, {&"range": 25, &"radius": 8, &"damage": 120, &"stun": 1.2, &"secondary_duration": 6,
		&"dr": 0.25, &"cooldown": 110, &"leap_time": 0.6})


func test_brannoc_boost_and_ult_rank_nodes_reach_the_gdd_numbers() -> void:
	var b := CombatFixtures.brannoc()
	var wall := _skill(b, 0)
	_learn(wall, SkillNodeDef.Kind.BOOST, 3)
	_assert_params(wall, {&"hp": 1500, &"duration": 12})
	var ram := _skill(b, 1)
	_learn(ram, SkillNodeDef.Kind.BOOST, 3)
	_assert_params(ram, {&"damage": 80, &"bonus_damage": 80, &"cooldown": 12})
	var fort := _skill(b, 2)
	_learn(fort, SkillNodeDef.Kind.BOOST, 3)
	_assert_params(fort, {&"dr": 0.5})
	var quake := _skill(b, 3)
	_learn(quake, SkillNodeDef.Kind.ULT_RANK, 10)
	_assert_params(quake, {&"damage": 150, &"stun": 1.4, &"secondary_duration": 7, &"cooldown": 100})
	_learn(quake, SkillNodeDef.Kind.ULT_RANK, 14)
	_assert_params(quake, {&"damage": 180, &"stun": 1.6, &"secondary_duration": 8, &"cooldown": 90})


func test_brannoc_anchor_passive_is_zone_scoped() -> void:
	var b := CombatFixtures.brannoc()
	assert_int(b.passive_modifiers.size()).is_equal(0)
	var dr := 0.0
	var kb := 0.0
	for m in b.zone_passive_modifiers:
		if m.stat == &"damage_reduction":
			dr = m.value
		elif m.stat == &"knockback_immune":
			kb = m.value
	assert_float(dr).is_equal_approx(0.15, 1e-6)
	assert_float(kb).is_equal(1.0)
	# Not applied outside a zone.
	var c := HeroCombat.new(b, 0, 30, 1)
	assert_float(c.stats.get_value(StatCatalog.DAMAGE_REDUCTION)).is_equal(0.0)
