extends GdUnitTestSuite
## Armory items appended in v21 step 5 (weapons-and-mods.md Barrel and
## defensive Frame weaves, wardlings-and-economy.md §7 squad upgrades): the
## stat each one writes on a real ServerWorld, the combat hooks that read
## those stats (falloff range, armor pen, damage taken by type), the squad
## numbers the GDD names, and how the shipped guides offer them.

const PINNED_NEW: Array[StringName] = [&"focus_lens", &"rifling", &"penetrator", &"bastion_weave",
	&"null_weave", &"harmonic_tether", &"quick_mint", &"bulwark_protocol"]

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
	_builds = load("res://assets/data/economy/recommended_builds_slice.tres") as RecommendedBuildsDef
	_ar = load("res://assets/data/economy/advice_rules.tres") as AdviceRulesDef


func _hero(def: HeroDef) -> HeroBody:
	var id := _server.add_scripted_hero(ScriptedInputSource.new(CombatFixtures.idle_input()), Vector3.ZERO, def, 0)
	var h := _server.hero(id)
	_pr.progress_of(h).lumen = 20000
	return h


func _buy(h: HeroBody, id: StringName, tier: int = 0) -> int:
	return _pr.buy_index(h, _cat.index_of(id), tier)


func _stat(h: HeroBody, stat: int) -> float:
	return h.combat.stats.get_value(stat)


func test_new_items_are_appended_after_the_pinned_twelve() -> void:
	for i in PINNED_NEW.size():
		assert_int(_cat.index_of(PINNED_NEW[i])).is_equal(12 + i)
	for id in [&"harmonic_tether", &"quick_mint", &"bulwark_protocol"]:
		assert_int(_cat.index_of(id)).is_less(32)  # owned_bits is a u32


func test_barrel_lines_fit_their_family_and_stretch_falloff() -> void:
	var v := _hero(CombatFixtures.vesper())  # Mana gun
	assert_int(_buy(v, &"rifling")).is_equal(HeroProgress.Result.WRONG_FAMILY)
	assert_int(_buy(v, &"focus_lens")).is_equal(HeroProgress.Result.OK)
	assert_float(_stat(v, StatCatalog.FALLOFF_RANGE)).is_equal_approx(1.12, 1e-5)
	assert_int(_buy(v, &"focus_lens", 3)).is_equal(HeroProgress.Result.OK)
	assert_float(_stat(v, StatCatalog.FALLOFF_RANGE)).is_equal_approx(1.30, 1e-5)
	# Rifling and Penetrator share the Barrel socket: buying one sells the other.
	var b := _hero(CombatFixtures.brannoc())
	assert_int(_buy(b, &"penetrator")).is_equal(HeroProgress.Result.OK)
	assert_float(_stat(b, StatCatalog.ARMOR_PEN_BONUS)).is_equal_approx(0.10, 1e-5)
	assert_int(_buy(b, &"rifling")).is_equal(HeroProgress.Result.OK)
	assert_float(_stat(b, StatCatalog.ARMOR_PEN_BONUS)).is_equal_approx(0.0, 1e-5)
	assert_float(_stat(b, StatCatalog.FALLOFF_RANGE)).is_equal_approx(1.12, 1e-5)


func test_falloff_range_multiplier_moves_both_ends() -> void:
	var t := CombatFixtures.vesper().weapon  # Threadcaster 25–45 m -> 0.60
	assert_float(DamageMath.falloff(t, 35.0, 1.0)).is_equal_approx(0.8, 1e-6)
	# x1.2: 30–54 m, so 35 m is 5/24 of the way down.
	assert_float(DamageMath.falloff(t, 30.0, 1.2)).is_equal(1.0)
	assert_float(DamageMath.falloff(t, 35.0, 1.2)).is_equal_approx(1.0 - 0.4 * 5.0 / 24.0, 1e-5)
	assert_float(DamageMath.falloff(t, 60.0, 1.2)).is_equal_approx(0.6, 1e-6)
	assert_float(DamageMath.hit_damage(t, 35.0, false, 1, 1.2)).is_greater(DamageMath.hit_damage(t, 35.0, false))


func test_weaves_cut_only_their_damage_type_and_share_the_frame() -> void:
	var h := _hero(CombatFixtures.vesper())
	assert_int(_buy(h, &"bastion_weave", 3)).is_equal(HeroProgress.Result.OK)  # ANY family
	assert_float(_stat(h, StatCatalog.WEAPON_DAMAGE_TAKEN)).is_equal_approx(0.86, 1e-5)
	var hp := h.combat.health
	var armor_only := DamageMath.armor_mult(hp.armor, hp.damage_reduction)
	var gun := hp.apply_damage(DamageInfo.make(100.0, 99, 1, 0, DamageInfo.Type.WEAPON))
	assert_float(gun).is_equal_approx(100.0 * armor_only * 0.86, 1e-3)
	hp.hp = hp.max_hp
	var skill := hp.apply_damage(DamageInfo.make(100.0, 99, 1, 0, DamageInfo.Type.SKILL))
	assert_float(skill).is_equal_approx(100.0 * armor_only, 1e-3)
	# Null Weave replaces Bastion in the Frame (unique group frame_ward).
	assert_int(_buy(h, &"null_weave")).is_equal(HeroProgress.Result.OK)
	assert_float(_stat(h, StatCatalog.WEAPON_DAMAGE_TAKEN)).is_equal_approx(1.0, 1e-5)
	assert_float(_stat(h, StatCatalog.SKILL_DAMAGE_TAKEN)).is_equal_approx(0.92, 1e-5)
	hp.hp = hp.max_hp
	var cut := hp.apply_damage(DamageInfo.make(100.0, 99, 1, 0, DamageInfo.Type.SKILL))
	assert_float(cut).is_equal_approx(100.0 * armor_only * 0.92, 1e-3)
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
	assert_int(_pr.undo_item(h, _cat.index_of(&"harmonic_tether"))).is_equal(HeroProgress.Result.OK)
	assert_float(_stat(h, StatCatalog.WARDLING_SPEED_MULT)).is_equal_approx(1.0, 1e-5)


func test_squad_defaults_change_nothing_without_upgrades() -> void:
	var sq := Squad.new(1, 10, 0, 3)
	assert_float(sq.speed_mult).is_equal(1.0)
	assert_float(sq.leash_bonus_m).is_equal(0.0)
	assert_float(sq.mint_interval_mult).is_equal(1.0)
	assert_float(sq.mint_guard).is_equal(0.0)
	assert_float(sq.guard_dr).is_equal(0.0)


# --- guides -------------------------------------------------------------------

func _state(hero_def: HeroDef, lumen: int, own: Dictionary) -> BuildState:
	var st := BuildState.new()
	st.catalog = _cat
	st.weapon = hero_def.weapon
	st.lumen = lumen
	st.team_size = 5
	for id in own:
		st.holdings[_cat.index_of(id)] = int(own[id])
	return st


func _ids(r: BuildAdvisor.Result) -> Array:
	var out: Array = []
	for a in r.advice:
		out.append(String(a.node.id))
	return out


func test_weave_branches_open_on_damage_signals_and_the_frame_path_follows_the_weave() -> void:
	var g := _builds.for_hero(&"hero_vesper_loom")
	var st := _state(CombatFixtures.vesper(), 5000, {&"med_pack": 1, &"ember_heart": 1})
	assert_array(_ids(BuildAdvisor.evaluate(g, st, _ar))).not_contains(["vs_guns", "vs_skills"])
	st.signals = SnapshotData.ProgressState.SIG_WEAPON_DAMAGE
	var r := BuildAdvisor.evaluate(g, st, _ar)
	assert_array(_ids(r)).contains(["vs_guns"])
	assert_array(_ids(r)).not_contains(["vs_skills"])
	st.signals = SnapshotData.ProgressState.SIG_SKILL_DAMAGE
	assert_array(_ids(BuildAdvisor.evaluate(g, st, _ar))).contains(["vs_skills"])
	# Holding a weave: the Frame path upgrades the weave, never swaps back to Flux Coil.
	st = _state(CombatFixtures.vesper(), 5000, {&"med_pack": 1, &"ember_heart": 2, &"bastion_weave": 1})
	r = BuildAdvisor.evaluate(g, st, _ar)
	for a in r.advice:
		assert_int(a.item_index).is_not_equal(_cat.index_of(&"flux_coil"))
		if a.node.id == &"f2":
			assert_int(a.item_index).is_equal(_cat.index_of(&"bastion_weave"))


func test_barrel_and_penetrator_follow_the_gun_family() -> void:
	var mana := _builds.for_hero(&"hero_vesper_loom")
	var st := _state(CombatFixtures.vesper(), 9000, {&"med_pack": 1, &"ember_heart": 2, &"flux_coil": 1})
	var r := BuildAdvisor.evaluate(mana, st, _ar)
	var b1: Array = r.advice.filter(func(a: BuildAdvisor.Advice) -> bool: return a.node.id == &"b1")
	assert_int(b1.size()).is_equal(1)
	assert_int(b1[0].item_index).is_equal(_cat.index_of(&"focus_lens"))
	assert_bool(mana.node(&"vs_armor_barrel") == null).is_true()  # Mana guides carry no Penetrator
	var mech := _builds.for_hero(&"hero_brannoc")
	st = _state(CombatFixtures.brannoc(), 9000, {&"med_pack": 1, &"overclock": 1})
	assert_array(_ids(BuildAdvisor.evaluate(mech, st, _ar))).not_contains(["vs_armor_barrel"])
	st.enemy_tags = {"frontline": 2}
	assert_array(_ids(BuildAdvisor.evaluate(mech, st, _ar))).contains(["vs_armor_barrel"])
	# Penetrator held: the Barrel path continues on it.
	st = _state(CombatFixtures.brannoc(), 9000, {&"med_pack": 1, &"overclock": 2, &"quickload": 1, &"penetrator": 1})
	for a in BuildAdvisor.evaluate(mech, st, _ar).advice:
		assert_int(a.item_index).is_not_equal(_cat.index_of(&"rifling"))


func test_squad_guides_offer_the_new_squad_upgrades() -> void:
	var g := _builds.for_hero(&"hero_vesper_loom")
	var st := _state(CombatFixtures.vesper(), 9000, {&"med_pack": 1, &"ember_heart": 1, &"flux_coil": 1,
		&"reinforced_cores_1": 1, &"amplifier_emitters": 1, &"squad_expansion_1": 1})
	var ids := _ids(BuildAdvisor.evaluate(g, st, _ar))
	assert_array(ids).contains(["sq_mint", "sq_tether"])
	assert_array(ids).not_contains(["sq_bulwark"])  # late: needs Cores II and the third Core tier
	assert_bool(_builds.for_hero(&"hero_brannoc").node(&"sq_bulwark") != null).is_true()
