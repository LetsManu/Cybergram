extends GdUnitTestSuite
## Online slots: the first player gets a fresh hero on team 0; a second player
## takes over a scripted (bot) hero on the team with fewer humans, matching
## the picked hero; when that player leaves, the hero is released to a driver.

var _net: NetConfig
var _link: LoopbackLink
var _server: ServerWorld


func _client(peer: int, hero: HeroDef, scene: PackedScene) -> ClientWorld:
	var c := ClientWorld.new()
	add_child(auto_free(c))
	c.setup(_net, MovementDef.new(), LookSettings.new(), scene, _link.create_endpoint(peer),
		ScriptedInputSource.new(CombatFixtures.idle_input()), hero)
	return c


func _tick(clients: Array, n: int) -> void:
	for i in n:
		_link.advance(_net.tick_dt())
		for c: ClientWorld in clients:
			c.session.poll()
			c.tick()
		_server.step()


func test_second_player_takes_over_a_bot_and_leaving_releases_it() -> void:
	_net = NetFixtures.net_config()
	_link = LoopbackLink.new(NetFixtures.profile(0, 0, 0.0))
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(auto_free(vp))
	_server = ServerWorld.new()
	vp.add_child(_server)
	var scene := CombatFixtures.range_scene(false)
	var vesper := load("res://assets/data/heroes/hero_vesper_loom.tres") as HeroDef
	var brannoc := load("res://assets/data/heroes/hero_brannoc.tres") as HeroDef
	_server.setup(_net, MovementDef.new(), scene, _link.create_endpoint(1), vesper,
		load("res://assets/data/match/match_rules_slice.tres") as MatchRulesDef)
	# "Bots" on team 1: a Vesper and a Brannoc.
	var idle := CombatFixtures.idle_input()
	_server.add_scripted_hero(ScriptedInputSource.new(idle), _server.spawn_point("DummySpawn1"), vesper, 1)
	var bot_brannoc := _server.add_scripted_hero(ScriptedInputSource.new(idle),
		_server.spawn_point("DummySpawn2"), brannoc, 1)
	var taken: Array[int] = []
	var released: Array[int] = []
	_server.controller_taken.connect(func(id: int) -> void: taken.append(id))
	_server.controller_released.connect(func(id: int) -> void: released.append(id))
	await get_tree().physics_frame
	var c1 := _client(2, vesper, scene)
	_tick([c1], 6)
	var c2 := _client(3, brannoc, scene)
	_tick([c1, c2], 6)
	assert_bool(c1.session.is_welcomed and c2.session.is_welcomed).is_true()
	# Player 1: a fresh hero on team 0. Player 2: the Brannoc bot on team 1.
	assert_int(_server.hero(c1.session.own_net_id).combat.team).is_equal(0)
	assert_int(c2.session.own_net_id).is_equal(bot_brannoc)
	assert_array(taken).contains_exactly([bot_brannoc])
	# Player 2 leaves: its hero is released for a bot to drive.
	_server.on_peer_left(3)
	assert_array(released).contains_exactly([bot_brannoc])
	assert_bool(_server.session.clients.has(3)).is_false()
