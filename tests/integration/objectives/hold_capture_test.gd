extends GdUnitTestSuite
## E7 integration: a scripted Concord hero walks into the neutral Mid (The
## Spindle, Hold 60 s) on the slice map through the real server tick, captures it
## alone in the GDD time (Δ 1.0 -> M 0.64 -> 60 / 0.64 = 93.75 s, ±10%), the
## ownership replicates to the client and the Concord front moves to Scrap Bazaar.

const HZ: int = 30
const MAP_PATH := "res://assets/data/match/map_slice_lane.tres"

var _server: ServerWorld
var _client: ClientWorld
var _link: LoopbackLink
var _net: NetConfig


func _tick() -> void:
	_link.advance(_net.tick_dt())
	_client.session.poll()
	_client.tick()
	_server.step()


func test_scripted_hero_captures_neutral_mid_and_it_replicates() -> void:
	var def := load(MAP_PATH) as MapDef
	var rules := load("res://assets/data/match/match_rules_slice.tres") as MatchRulesDef
	_net = NetFixtures.net_config()
	_link = LoopbackLink.new(NetFixtures.profile(0, 0, 0.0))
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(auto_free(vp))
	_server = ServerWorld.new()
	vp.add_child(_server)
	var movement := load("res://assets/data/movement/movement_default.tres") as MovementDef
	_server.setup(_net, movement, def.scene, _link.create_endpoint(1), CombatFixtures.vesper(), rules)
	_server.setup_objectives(def)
	var mid := _server.objectives.find(&"s_mid")
	# Walker: 10 m outside the Mid zone on the Concord side, walking -Z.
	var walk := ScriptedInputDef.new()
	walk.segments = PackedVector2Array([Vector2(0.0, 1.0)])
	var start := mid.def.position + Vector3(0.0, 0.05, mid.def.zone_radius + 10.0)
	var walker := _server.add_scripted_hero(ScriptedInputSource.new(walk), start, CombatFixtures.vesper(),
		ServerWorld.TEAM_PLAYERS)
	var idle := ScriptedInputDef.new()
	idle.segments = PackedVector2Array([Vector2.ZERO])
	_client = auto_free(ClientWorld.new())
	add_child(_client)
	_client.setup(_net, movement, LookSettings.new(), def.scene, _link.create_endpoint(2),
		ScriptedInputSource.new(idle), CombatFixtures.vesper())
	_client.setup_objectives(def)
	var client_flips: Array = []
	_client.hardpoint_owner_changed.connect(func(i: int, o: int, n: int) -> void: client_flips.append([i, o, n]))
	var server_events: Array = []
	_server.objective_event.connect(func(ev: ObjectiveEvent) -> void: server_events.append(ev))
	await get_tree().physics_frame
	for i in 5:
		_tick()
	assert_int(_client.hardpoints.size()).is_equal(5)
	assert_int(_client.fronts[MapDef.TEAM_CONCORD]).is_equal(2)
	assert_int(_client.hardpoints[2].owner).is_equal(MapDef.TEAM_NEUTRAL)
	var entered := -1
	var flipped := -1
	for i in HZ * 150:
		var h := _server.hero(walker)
		if entered < 0 and mid.presence[MapDef.TEAM_CONCORD] > 0.0:
			entered = _server.tick
		if h.state.position.distance_to(mid.def.position) < mid.def.zone_radius * 0.5:
			walk.segments = PackedVector2Array([Vector2.ZERO])  # stand on the dais
		_tick()
		if mid.owner == MapDef.TEAM_CONCORD:
			flipped = _server.tick
			break
	assert_int(entered).is_greater_equal(0)
	assert_int(flipped).is_greater(entered)
	var expected := 60.0 / (0.4 + 0.24 * 1.0)
	var took := float(flipped - entered) / HZ
	print("hold capture: %.2f s (GDD %.2f s)" % [took, expected])
	assert_float(took).is_between(expected * 0.9, expected * 1.1)
	# Server events: one FLIP with the walker as participant.
	assert_int(server_events.size()).is_equal(1)
	assert_int(server_events[0].new_team).is_equal(MapDef.TEAM_CONCORD)
	assert_array(Array(server_events[0].participants)).contains([walker])
	# Replication to the client, and the front moves to Scrap Bazaar (index 3).
	for i in 5:
		_tick()
	assert_int(_client.hardpoints[2].owner).is_equal(MapDef.TEAM_CONCORD)
	assert_array(client_flips).is_equal([[2, MapDef.TEAM_NEUTRAL, MapDef.TEAM_CONCORD]])
	assert_int(_client.fronts[MapDef.TEAM_CONCORD]).is_equal(3)
	assert_bool(_client.hardpoints[3].locked[MapDef.TEAM_CONCORD]).is_false()
