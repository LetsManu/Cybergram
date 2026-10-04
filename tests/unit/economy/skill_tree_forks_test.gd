extends GdUnitTestSuite
## W10-T1 skill tree nodes (heroes.md §2 / §3.5): Fork at L5 (A or B, permanent), Mastery at
## L9 and only after a Fork, ultimates take no Forks, the choice travels in the ACTION_LEARN arg.

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



func _boost(h: HeroBody, slot: int) -> void:
	_pr.debug_set_level(h, 3)
	assert_int(_server.learn_skill(h, slot)).is_equal(HeroProgress.Result.OK)  # Unlock
	assert_int(_server.learn_skill(h, slot)).is_equal(HeroProgress.Result.OK)  # Boost


func test_fork_needs_boost_level_five_and_an_explicit_choice() -> void:
	_setup()
	var h := _hero(0)
	_pr.debug_set_level(h, 4)
	var r := h.combat.abilities
	assert_int(_server.learn_skill(h, 0, SkillNodeDef.Kind.FORK_A)).is_equal(HeroProgress.Result.REQUIRES)  # no Unlock
	_server.learn_skill(h, 0)  # Unlock
	assert_int(_server.learn_skill(h, 0, SkillNodeDef.Kind.FORK_A)).is_equal(HeroProgress.Result.REQUIRES)  # no Boost
	_server.learn_skill(h, 0)  # Boost
	assert_int(_server.learn_skill(h, 0, SkillNodeDef.Kind.FORK_A)).is_equal(HeroProgress.Result.LEVEL_GATE)  # L4
	_pr.debug_set_level(h, 5)
	# No explicit choice: nothing is spent, the HUD offers A / B.
	var spent := _pr.progress_of(h).spent
	assert_int(_server.learn_skill(h, 0)).is_equal(HeroProgress.Result.FORK_CHOICE)
	assert_int(_pr.progress_of(h).spent).is_equal(spent)
	assert_bool(AbilityRunner.fork_offered(r.hud_state(0, 0)[2] | AbilityRunner.FLAG_LEARNABLE, false)).is_true()
	assert_int(_server.learn_skill(h, 0, SkillNodeDef.Kind.MASTERY)).is_equal(HeroProgress.Result.REQUIRES)  # Mastery needs a Fork
	assert_int(_server.learn_skill(h, 0, SkillNodeDef.Kind.FORK_B)).is_equal(HeroProgress.Result.OK)
	assert_int(r.skill(0).fork()).is_equal(2)
	assert_int(AbilityRunner.fork_of_flags(r.hud_state(0, 0)[2])).is_equal(2)


func test_fork_choice_is_permanent_and_mastery_needs_level_nine() -> void:
	_setup()
	var h := _hero(0)
	_boost(h, 1)
	_pr.debug_set_level(h, 5)
	assert_int(_server.learn_skill(h, 1, SkillNodeDef.Kind.FORK_A)).is_equal(HeroProgress.Result.OK)
	# Neither the other Fork nor a second copy of this one can be bought.
	assert_int(_server.learn_skill(h, 1, SkillNodeDef.Kind.FORK_B)).is_equal(HeroProgress.Result.FORK_LOCKED)
	assert_int(_server.learn_skill(h, 1, SkillNodeDef.Kind.FORK_A)).is_equal(HeroProgress.Result.FORK_LOCKED)
	assert_int(_server.learn_skill(h, 1)).is_equal(HeroProgress.Result.LEVEL_GATE)  # Mastery at L5
	_pr.debug_set_level(h, 8)
	assert_int(_server.learn_skill(h, 1)).is_equal(HeroProgress.Result.LEVEL_GATE)
	_pr.debug_set_level(h, 9)
	assert_int(_server.learn_skill(h, 1)).is_equal(HeroProgress.Result.OK)  # Mastery
	var r := h.combat.abilities
	assert_bool(r.skill(1).has_mastery()).is_true()
	assert_int(r.skill(1).fork()).is_equal(1)  # the Fork stays
	assert_int(r.hud_state(1, 0)[2] & AbilityRunner.FLAG_MASTERY).is_equal(AbilityRunner.FLAG_MASTERY)
	assert_int(_server.learn_skill(h, 1)).is_equal(HeroProgress.Result.MAXED)
	# Ultimates take no Forks.
	assert_int(_server.learn_skill(h, 3, SkillNodeDef.Kind.FORK_A)).is_equal(HeroProgress.Result.NOT_IN_SLICE)


func test_learn_action_arg_carries_the_fork_choice() -> void:
	_setup()
	var h := _hero(0)
	_boost(h, 2)
	_pr.debug_set_level(h, 5)
	assert_int(ProgressionSystem.learn_arg(2, 2)).is_equal(2 | (2 << 2))
	assert_int(ProgressionSystem.learn_kind_of_arg(ProgressionSystem.learn_arg(2, 0))).is_equal(-1)
	var cmd := InputCommand.new()
	cmd.action = InputCommand.ACTION_LEARN
	cmd.action_arg = ProgressionSystem.learn_arg(2, 0)  # Alt + key without a choice
	assert_int(_pr.handle_action(h, cmd)).is_equal(HeroProgress.Result.FORK_CHOICE)
	cmd.action_arg = ProgressionSystem.learn_arg(2, 2)
	assert_int(_pr.handle_action(h, cmd)).is_equal(HeroProgress.Result.OK)
	assert_int(h.combat.abilities.skill(2).fork()).is_equal(2)
	cmd.action_arg = ProgressionSystem.learn_arg(2, 1)
	assert_int(_pr.handle_action(h, cmd)).is_equal(HeroProgress.Result.FORK_LOCKED)
	cmd.quantize()
	assert_int(cmd.action_arg).is_equal(ProgressionSystem.learn_arg(2, 1))  # survives the u16 wire field


func test_every_basic_skill_of_every_hero_has_both_forks_and_a_mastery() -> void:
	for path in ["vesper_loom", "brannoc", "ryker_vance", "liora_vale", "sable", "juniper_quill", "hex"]:
		var d := load("res://assets/data/heroes/hero_%s.tres" % path) as HeroDef
		for i in 3:
			var s := SkillInstance.new(d.skills[i], i)
			for k in [SkillNodeDef.Kind.FORK_A, SkillNodeDef.Kind.FORK_B, SkillNodeDef.Kind.MASTERY]:
				var n := s.node_of(k)
				assert_object(n).override_failure_message("%s slot %d kind %d" % [path, i, k]).is_not_null()
				assert_int(n.required_level).is_equal(9 if k == SkillNodeDef.Kind.MASTERY else 5)
				assert_bool(n.modifiers.size() > 0 or n.added_effects.size() > 0).is_true()


func test_bot_roster_fork_preferences_are_data() -> void:
	var roster := load("res://assets/data/ai/bot_roster_slice.tres") as BotRosterDef
	var hex := load("res://assets/data/heroes/hero_hex.tres") as HeroDef
	assert_int(roster.fork_prefs_for(hex)[0]).is_equal(2)
	assert_int(roster.fork_prefs_for(null).size()).is_equal(3)
