extends GdUnitTestSuite
## Lag compensation: the server rewinds a target to the client's view tick
## (interpolated, clamped to the rewind window) before testing the shot.
## The target strafes +1 m on X every tick; the shot aims where it was at
## tick 5, 8 m ahead.

const STEP_M := 1.0
const NOW := 10
const REWIND := 6

var _server: ServerWorld


func _strafing_target(tracer: HitscanTracer) -> HeroBody:
	var link := LoopbackLink.new(NetFixtures.profile(0, 0, 0.0))
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(auto_free(vp))
	_server = ServerWorld.new()
	vp.add_child(_server)
	_server.setup(NetFixtures.net_config(), MovementDef.new(), CombatFixtures.range_scene(false),
		link.create_endpoint(1), CombatFixtures.vesper(),
		load("res://assets/data/match/match_rules_slice.tres") as MatchRulesDef)
	var h := _server.hero(_server.add_scripted_hero(ScriptedInputSource.new(CombatFixtures.idle_input()),
		Vector3.ZERO, CombatFixtures.vesper()))
	tracer.rewind_ticks = REWIND
	for t in range(1, NOW + 1):
		h.state.position = Vector3(t * STEP_M, 0.0, -8.0)
		tracer.record(t, [h])
	return h


func _shot_at_tick5(tracer: HitscanTracer, h: HeroBody, view_tick: int, alpha: float) -> bool:
	var targets: Array[HeroBody] = [h]
	var origin := Vector3(5.0 * STEP_M, 1.2, 0.0)
	return tracer.trace(null, origin, Vector3.FORWARD, 50.0, targets, view_tick, alpha).target != null


func test_shot_hits_where_the_client_saw_the_target() -> void:
	var tracer := HitscanTracer.new()
	var h := _strafing_target(tracer)
	assert_bool(_shot_at_tick5(tracer, h, 5, 0.0)).is_true()


func test_without_rewind_the_same_shot_misses() -> void:
	var tracer := HitscanTracer.new()
	var h := _strafing_target(tracer)
	assert_bool(_shot_at_tick5(tracer, h, 0, 0.0)).is_false()  # 0 = current pose (x = 10)


func test_alpha_interpolates_between_ticks() -> void:
	var tracer := HitscanTracer.new()
	var h := _strafing_target(tracer)
	# 80 % of the way from tick 4 (x=4) to 5 (x=5) is x=4.8, inside the 0.4 m
	# body radius of the 5.0 aim; 20 % (x=4.2) is outside it.
	assert_bool(_shot_at_tick5(tracer, h, 4, 0.8)).is_true()
	assert_bool(_shot_at_tick5(tracer, h, 4, 0.2)).is_false()
	# Tick 3 exactly (x=3) is 2 m off: miss.
	assert_bool(_shot_at_tick5(tracer, h, 3, 0.0)).is_false()


func test_rewind_is_clamped_to_the_window() -> void:
	var tracer := HitscanTracer.new()
	var h := _strafing_target(tracer)
	# Asks for tick 1 (x=1) but may rewind only to NOW - REWIND = 4 (x=4):
	# an aim at x=4 hits, proving the clamp, not the requested tick.
	var targets: Array[HeroBody] = [h]
	var hit := tracer.trace(null, Vector3(4.0, 1.2, 0.0), Vector3.FORWARD, 50.0, targets, 1, 0.0)
	assert_object(hit.target).is_not_null()
