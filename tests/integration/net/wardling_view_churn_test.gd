extends GdUnitTestSuite
## Regression (PR #29, matchmaking e2e crash): on Shardline Front with 24
## Garrison Sentinels plus Vanguard waves, over a link with latency and loss,
## a new Wardling the byte budget defers against an older acknowledged baseline
## drops out of one snapshot. The presenter freed and rebuilt its rigged model
## every time, the AnimationTree setup calls flooded the message queue and the
## client crashed. Each Wardling must get exactly one view.
var _server: ServerWorld
var _client: ClientWorld
var _link: LoopbackLink
var _net: NetConfig
## Keeps the RefCounted WardlingDirector alive.
var _built: Array = []

func _tick(n: int = 1) -> void:
	for i in n:
		_link.advance(_net.tick_dt())
		_client.session.poll()
		_client.tick()
		_server.step()

func test_each_wardling_gets_one_view_over_a_lossy_link() -> void:
	var def := load("res://assets/data/match/map_front.tres") as MapDef
	_net = NetFixtures.net_config()
	_link = LoopbackLink.new(NetFixtures.profile(80, 10, 0.02))
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(auto_free(vp))
	_server = ServerWorld.new()
	vp.add_child(_server)
	var movement := load("res://assets/data/movement/movement_default.tres") as MovementDef
	_server.setup(_net, movement, def.scene, _link.create_endpoint(1), CombatFixtures.vesper(),
		load("res://assets/data/match/match_rules_front.tres") as MatchRulesDef)
	_server.setup_objectives(def)
	_server.setup_match(def, 1.0)
	_server.enable_wardlings(def, WardlingFixtures.rules(), load(WardlingFixtures.PICKET) as WardlingDef)
	var dir := WardlingDirector.new()
	dir.attach(_server)
	_built = [dir]
	var inp := WardlingFixtures.Owner.new()
	inp.server = _server
	# The client in its own World3D too: the Shardline Front navmesh must not
	# stay in the default world's navigation map for later suites (slice_walk_test).
	var cvp := SubViewport.new()
	cvp.own_world_3d = true
	cvp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(auto_free(cvp))
	_client = ClientWorld.new()
	cvp.add_child(_client)
	_client.setup(_net, movement, LookSettings.new(), def.scene, _link.create_endpoint(2), inp, CombatFixtures.vesper())
	_client.setup_objectives(def)
	await WardlingFixtures.await_nav(get_tree(), _server, def)
	var created := [0]
	_client.wardlings.child_entered_tree.connect(func(n: Node) -> void: if n is WardlingView: created[0] += 1)
	var counts := []
	for i in 30 * 8:
		_tick()
		if i % 30 == 0:
			counts.append([_server.wardlings.wardlings.size(), _client.wardlings._views.size(), created[0]])
	var last: Array = counts[-1]
	assert_int(int(last[0])).is_greater(24)  # Sentinels + waves on the server
	assert_int(int(last[1])).is_equal(int(last[0]))  # one view per Wardling
	assert_int(int(last[2])).is_equal(int(last[1]))  # no view was built twice
