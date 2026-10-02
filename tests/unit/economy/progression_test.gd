extends GdUnitTestSuite
## E15 skill tree and E13/E15 income on a real ServerWorld (range scene, no
## map): reduced tree gates (Unlock, Boost at L3, ult ranks at 6/10/14, Forks
## refused), level-ups from Resonance, hero-kill bounty, capture / defence
## rewards with the recapture cooldown, trickle, Med-Pack, input actions.

const HZ: int = 30

var _server: ServerWorld
var _link: LoopbackLink
var _pr: ProgressionSystem
var _rules: EconomyRulesDef


func _setup() -> void:
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
	_rules = (load("res://assets/data/economy/economy_rules_slice.tres") as EconomyRulesDef).duplicate()
	_pr = _server.enable_progression(_rules, load(ArmoryCatalogDef.DEFAULT_PATH) as ArmoryCatalogDef, null)


func _hero(team: int, def: HeroDef = null, at: Vector3 = Vector3.ZERO) -> HeroBody:
	var id := _server.add_scripted_hero(ScriptedInputSource.new(CombatFixtures.idle_input()), at,
		def if def != null else CombatFixtures.vesper(), team)
	return _server.hero(id)


func test_reduced_tree_gates_unlock_boost_and_ult_ranks() -> void:
	_setup()
	var h := _hero(0)
	var p := _pr.progress_of(h)
	var r := h.combat.abilities
	assert_int(p.lumen).is_equal(500)  # starting purse
	assert_int(p.skill_points()).is_equal(1)
	# Unlearned skills cannot be cast with the tree on.
	assert_bool(r.is_unlocked(0)).is_false()
	var cmd := InputCommand.new()
	assert_bool(r.try_activate(0, h, cmd, 0, null)).is_false()
	assert_int(r.last_reject).is_equal(AbilityRunner.Reject.LOCKED)
	# Boost before Unlock, and Forks / Mastery, are refused.
	assert_int(_server.learn_skill(h, 0, SkillNodeDef.Kind.BOOST)).is_equal(HeroProgress.Result.REQUIRES)
	assert_int(_server.learn_skill(h, 0, SkillNodeDef.Kind.FORK_A)).is_equal(HeroProgress.Result.NOT_IN_SLICE)
	assert_int(_server.learn_skill(h, 0, SkillNodeDef.Kind.MASTERY)).is_equal(HeroProgress.Result.NOT_IN_SLICE)
	assert_int(_server.learn_skill(h, 1)).is_equal(HeroProgress.Result.OK)  # S2 Unlock
	assert_bool(r.is_unlocked(1)).is_true()
	assert_int(p.skill_points()).is_equal(0)
	assert_int(_server.learn_skill(h, 0)).is_equal(HeroProgress.Result.NO_POINTS)
	# L2: one point; Boost is gated at L3.
	_pr.debug_set_level(h, 2)
	assert_int(_server.learn_skill(h, 1)).is_equal(HeroProgress.Result.LEVEL_GATE)
	_pr.debug_set_level(h, 3)
	var cd_before := r.skill(1).param(&"cooldown")
	assert_int(_server.learn_skill(h, 1)).is_equal(HeroProgress.Result.OK)  # Boost
	assert_bool(r.skill(1).has_node(SkillNodeDef.Kind.BOOST)).is_true()
	assert_int(r.hud_state(1, 0)[2] & AbilityRunner.FLAG_BOOSTED).is_equal(AbilityRunner.FLAG_BOOSTED)
	assert_bool(r.skill(1).param(&"cooldown") != cd_before or r.skill(1).learned.size() == 2).is_true()
	assert_int(_server.learn_skill(h, 1)).is_equal(HeroProgress.Result.MAXED)  # no Forks in the slice
	# Ultimate: rank 1 at L6, rank 2 at L10, rank 3 at L14.
	_pr.debug_set_level(h, 5)
	assert_int(_server.learn_skill(h, 3)).is_equal(HeroProgress.Result.LEVEL_GATE)
	assert_bool(r.is_unlocked(3)).is_false()
	_pr.debug_set_level(h, 6)
	assert_int(_server.learn_skill(h, 3)).is_equal(HeroProgress.Result.OK)
	assert_int(r.skill(3).rank).is_equal(1)
	assert_bool(r.is_unlocked(3)).is_true()
	_pr.debug_set_level(h, 9)
	assert_int(_server.learn_skill(h, 3)).is_equal(HeroProgress.Result.LEVEL_GATE)
	_pr.debug_set_level(h, 10)
	assert_int(_server.learn_skill(h, 3)).is_equal(HeroProgress.Result.OK)
	_pr.debug_set_level(h, 14)
	assert_int(_server.learn_skill(h, 3)).is_equal(HeroProgress.Result.OK)
	assert_int(r.skill(3).rank).is_equal(3)
	assert_int(_server.learn_skill(h, 3)).is_equal(HeroProgress.Result.MAXED)
	assert_int(r.hud_state(3, 0)[2] & AbilityRunner.RANK_MASK).is_equal(3 << AbilityRunner.RANK_SHIFT)
	assert_int(_server.learn_skill(h, 9)).is_equal(HeroProgress.Result.NO_SKILL)


func test_learn_and_spawn_choice_arrive_as_input_actions_even_while_dead() -> void:
	_setup()
	var h := _hero(0)
	h.combat.dead = true
	h.combat.respawn_tick = 1000000
	var cmd := InputCommand.new()
	cmd.action = InputCommand.ACTION_LEARN
	cmd.action_arg = 2
	_server._step_hero(h, cmd)
	assert_bool(h.combat.abilities.skill(2).unlocked).is_true()
	cmd.action = InputCommand.ACTION_SPAWN_CHOICE
	cmd.action_arg = HeroProgress.SPAWN_BEACON
	_server._step_hero(h, cmd)
	assert_int(_pr.progress_of(h).spawn_choice).is_equal(HeroProgress.SPAWN_BEACON)
	assert_that(_pr.respawn_point(h)).is_null()  # no Beacon on this map: Sanctum


func test_resonance_levels_up_and_scales_the_hero() -> void:
	_setup()
	var h := _hero(0)
	var levels: Array[int] = []
	_pr.leveled_up.connect(func(_id: int, l: int) -> void: levels.append(l))
	_pr.award_exp(h, 189.0)
	assert_int(_pr.progress_of(h).level).is_equal(1)
	_pr.award_exp(h, 1.0)
	assert_int(_pr.progress_of(h).level).is_equal(2)
	assert_int(h.combat.level).is_equal(2)
	assert_float(h.combat.health.max_hp).is_equal_approx(260.0, 1e-3)
	_pr.award_exp(h, 2000.0)  # 2190 -> L7
	assert_int(_pr.progress_of(h).level).is_equal(7)
	assert_array(levels).contains_exactly([2, 7])
	assert_int(_pr.progress_of(h).skill_points()).is_equal(7)
	_pr.award_exp(h, 100000.0)
	assert_int(_pr.progress_of(h).level).is_equal(15)


func test_hero_kill_pays_killer_and_assister() -> void:
	_setup()
	var killer := _hero(0)
	var mate := _hero(0, null, Vector3(40.0, 0.05, 0.0))  # outside 25 m, but assisted
	var far := _hero(0, null, Vector3(-35.0, 0.05, 0.0))  # neither
	var victim := _hero(1, null, Vector3(0.0, 0.05, -8.0))
	_server.damage_hero(victim, DamageInfo.make(10.0, mate.net_id, 0))
	_server.damage_hero(victim, DamageInfo.make(5000.0, killer.net_id, 0))
	assert_bool(victim.combat.dead).is_true()
	var kp := _pr.progress_of(killer)
	assert_int(kp.lumen).is_equal(500 + 200)  # K = 200 × D(1)
	assert_float(kp.exp).is_equal_approx(220.0, 1e-3)  # P = 200 + 20·1
	assert_int(kp.level).is_equal(2)
	assert_int(kp.streak).is_equal(1)
	var mp := _pr.progress_of(mate)
	assert_int(mp.lumen).is_equal(600)  # assist 100 × D
	assert_float(mp.exp).is_greater(0.0)
	assert_int(_pr.progress_of(far).lumen).is_equal(500)
	assert_float(_pr.progress_of(far).exp).is_equal(0.0)


func test_capture_and_defence_rewards_with_recapture_cooldown() -> void:
	_setup()
	var a := _hero(0)
	var b := _hero(0)
	var enemy := _hero(1)
	var ev := ObjectiveEvent.new()
	ev.kind = ObjectiveEvent.Kind.FLIP
	ev.hardpoint_id = &"s_mid"
	ev.new_team = 0
	ev.old_team = MapDef.TEAM_NEUTRAL
	ev.participants = PackedInt32Array([a.net_id])
	ev.lumen_each = 120
	ev.lumen_team = 40
	_server.objective_event.emit(ev)
	assert_int(_pr.progress_of(a).lumen).is_equal(500 + 120 + 40)
	assert_float(_pr.progress_of(a).exp).is_equal_approx(350.0, 1e-3)
	assert_int(_pr.progress_of(b).lumen).is_equal(540)
	assert_float(_pr.progress_of(b).exp).is_equal_approx(100.0, 1e-3)
	assert_int(_pr.progress_of(enemy).lumen).is_equal(500)
	# Same team, same hardpoint within 180 s: ×0.25 (Lumen and EXP).
	_server.objective_event.emit(ev)
	assert_int(_pr.progress_of(b).lumen).is_equal(550)
	var d := ObjectiveEvent.new()
	d.kind = ObjectiveEvent.Kind.DEFENCE
	d.hardpoint_id = &"s_mid"
	d.new_team = 1
	d.participants = PackedInt32Array([enemy.net_id])
	d.lumen_each = 60
	_server.objective_event.emit(d)
	assert_int(_pr.progress_of(enemy).lumen).is_equal(560)
	_server.objective_event.emit(d)  # defence cooldown 90 s
	assert_int(_pr.progress_of(enemy).lumen).is_equal(560)


func test_trickle_starts_at_one_minute_at_60_per_minute() -> void:
	_setup()
	var h := _hero(0)
	_server.tick = 60 * HZ
	_pr.step()
	assert_int(_pr.progress_of(h).lumen).is_equal(500)
	_server.tick = 120 * HZ
	_pr.step()
	assert_int(_pr.progress_of(h).lumen).is_equal(560)
	_server.tick = 150 * HZ
	_pr.step()
	assert_int(_pr.progress_of(h).lumen).is_equal(590)


func test_med_pack_heals_40_percent_over_3s_and_firing_cancels() -> void:
	_setup()
	var h := _hero(0)
	var p := _pr.progress_of(h)
	assert_int(_server.use_medpack(h)).is_equal(HeroProgress.Result.NOT_OWNED)
	p.medpacks = 2
	h.combat.health.hp = 100.0
	assert_int(_server.use_medpack(h)).is_equal(HeroProgress.Result.OK)
	for i in 3 * HZ:
		_pr.step()
		_server.tick += 1
	assert_float(h.combat.health.hp).is_equal_approx(200.0, 0.5)  # +40% of 250
	h.combat.health.hp = 100.0
	assert_int(_server.use_medpack(h)).is_equal(HeroProgress.Result.OK)
	for i in 10:
		_pr.step()
		_server.tick += 1
	h.combat.weapon.shots_fired += 1  # fired
	var hp := h.combat.health.hp
	for i in 30:
		_pr.step()
		_server.tick += 1
	assert_float(h.combat.health.hp).is_equal_approx(hp, 1e-4)
	assert_int(p.medpacks).is_equal(0)
