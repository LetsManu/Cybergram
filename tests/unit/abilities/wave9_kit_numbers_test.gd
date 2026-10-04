extends GdUnitTestSuite
## Wave-9 kits' data against design/gdd/heroes.md §4.2 (Sable), §4.4 (Ryker
## Vance) and §4.6 (Liora Vale): slots, Unlock / Rank 1 numbers, the authored
## Boost / Ult-rank nodes (Modifiers only), the passives and that the heroes are
## ContentDB entries with models. Forks and Masteries are not in the slice tree.

const RYKER := "res://assets/data/heroes/hero_ryker_vance.tres"
const SABLE := "res://assets/data/heroes/hero_sable.tres"
const LIORA := "res://assets/data/heroes/hero_liora_vale.tres"


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


func test_base_stats_and_weapons() -> void:
	var r := load(RYKER) as HeroDef
	var s := load(SABLE) as HeroDef
	var l := load(LIORA) as HeroDef
	assert_int(r.max_hp).is_equal(250)
	assert_float(r.move_speed).is_equal(6.2)
	assert_int(s.max_hp).is_equal(225)
	assert_float(s.move_speed).is_equal(6.6)
	assert_int(l.max_hp).is_equal(225)
	assert_float(l.move_speed).is_equal(6.0)
	for d in [r, s, l]:
		assert_int((d as HeroDef).skills.size()).is_equal(4)
		assert_bool((d as HeroDef).skills[3].ultimate).is_true()
		assert_int((d as HeroDef).skills[3].required_level).is_equal(6)
	# weapons-and-mods.md §3.3 body DPS: Breakline 180, Whisperfang 188, Halo 95.
	assert_float(r.weapon.damage * r.weapon.fire_rate).is_equal_approx(180.0, 1.0)
	assert_float(s.weapon.damage * s.weapon.fire_rate).is_equal_approx(188.0, 1.0)
	assert_float(l.weapon.damage * l.weapon.fire_rate).is_equal_approx(95.0, 1.0)
	assert_int(r.weapon.feed_kind).is_equal(WeaponDef.FeedKind.MAGAZINE)
	assert_int(r.weapon.magazine).is_equal(30)
	assert_int(r.weapon.reserve).is_equal(150)
	assert_int(s.weapon.feed_kind).is_equal(WeaponDef.FeedKind.MANA)
	assert_float(s.weapon.mana_regen).is_equal(45.0)
	assert_float(l.weapon.mana_regen_delay_s).is_equal(0.8)


func test_ryker_kit_unlock_boost_and_ult_ranks() -> void:
	var d := load(RYKER) as HeroDef
	var frag := _skill(d, 0)
	assert_int(frag.def.targeting).is_equal(SkillDef.TargetMode.PROJECTILE)
	_assert_params(frag, {&"damage": 110, &"radius": 5, &"duration": 1.2, &"charges": 2, &"cooldown": 9})
	assert_int(frag.max_charges()).is_equal(2)
	_learn(frag, SkillNodeDef.Kind.BOOST, 3)
	_assert_params(frag, {&"damage": 130, &"cooldown": 7.5})
	var stim := _skill(d, 1)
	assert_bool(stim.def.cooldown_on_end).is_true()
	_assert_params(stim, {&"duration": 5, &"cooldown": 16})
	_learn(stim, SkillNodeDef.Kind.BOOST, 3)
	_assert_params(stim, {&"duration": 6, &"cooldown": 14})
	var slide := _skill(d, 2)
	assert_int(slide.def.targeting).is_equal(SkillDef.TargetMode.DIRECTION)
	_assert_params(slide, {&"distance": 7, &"cooldown": 8})
	_learn(slide, SkillNodeDef.Kind.BOOST, 3)
	_assert_params(slide, {&"cooldown": 6.5})
	var ult := _skill(d, 3)
	_assert_params(ult, {&"duration": 8, &"bonus_damage": 0.30, &"cooldown": 100, &"secondary_duration": 0})
	_learn(ult, SkillNodeDef.Kind.ULT_RANK, 6)
	_learn(ult, SkillNodeDef.Kind.ULT_RANK, 10)
	_assert_params(ult, {&"duration": 10, &"bonus_damage": 0.35, &"cooldown": 90})
	_learn(ult, SkillNodeDef.Kind.ULT_RANK, 14)
	_assert_params(ult, {&"duration": 12, &"bonus_damage": 0.40, &"cooldown": 80, &"secondary_duration": 2})
	assert_int(ult.rank).is_equal(3)


func test_ryker_stim_and_slide_effect_values() -> void:
	var d := load(RYKER) as HeroDef
	var stim := d.skills[1].effects[0] as StimEffectDef
	assert_float(stim.fire_rate_bonus).is_equal(0.25)
	assert_float(stim.speed_bonus).is_equal(0.15)
	assert_float(stim.hp_cost).is_equal(20.0)
	var slide := d.skills[2].effects[0] as SlideEffectDef
	assert_float(slide.reload_frac).is_equal(0.3)
	# W10-T1: the detonation hook is a Fork A gate; its else branch is the base blast.
	var gate := (d.skills[0].effects[0] as ThrownEffectDef).on_detonate[0] as ForkGateEffectDef
	var blast := gate.else_effects[0] as BlastEffectDef
	assert_float(blast.min_falloff).is_equal(0.4)
	assert_float(blast.wardling_mult).is_equal(1.5)


func test_sable_kit_unlock_boost_and_ult_ranks() -> void:
	var d := load(SABLE) as HeroDef
	var veil := _skill(d, 0)
	assert_bool(veil.def.cooldown_on_end).is_true()
	_assert_params(veil, {&"duration": 6, &"radius": 8, &"cooldown": 16})
	_learn(veil, SkillNodeDef.Kind.BOOST, 3)
	_assert_params(veil, {&"duration": 8, &"cooldown": 13})
	var phase := _skill(d, 1)
	_assert_params(phase, {&"distance": 8, &"cooldown": 14})
	var phase_fx := d.skills[1].effects[0] as SlideEffectDef
	assert_float(phase_fx.intangible_s).is_equal(0.4)
	_learn(phase, SkillNodeDef.Kind.BOOST, 3)
	_assert_params(phase, {&"distance": 10, &"cooldown": 11})
	var sab := _skill(d, 2)
	assert_bool(sab.def.interruptible).is_true()
	assert_bool(sab.def.recast_effects.is_empty()).is_false()
	_assert_params(sab, {&"damage": 120, &"radius": 4, &"max_placed": 2, &"cast_time": 1.0, &"cooldown": 12, &"range": 3})
	assert_float((d.skills[2].effects[0] as SabotageEffectDef).arm_s).is_equal(1.5)
	assert_float((d.skills[2].effects[0] as SabotageEffectDef).structure_frac).is_equal(0.25)
	_learn(sab, SkillNodeDef.Kind.BOOST, 3)
	_assert_params(sab, {&"damage": 150, &"max_placed": 3})
	var ult := _skill(d, 3)
	_assert_params(ult, {&"range": 40, &"speed": 80, &"duration": 2.0, &"bonus_damage": 0.40, &"secondary_duration": 2.0,
		&"cooldown": 100})
	_learn(ult, SkillNodeDef.Kind.ULT_RANK, 6)
	_learn(ult, SkillNodeDef.Kind.ULT_RANK, 10)
	_assert_params(ult, {&"duration": 2.25, &"bonus_damage": 0.50, &"secondary_duration": 2.5, &"cooldown": 90})
	_learn(ult, SkillNodeDef.Kind.ULT_RANK, 14)
	_assert_params(ult, {&"duration": 2.5, &"bonus_damage": 0.50, &"secondary_duration": 3.0, &"cooldown": 80})
	assert_bool(ult.effects().any(func(e: Variant) -> bool: return e is EclipseRiderEffectDef)).is_true()


func test_liora_kit_unlock_boost_and_ult_ranks() -> void:
	var d := load(LIORA) as HeroDef
	var drone := _skill(d, 0)
	_assert_params(drone, {&"heal_per_s": 60, &"duration": 2, &"charges": 2, &"cooldown": 12, &"range": 25})
	assert_float(drone.param(&"heal_per_s") * drone.param(&"duration")).is_equal(120.0)
	_learn(drone, SkillNodeDef.Kind.BOOST, 3)
	assert_float(drone.param(&"heal_per_s") * drone.param(&"duration")).is_equal(150.0)
	_assert_params(drone, {&"cooldown": 10})
	var ward := _skill(d, 1)
	_assert_params(ward, {&"hp": 150, &"duration": 4, &"cooldown": 14, &"range": 20})
	_learn(ward, SkillNodeDef.Kind.BOOST, 3)
	_assert_params(ward, {&"hp": 200})
	var bloom := _skill(d, 2)
	_assert_params(bloom, {&"duration": 1.0, &"distance": 3, &"radius": 10, &"range": 15, &"cooldown": 15})
	_learn(bloom, SkillNodeDef.Kind.BOOST, 3)
	_assert_params(bloom, {&"duration": 1.3, &"cooldown": 13})
	var ult := _skill(d, 3)
	_assert_params(ult, {&"radius": 12, &"duration": 6, &"heal_per_s": 80, &"cooldown": 130, &"dr": 0})
	_learn(ult, SkillNodeDef.Kind.ULT_RANK, 6)
	_learn(ult, SkillNodeDef.Kind.ULT_RANK, 10)
	_assert_params(ult, {&"heal_per_s": 100, &"duration": 7, &"cooldown": 115})
	_learn(ult, SkillNodeDef.Kind.ULT_RANK, 14)
	_assert_params(ult, {&"heal_per_s": 120, &"duration": 8, &"cooldown": 100, &"dr": 0.2})


func test_passives_are_data() -> void:
	var r := (load(RYKER) as HeroDef).passives[0]
	assert_int(r.kind).is_equal(HeroPassiveDef.Kind.BATTLE_RHYTHM)
	assert_float(r.magazine_refill_frac).is_equal(0.5)
	assert_float(r.speed_bonus).is_equal(0.15)
	assert_float(r.duration_s).is_equal(3.0)
	var s := (load(SABLE) as HeroDef).passives[0]
	assert_int(s.kind).is_equal(HeroPassiveDef.Kind.SHADOWGRAPH)
	assert_float(s.damage_bonus).is_equal(0.2)
	var lp := (load(LIORA) as HeroDef).passives
	assert_int(lp[0].kind).is_equal(HeroPassiveDef.Kind.TRIAGE_KIT)
	assert_float(lp[0].interval_s).is_equal(30.0)
	assert_int(lp[0].max_free).is_equal(2)
	assert_int(lp[1].kind).is_equal(HeroPassiveDef.Kind.HEAL_BEAM)
	assert_float(lp[1].range_m).is_equal(18.0)
	assert_float(lp[1].hero_heal_per_s).is_equal(60.0)
	assert_float(lp[1].wardling_heal_per_s).is_equal(30.0)
	assert_float(lp[1].mana_per_s).is_equal(25.0)


func test_heroes_are_content_db_entries_with_models() -> void:
	var db := ContentDB.shared()
	for id in [&"hero_ryker_vance", &"hero_sable", &"hero_liora_vale"]:
		assert_int(db.index_of(ContentDB.HERO, id)).is_greater(0)
	assert_str(String(ModelCatalog.hero_key(load(RYKER) as HeroDef))).is_equal("ryker")
	assert_str(String(ModelCatalog.hero_key(load(SABLE) as HeroDef))).is_equal("sable")
	assert_str(String(ModelCatalog.hero_key(load(LIORA) as HeroDef))).is_equal("liora")
	for key in [&"ryker", &"sable", &"liora"]:
		assert_int(HeroModelBuilder.blueprint(key)["tris"]).is_greater(0)


func test_health_floor_and_weapon_rate_mult() -> void:
	var h := HealthComponent.new(100.0, 0.0, 0)
	h.floor_hp = 1.0
	h.apply_damage(DamageInfo.make(500.0, 1, 1, 0, DamageInfo.Type.WEAPON))
	assert_float(h.hp).is_equal(1.0)
	h.floor_hp = 0.0
	h.apply_damage(DamageInfo.make(5.0, 1, 1, 0, DamageInfo.Type.WEAPON))
	assert_bool(h.is_alive()).is_false()
	var w := WeaponSim.new(load(RYKER).weapon, 30, 1)
	assert_float(w.rate_mult).is_equal(1.0)


func test_bots_have_rules_for_every_new_skill() -> void:
	var roster := load("res://assets/data/ai/bot_roster_slice.tres") as BotRosterDef
	for path in [RYKER, SABLE, LIORA]:
		var d := load(path) as HeroDef
		assert_bool(roster.heroes.has(d)).override_failure_message(d.id).is_true()
		assert_bool(roster.build_orders.has(d.id)).is_true()
