extends GdUnitTestSuite
## W9-H2 data and rules: skill charges (SkillInstance), the kit numbers of
## design/gdd/heroes.md §4.3 (Juniper Quill) and §4.7 (Hex), the hack
## durations of §5.4 and the gadget bonus field.


func _skill(id: String) -> SkillDef:
	return load("res://assets/data/skills/skill_%s.tres" % id) as SkillDef


func test_charges_spend_and_recharge_one_at_a_time() -> void:
	var s := SkillInstance.new(_skill("juniper_snare_coil"), 0)
	assert_int(s.max_charges()).is_equal(2)
	assert_bool(s.on_cooldown(0)).is_false()
	s.consume_charge(0, 300)
	assert_int(s.charges_left).is_equal(1)
	assert_bool(s.on_cooldown(1)).is_false()
	s.consume_charge(10, 300)
	assert_bool(s.on_cooldown(11)).is_true()
	assert_int(s.cooldown_ticks_left(11)).is_equal(289)
	assert_bool(s.on_cooldown(300)).is_false()  # first charge back at tick 300
	assert_int(s.charges_left).is_equal(1)
	assert_bool(s.on_cooldown(600)).is_false()
	assert_int(s.charges_left).is_equal(2)


func test_boost_adds_a_third_charge_immediately_usable() -> void:
	var s := SkillInstance.new(_skill("juniper_snare_coil"), 0)
	s.learn(s.node_of(SkillNodeDef.Kind.BOOST))
	assert_int(s.max_charges()).is_equal(3)
	assert_bool(s.on_cooldown(0)).is_false()
	assert_int(s.charges_left).is_equal(3)
	assert_float(s.param(&"duration")).is_equal(1.5)  # root 1.25 -> 1.5


func test_single_charge_skills_keep_the_plain_cooldown() -> void:
	var s := SkillInstance.new(_skill("juniper_pressure_mine"), 0)
	assert_bool(s.is_multi()).is_false()
	s.cooldown_end_tick = 100
	assert_bool(s.on_cooldown(99)).is_true()
	assert_bool(s.on_cooldown(100)).is_false()


func test_juniper_numbers_match_the_gdd() -> void:
	var sn := _skill("juniper_snare_coil")
	assert_float(sn.param(&"damage")).is_equal(30.0)
	assert_float(sn.param(&"duration")).is_equal(1.25)
	assert_float(sn.param(&"cooldown")).is_equal(10.0)
	assert_float(sn.param(&"arm_time")).is_equal(1.0)
	var tw := _skill("juniper_tripwire_lattice")
	assert_float(tw.param(&"damage")).is_equal(70.0)
	assert_float(tw.param(&"slow")).is_equal(0.4)
	assert_float(tw.param(&"distance")).is_equal(10.0)
	assert_float(tw.param(&"cooldown")).is_equal(12.0)
	assert_int(tw.recast_effects.size()).is_equal(1)
	var mine := _skill("juniper_pressure_mine")
	assert_float(mine.param(&"damage")).is_equal(140.0)
	assert_float(mine.param(&"radius")).is_equal(5.0)
	assert_float(mine.param(&"arm_time")).is_equal(2.0)
	assert_float(mine.param(&"max_placed")).is_equal(2.0)
	var kb := _skill("juniper_killbox")
	assert_bool(kb.ultimate).is_true()
	assert_float(kb.param(&"radius")).is_equal(12.0)
	assert_float(kb.param(&"hp")).is_equal(400.0)


func test_killbox_ranks_follow_the_table() -> void:
	var s := SkillInstance.new(_skill("juniper_killbox"), 3)
	var expect := [[8.0, 80.0, 1.0, 120.0], [10.0, 100.0, 1.0, 110.0], [12.0, 120.0, 1.2, 100.0]]
	for r in 3:
		s.learn(s.node_of(SkillNodeDef.Kind.ULT_RANK, r + 1))
		assert_float(s.param(&"duration")).is_equal_approx(expect[r][0], 1e-4)
		assert_float(s.param(&"damage")).is_equal_approx(expect[r][1], 1e-4)
		assert_float(s.param(&"stun")).is_equal_approx(expect[r][2], 1e-4)
		assert_float(s.param(&"cooldown")).is_equal_approx(expect[r][3], 1e-4)
	assert_float(s.param(&"slow")).is_equal_approx(0.2, 1e-4)  # Rank 3 rider


func test_zero_day_ranks_follow_the_table() -> void:
	var s := SkillInstance.new(_skill("hex_zero_day"), 3)
	var expect := [[6.0, 4.0, 3.0, 120.0], [8.0, 5.0, 4.0, 110.0], [10.0, 6.0, 5.0, 100.0]]
	for r in 3:
		s.learn(s.node_of(SkillNodeDef.Kind.ULT_RANK, r + 1))
		assert_float(s.param(&"duration")).is_equal_approx(expect[r][0], 1e-4)
		assert_float(s.param(&"scramble")).is_equal_approx(expect[r][1], 1e-4)
		assert_float(s.param(&"lag")).is_equal_approx(expect[r][2], 1e-4)
		assert_float(s.param(&"cooldown")).is_equal_approx(expect[r][3], 1e-4)
	assert_float(s.param(&"radius")).is_equal(20.0)


func test_hex_numbers_match_the_gdd() -> void:
	var sp := _skill("hex_breach_spike")
	assert_float(sp.param(&"damage")).is_equal(40.0)
	assert_float(sp.param(&"range")).is_equal(35.0)
	assert_float(sp.param(&"scramble")).is_equal(3.0)
	var hack := (sp.effects[0] as ProjectileEffectDef).on_hit[0] as HackEffectDef
	assert_float(hack.trap_s).is_equal(6.0)
	assert_float(hack.turret_s).is_equal(4.0)
	assert_float(hack.deployable_s).is_equal(3.0)
	assert_float(hack.wardling_s).is_equal(3.0)
	assert_float(hack.barricade_s).is_equal(4.0)
	assert_float(hack.immune_s).is_equal(4.0)
	var fld := _skill("hex_static_field")
	assert_float(fld.param(&"radius")).is_equal(6.0)
	assert_float(fld.param(&"duration")).is_equal(6.0)
	var hop := _skill("hex_relay_hop")
	assert_float(hop.param(&"range")).is_equal(30.0)
	assert_float(hop.param(&"cast_time")).is_equal(0.5)
	assert_int(hop.targeting).is_equal(SkillDef.TargetMode.GADGET)


func test_hero_stats_and_weapons() -> void:
	var j := load("res://assets/data/heroes/hero_juniper_quill.tres") as HeroDef
	var h := load("res://assets/data/heroes/hero_hex.tres") as HeroDef
	assert_int(j.max_hp).is_equal(250)
	assert_int(h.max_hp).is_equal(250)
	assert_float(j.move_speed).is_equal(6.0)
	assert_int(j.skills.size()).is_equal(4)
	assert_int(h.skills.size()).is_equal(4)
	assert_float(j.weapon.damage * j.weapon.fire_rate).is_equal_approx(135.0, 0.01)  # Mid band
	assert_float(h.weapon.damage * h.weapon.fire_rate).is_between(130.0, 160.0)
	assert_float(h.weapon.range_m).is_equal(15.0)  # Glitchcaster hard max
	assert_float(j.gadget_damage_mult).is_equal(1.0)
	assert_float(h.gadget_damage_mult).is_equal(1.5)
	assert_str(String(ModelCatalog.hero_key(j))).is_equal("juniper")
	assert_str(String(ModelCatalog.hero_key(h))).is_equal("hex")


func test_content_db_lists_the_new_heroes() -> void:
	var db := ContentDB.shared()
	assert_int(db.index_of(ContentDB.HERO, &"hero_juniper_quill")).is_greater(0)
	assert_int(db.index_of(ContentDB.HERO, &"hero_hex")).is_greater(0)
