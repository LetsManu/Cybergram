extends GdUnitTestSuite
## Armory v2 combat through ServerWorld (items-and-armory.md §3.5, §4.3;
## weapons-and-mods.md §3.7.1): ammo effects on real hits, gear armor on the
## target, move-speed items and the out-of-combat bonus.

var _server: ServerWorld
var _link: LoopbackLink
var _net: NetConfig


func _world() -> void:
	_net = NetFixtures.net_config()
	_link = LoopbackLink.new(NetFixtures.profile(0, 0, 0.0))
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(auto_free(vp))
	_server = ServerWorld.new()
	vp.add_child(_server)
	_server.setup(_net, MovementDef.new(), CombatFixtures.range_scene(false), _link.create_endpoint(1),
		CombatFixtures.vesper(), load("res://assets/data/match/match_rules_slice.tres") as MatchRulesDef)


func _tick(n: int) -> void:
	for i in n:
		_link.advance(_net.tick_dt())
		_server.step()


func _duel(shooter_ammo: int, period: int = 6) -> Array[HeroBody]:
	_world()
	var target := _server.add_scripted_hero(ScriptedInputSource.new(CombatFixtures.idle_input()),
		_server.spawn_point("DummySpawn1"), CombatFixtures.vesper(), ServerWorld.TEAM_DUMMIES)
	var shooter := _server.add_scripted_hero(ScriptedInputSource.new(CombatFixtures.shooter_input(8.0, period)),
		_server.spawn_point("PlayerSpawn"), CombatFixtures.vesper(), ServerWorld.TEAM_PLAYERS)
	_server.hero(shooter).combat.ammo_type = shooter_ammo
	return [_server.hero(shooter), _server.hero(target)]


func test_incendiary_hits_burn_and_scorch_the_target() -> void:
	var pair := _duel(DamageMath.AMMO_INCENDIARY)
	await get_tree().physics_frame
	_tick(20)
	var t := pair[1].combat
	assert_bool(t.status.ammo.is_burning()).is_true()
	assert_float(t.health.heal_mult).is_equal_approx(0.70, 1e-4)


func test_cryo_hits_slow_the_target_inside_the_cap() -> void:
	var pair := _duel(DamageMath.AMMO_CRYO)
	await get_tree().physics_frame
	_tick(30)
	var t := pair[1].combat
	assert_float(t.status.ammo.chill).is_greater(0.0)
	assert_float(t.status.slow_total()).is_greater(0.0)
	assert_float(t.status.slow_total()).is_less_equal(0.25 + 1e-6)


func test_siphon_heals_the_shooter() -> void:
	var pair := _duel(DamageMath.AMMO_SIPHON)
	await get_tree().physics_frame
	var s := pair[0].combat
	s.health.hp = 100.0
	_tick(20)
	assert_float(s.health.hp).is_greater(100.0)


func test_gear_armor_reduces_hero_gunfire() -> void:
	var pair := _duel(DamageMath.AMMO_STANDARD, 1000)
	pair[1].combat.stats.add_modifier(Modifier.make(StatCatalog.GEAR_ARMOR, Modifier.Op.ADD, 0.13, 99))
	await get_tree().physics_frame
	_tick(3)
	# One Threadcaster body hit at 8 m: 29 × 0.87.
	assert_float(250.0 - pair[1].combat.health.hp).is_equal_approx(29.0 * 0.87, 0.01)


func test_move_speed_items_and_out_of_combat_bonus() -> void:
	_world()
	var id := _server.add_scripted_hero(ScriptedInputSource.new(CombatFixtures.idle_input()),
		_server.spawn_point("PlayerSpawn"), CombatFixtures.vesper(), ServerWorld.TEAM_PLAYERS)
	var h := _server.hero(id)
	h.combat.stats.add_modifier(Modifier.make(StatCatalog.ITEM_MOVE_SPEED, Modifier.Op.ADD, 0.04, 99))
	h.combat.stats.add_modifier(Modifier.make(StatCatalog.OOC_MOVE_SPEED, Modifier.Op.ADD, 0.08, 99))
	await get_tree().physics_frame
	_tick(2)
	# Never damaged: out of combat from the start.
	assert_float(h.state.speed_scale).is_equal_approx(1.12, 1e-4)
	_server.damage_hero(h, DamageInfo.make(5.0, 0, -1))
	_tick(2)
	assert_float(h.state.speed_scale).is_equal_approx(1.04, 1e-4)
	_tick(roundi(4.0 * _net.tick_rate_hz))
	assert_float(h.state.speed_scale).is_equal_approx(1.12, 1e-4)
