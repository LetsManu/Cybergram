extends GdUnitTestSuite
## Armory v22 items with combat hooks (items-and-armory.md; wardlings-and-economy.md
## §7 squad upgrades): the stat each one writes on a real ServerWorld, the
## combat hooks that read those stats (falloff range, armor pen, gear armor /
## resist by damage type), the squad numbers the GDD names, and how the
## shipped guides offer the squad upgrades.

const SQUAD_NEW: Array[StringName] = [&"harmonic_tether", &"quick_mint", &"bulwark_protocol"]

var _server: ServerWorld
var _link: LoopbackLink
var _pr: ProgressionSystem
var _cat: ArmoryCatalogDef
var _builds: RecommendedBuildsDef
var _ar: AdviceRulesDef


func before_test() -> void:
	var net := NetFixtures.net_config()
	_link = LoopbackLink.new(NetFixtures.profile(0, 0, 0.0))
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(auto_free(vp))
	_server = ServerWorld.new()
	vp.add_child(_server)
	_server.setup(net, MovementDef.new(), CombatFixtures.range_scene(false), _link.create_endpoint(1),
		CombatFixtures.vesper(), load("res://assets/data/match/match_rules_slice.tres") as MatchRulesDef)
	_cat = load(ArmoryCatalogDef.DEFAULT_PATH) as ArmoryCatalogDef
	_pr = _server.enable_progression(load("res://assets/data/economy/economy_rules_slice.tres"), _cat, null)
	_pr.debug_shop_anywhere = true
	_pr.armory_log = false
	_builds = load(RecommendedBuildsDef.DEFAULT_PATH) as RecommendedBuildsDef
	_ar = load("res://assets/data/economy/advice_rules.tres") as AdviceRulesDef


func _hero(def: HeroDef) -> HeroBody:
	var id := _server.add_scripted_hero(ScriptedInputSource.new(CombatFixtures.idle_input()), Vector3.ZERO, def, 0)
	var h := _server.hero(id)
	_pr.progress_of(h).lumen = 20000
	return h


func _buy(h: HeroBody, id: StringName) -> int:
	return _pr.buy_index(h, _cat.index_of(id))


func _stat(h: HeroBody, stat: int) -> float:
	return h.combat.stats.get_value(stat)


func test_squad_upgrades_stay_inside_the_u32_owned_bits() -> void:
	for id in SQUAD_NEW:
		assert_int(_cat.index_of(id)).is_greater_equal(0)
		assert_int(_cat.index_of(id)).is_less(32)  # owned_bits is a u32


func test_barrel_rings_stretch_falloff_or_pierce_and_share_the_socket() -> void:
	var v := _hero(CombatFixtures.vesper())
	assert_int(_buy(v, &"longsight_ring")).is_equal(HeroProgress.Result.OK)
	assert_float(_stat(v, StatCatalog.FALLOFF_RANGE)).is_greater(1.0)
	# Longsight Ring and Bore Ring share the Barrel socket: buying one sells the other.
	assert_int(_buy(v, &"bore_ring")).is_equal(HeroProgress.Result.OK)
	assert_float(_stat(v, StatCatalog.ARMOR_PEN_BONUS)).is_equal_approx(0.15, 1e-5)
	assert_float(_stat(v, StatCatalog.FALLOFF_RANGE)).is_equal_approx(1.0, 1e-5)


func test_falloff_range_multiplier_moves_both_ends() -> void:
	var t := CombatFixtures.vesper().weapon  # Threadcaster 25–45 m -> 0.60
	assert_float(DamageMath.falloff(t, 35.0, 1.0)).is_equal_approx(0.8, 1e-6)
	# x1.2: 30–54 m, so 35 m is 5/24 of the way down.
	assert_float(DamageMath.falloff(t, 30.0, 1.2)).is_equal(1.0)
	assert_float(DamageMath.falloff(t, 35.0, 1.2)).is_equal_approx(1.0 - 0.4 * 5.0 / 24.0, 1e-5)
	assert_float(DamageMath.falloff(t, 60.0, 1.2)).is_equal_approx(0.6, 1e-6)
	assert_float(DamageMath.hit_damage(t, 35.0, false, 1, 1.2)).is_greater(DamageMath.hit_damage(t, 35.0, false))


func test_gear_armor_cuts_weapon_damage_and_gear_resist_cuts_skill_damage() -> void:
	var h := _hero(CombatFixtures.vesper())
	var hp := h.combat.health
	var armor_only := DamageMath.armor_mult(hp.armor, hp.damage_reduction)
	var bare_weapon := hp.apply_damage(DamageInfo.make(100.0, 99, 1, 0, DamageInfo.Type.WEAPON))
	hp.hp = hp.max_hp
	assert_float(bare_weapon).is_equal_approx(100.0 * armor_only, 1e-3)
	assert_int(_buy(h, &"plate_harness")).is_equal(HeroProgress.Result.OK)
	hp.hp = hp.max_hp
	var with_plate := hp.apply_damage(DamageInfo.make(100.0, 99, 1, 0, DamageInfo.Type.WEAPON))
	assert_float(with_plate).is_less(bare_weapon)
	hp.hp = hp.max_hp
	var skill := hp.apply_damage(DamageInfo.make(100.0, 99, 1, 0, DamageInfo.Type.SKILL))
	assert_float(skill).is_equal_approx(100.0 * armor_only, 1e-3)  # armor gear does not cut skills
	assert_int(_buy(h, &"null_cowl")).is_equal(HeroProgress.Result.OK)
	hp.hp = hp.max_hp
	assert_float(hp.apply_damage(DamageInfo.make(100.0, 99, 1, 0, DamageInfo.Type.SKILL))).is_less(skill)
	# TRUE damage ignores both.
	hp.hp = hp.max_hp
	assert_float(hp.apply_damage(DamageInfo.make(50.0, 99, 1, 0, DamageInfo.Type.TRUE))).is_equal_approx(50.0, 1e-4)


func test_squad_upgrades_write_the_gdd_numbers() -> void:
	var h := _hero(CombatFixtures.vesper())
	var rules := load("res://assets/data/wardlings/wardling_rules_slice.tres") as WardlingRulesDef
	assert_int(_buy(h, &"harmonic_tether")).is_equal(HeroProgress.Result.OK)
	assert_float(_stat(h, StatCatalog.WARDLING_SPEED_MULT)).is_equal_approx(1.12, 1e-5)
	assert_float(rules.follow_leash_m + _stat(h, StatCatalog.WARDLING_LEASH_BONUS)).is_equal_approx(40.0, 1e-4)
	assert_int(_buy(h, &"quick_mint")).is_equal(HeroProgress.Result.OK)
	assert_float(rules.mint_interval_s * _stat(h, StatCatalog.MINT_INTERVAL_MULT)).is_equal_approx(0.1, 1e-4)
	assert_float(_stat(h, StatCatalog.MINT_GUARD)).is_equal_approx(0.25, 1e-5)
	assert_float(rules.quick_mint_guard_s).is_equal(5.0)
	assert_int(_buy(h, &"bulwark_protocol")).is_equal(HeroProgress.Result.OK)
	assert_float(_stat(h, StatCatalog.WARDLING_GUARD_DR)).is_equal_approx(0.30, 1e-5)
	# Same-visit undo removes the effect (v21).
	assert_int(_pr.undo(h, -1, _cat.index_of(&"harmonic_tether"))).is_equal(HeroProgress.Result.OK)
	assert_float(_stat(h, StatCatalog.WARDLING_SPEED_MULT)).is_equal_approx(1.0, 1e-5)


func test_squad_defaults_change_nothing_without_upgrades() -> void:
	var sq := Squad.new(1, 10, 0, 3)
	assert_float(sq.speed_mult).is_equal(1.0)
	assert_float(sq.leash_bonus_m).is_equal(0.0)
	assert_float(sq.mint_interval_mult).is_equal(1.0)
	assert_float(sq.mint_guard).is_equal(0.0)
	assert_float(sq.guard_dr).is_equal(0.0)


# --- guides -------------------------------------------------------------------

func test_every_guide_names_a_squad_step_and_the_squad_upgrades_are_in_some_guide() -> void:
	var named := {}
	for g in _builds.builds:
		var squad := 0
		for n in g.nodes:
			var it := _cat.find(StringName(n.item_id))
			if it != null and it.kind == ArmoryItemDef.Kind.SQUAD:
				squad += 1
			named[String(n.item_id)] = true
			for alt in n.alternatives:
				named[String(alt)] = true
		assert_int(squad).override_failure_message("%s has no squad step" % g.hero_id).is_greater(0)
	for id in SQUAD_NEW:
		assert_bool(named.has(String(id))).override_failure_message("%s in no guide" % id).is_true()
