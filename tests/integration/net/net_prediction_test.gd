extends GdUnitTestSuite
## Client connected through loopback moves a hero; prediction and
## reconciliation (ADR-0002 §5, architecture.md §13 integration row).

const MOVE_TICKS: int = 300      # 10 s at 30 Hz
const SETTLE_TICKS: int = 30     # idle ticks so in-flight packets land

var _server: ServerWorld
var _client: ClientWorld
var _link: LoopbackLink
var _net: NetConfig


func _build(profile: NetSimProfile) -> void:
	_net = NetFixtures.net_config()
	var movement := MovementDef.new()
	var course := NetFixtures.course_scene()
	_link = LoopbackLink.new(profile)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(auto_free(vp))
	_server = ServerWorld.new()
	vp.add_child(_server)
	_server.setup(_net, movement, course, _link.create_endpoint(1))
	var dummy_def := ScriptedInputDef.new()
	dummy_def.segments = PackedVector2Array([Vector2(1, 0), Vector2(-1, 0)])
	_server.add_scripted_hero(ScriptedInputSource.new(dummy_def), _server.spawn_point("DummySpawn1"))
	_client = auto_free(ClientWorld.new())
	add_child(_client)
	_client.setup(_net, movement, LookSettings.new(), course, _link.create_endpoint(2),
		ScriptedInputSource.new(NetFixtures.walk_pattern()))


func _tick(n: int, move: bool = true) -> void:
	for i in n:
		_link.advance(_net.tick_dt())
		_client.session.poll()
		if move:
			_client.tick()
		_server.step()


func _own_server_hero() -> HeroBody:
	return _server.hero(_client.session.own_net_id)


func test_zero_latency_prediction_error_stays_below_epsilon() -> void:
	_build(NetFixtures.profile(0, 0, 0.0))
	await get_tree().physics_frame
	var start := _server.spawn_point("PlayerSpawn")
	_tick(MOVE_TICKS)
	var pr := _client.predictor
	assert_object(pr).is_not_null()
	assert_float(_own_server_hero().state.position.distance_to(start)).is_greater(5.0)
	assert_int(pr.reconciled_snapshots).is_greater(MOVE_TICKS - 5)
	assert_float(pr.max_error_m).is_less(_net.reconcile_epsilon_m)
	assert_int(pr.corrections).is_equal(0)
	assert_int(_client.view_count()).is_equal(1)  # the dummy, interpolated


func test_100ms_2pct_loss_reconciliation_stays_bounded() -> void:
	# 100 ms each way (200 ms RTT) +-10 ms jitter, 2% loss: stricter than the
	# ADR-0002 criterion (100 ms RTT).
	_build(NetFixtures.profile(100, 10, 0.02))
	await get_tree().physics_frame
	var start := _server.spawn_point("PlayerSpawn")
	_tick(MOVE_TICKS)
	_tick(SETTLE_TICKS, false)
	var pr := _client.predictor
	var server_hero := _own_server_hero()
	assert_float(server_hero.state.position.distance_to(start)).is_greater(5.0)
	assert_int(pr.reconciled_snapshots).is_greater(MOVE_TICKS / 2)
	# ADR-0002 validation: < 1 correction per 10 s of movement.
	assert_int(pr.corrections).is_less_equal(MOVE_TICKS / (_net.tick_rate_hz * 10))
	assert_float(pr.max_error_m).is_less(0.5)
	# After the stream settles, client and server agree.
	assert_float(_client.body.state.position.distance_to(server_hero.state.position)).is_less(_net.reconcile_epsilon_m)


func test_divergence_is_corrected_by_replay() -> void:
	_build(NetFixtures.profile(50, 0, 0.0))
	await get_tree().physics_frame
	_tick(60)
	# Shove the server hero: the client mispredicts and must reconcile.
	var h := _own_server_hero()
	h.state.position += Vector3(1.5, 0.0, 0.0)
	h.motor.restore(h.state)
	_tick(60)
	_tick(SETTLE_TICKS, false)
	var pr := _client.predictor
	assert_int(pr.corrections).is_greater_equal(1)
	assert_float(_client.body.state.position.distance_to(h.state.position)).is_less(_net.reconcile_epsilon_m)


func test_remote_view_tracks_server_with_interp_delay() -> void:
	_build(NetFixtures.profile(0, 0, 0.0))
	await get_tree().physics_frame
	_tick(45)
	var dummy := _server.hero(1)
	_client.render(_net.tick_dt())  # one frame-tick advances the server-tick estimate
	var view := _client.view(dummy.net_id)
	assert_object(view).is_not_null()
	# Rendered interp_delay ticks behind the newest snapshot, which itself trails
	# the server by one tick (client polls before the server steps): at most
	# (delay + 1) ticks of travel at run speed, plus float tolerance.
	var max_lag := MovementDef.new().base_move_speed * (_net.interp_delay_ticks + 1) * _net.tick_dt()
	var lag := view.position.distance_to(dummy.state.position)
	assert_float(lag).is_less_equal(max_lag + 1e-3)
	assert_float(lag).is_greater(0.0)  # it really is delayed, not snapped to the server
