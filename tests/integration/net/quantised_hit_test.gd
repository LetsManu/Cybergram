extends GdUnitTestSuite
## W16-NET: quantised hero positions (1/32 m) must not change hit results.
## The server rewinds its own exact pose history (lag compensation); the client
## aims at the decoded, quantised position it was shown. Aiming at the shown
## position plus an offset hits / misses exactly as aiming at the true one,
## for every offset clear of the body edge by more than the quantisation error.

const NOW := 10
const REWIND := 6
## Off-grid positions: the target never sits on a 1/32 m step.
const BASE := Vector3(3.0071, 0.013, -8.0193)

var _server: ServerWorld


func _target(tracer: HitscanTracer) -> HeroBody:
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
		h.state.position = BASE + Vector3(t * 1.013, 0.0, 0.0)
		tracer.record(t, [h])
	return h


## Where the client saw the target at `tick` after a v16 snapshot round trip.
func _shown(h: HeroBody, tick: int) -> Vector3:
	var s := SnapshotData.new()
	s.tick = tick
	var e := SnapshotFixtures.hero(h.net_id, BASE + Vector3(tick * 1.013, 0.0, 0.0))
	s.entities.append(e)
	return SnapshotCodec.decode(SnapshotCodec.encode(s)).entities[0].position


func _hit(tracer: HitscanTracer, h: HeroBody, aim: Vector3, view_tick: int) -> bool:
	var targets: Array[HeroBody] = [h]
	var origin := Vector3(aim.x, aim.y + 1.2, 0.0)
	return tracer.trace(null, origin, Vector3.FORWARD, 50.0, targets, view_tick, 0.0).target != null


func test_hit_results_unchanged_under_quantisation() -> void:
	var tracer := HitscanTracer.new()
	var h := _target(tracer)
	var view_tick := 5
	var truth := BASE + Vector3(view_tick * 1.013, 0.0, 0.0)
	var shown := _shown(h, view_tick)
	assert_float((shown - truth).length()).is_less(0.03)
	var hits := 0
	var compared := 0
	var x := -0.8
	while x <= 0.8:
		var off := Vector3(x, 0.0, 0.0)
		var exact := _hit(tracer, h, truth + off, view_tick)
		var quant := _hit(tracer, h, shown + off, view_tick)
		# Find the edge: compare only where the outcome is stable within +-3 cm.
		var stable := _hit(tracer, h, truth + off + Vector3(0.03, 0, 0), view_tick) == exact \
			and _hit(tracer, h, truth + off - Vector3(0.03, 0, 0), view_tick) == exact
		if stable:
			compared += 1
			assert_bool(quant).override_failure_message("offset %.2f: exact %s, quantised %s" % [x, exact, quant]).is_equal(exact)
			if exact:
				hits += 1
		x += 0.05
	assert_int(compared).is_greater(25)
	assert_int(hits).is_greater(5)
