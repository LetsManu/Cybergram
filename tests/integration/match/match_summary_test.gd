extends GdUnitTestSuite
## W10-W4: the server counts damage / kills during the match and, when it ends,
## sends PLAYER_STAT events; the client assembles ClientWorld.match_summary.

const MAP_PATH := "res://assets/data/match/map_slice_lane.tres"
const C := MapDef.TEAM_CONCORD
const S := MatchStats.Stat


func test_match_end_summary_reaches_the_client() -> void:
	var def := load(MAP_PATH) as MapDef
	var net := NetFixtures.net_config()
	var link := LoopbackLink.new(NetFixtures.profile(0, 0, 0.0))
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(auto_free(vp))
	var server := ServerWorld.new()
	vp.add_child(server)
	var movement := load("res://assets/data/movement/movement_default.tres") as MovementDef
	server.setup(net, movement, def.scene, link.create_endpoint(1), CombatFixtures.vesper(), null)
	server.setup_objectives(def)
	server.setup_match(def, 1.0)
	var client: ClientWorld = auto_free(ClientWorld.new())
	add_child(client)
	client.setup(net, movement, LookSettings.new(), def.scene, link.create_endpoint(2),
		ScriptedInputSource.new(CombatFixtures.idle_input()), CombatFixtures.vesper())
	client.setup_objectives(def)
	var got: Array = []
	client.match_summary_received.connect(func(rows: Dictionary) -> void: got.append(rows))
	for i in 10:
		link.advance(net.tick_dt())
		client.session.poll()
		client.tick()
		server.step()
	var id := client.session.own_net_id
	assert_int(id).is_greater(0)
	# Counters as the combat signals would feed them, then the Uplink falls.
	server.stats.record_damage(id, 999, 120.0, server.tick)
	server.stats.record_objective(id, 50.0)
	server.match_flow.on_uplink_destroyed(1 - C)
	for i in 30:
		link.advance(net.tick_dt())
		client.session.poll()
		client.tick()
		server.step()
		await get_tree().process_frame
	assert_int(got.size()).is_equal(1)
	var row: Dictionary = client.match_summary[id]
	assert_float(row[S.HERO_DAMAGE]).is_equal_approx(120.0, 1e-3)
	assert_float(row[S.OBJECTIVE_DAMAGE]).is_equal_approx(50.0, 1e-3)
	assert_float(row[S.TEAM]).is_equal(float(client.own_team()))
	assert_float(row[S.LEVEL]).is_greater_equal(1.0)
