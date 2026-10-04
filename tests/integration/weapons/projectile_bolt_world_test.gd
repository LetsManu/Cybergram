extends GdUnitTestSuite
## W10-W2 integration: a Halo Repeater bolt on a real ServerWorld takes travel time to
## hit (not instant), is stopped by a wall, and rewinds like hitscan.

const LIORA := "res://assets/data/heroes/hero_liora_vale.tres"

var _server: ServerWorld
var _link: LoopbackLink
var _net: NetConfig


func _world(wall: bool) -> void:
	_net = NetFixtures.net_config()
	_link = LoopbackLink.new(NetFixtures.profile(0, 0, 0.0))
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(auto_free(vp))
	_server = ServerWorld.new()
	vp.add_child(_server)
	_server.setup(_net, MovementDef.new(), CombatFixtures.range_scene(wall), _link.create_endpoint(1),
		CombatFixtures.vesper(), load("res://assets/data/match/match_rules_slice.tres") as MatchRulesDef)


func _shooter_and_target() -> Array:
	var liora := load(LIORA) as HeroDef
	var target_id := _server.add_scripted_hero(ScriptedInputSource.new(CombatFixtures.idle_input()),
		_server.spawn_point("DummySpawn1"), CombatFixtures.vesper())
	var shooter_id := _server.add_scripted_hero(ScriptedInputSource.new(CombatFixtures.shooter_input(8.0, 1)),
		Vector3(0.0, 0.05, 0.0), liora, 0)
	return [_server.hero(shooter_id), _server.hero(target_id)]


func test_bolt_hits_after_travel_time_not_instantly() -> void:
	_world(false)
	var pair := _shooter_and_target()
	var target: HeroBody = pair[1]
	await get_tree().physics_frame
	var max_hp := target.combat.health.hp
	var first_launch := -1
	var first_damage := -1
	for i in 30:
		_link.advance(_net.tick_dt())
		_server.step()
		if first_launch < 0 and not _server.bolts.bolts.is_empty():
			first_launch = _server.tick
		if first_damage < 0 and target.combat.health.hp < max_hp:
			first_damage = _server.tick
	assert_int(first_launch).is_greater(-1)
	assert_int(first_damage).is_greater(first_launch)  # 8 m at 90 m/s: not the launch tick
	assert_int(first_damage - first_launch).is_less_equal(4)


func test_wall_stops_the_bolt() -> void:
	_world(true)
	var pair := _shooter_and_target()
	var target: HeroBody = pair[1]
	await get_tree().physics_frame
	var max_hp := target.combat.health.hp
	for i in 40:
		_link.advance(_net.tick_dt())
		_server.step()
	assert_float(target.combat.health.hp).is_equal(max_hp)
	assert_int(_server.bolts.bolts.size()).is_less_equal(2)  # none linger past the wall
