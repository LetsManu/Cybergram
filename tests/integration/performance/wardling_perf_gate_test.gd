extends GdUnitTestSuite
## Performance regression gate (owner plan Part 5, docs/performance.md).
## Timings on shared CI runners vary 2x run to run, so the gate checks what the
## optimisations guarantee (deterministic counters) plus one generous time
## ceiling that only a large regression can cross:
##   - Wardling navmesh snaps: at most SNAP_RATIO_MAX of moving Wardling ticks
##     run the full closest-point query (it was 100 %: ~80 % of the step);
##   - server tick: mean below TICK_MS_CEILING over a 5v5 bot run (budget at
##     30 Hz is 33.3 ms; measured ~7 ms on the dev container).

const DEF_PATH := "res://assets/data/match/map_front.tres"
const ROSTER := "res://assets/data/ai/bot_roster_slice.tres"
const HZ: int = 30
## Thresholds (rationale in docs/performance.md).
const SNAP_RATIO_MAX := 0.5
const TICK_MS_CEILING := 20.0
const SIM_S := 40


func test_five_v_five_bot_run_stays_within_the_perf_gate() -> void:
	var def := load(DEF_PATH) as MapDef
	var built := WardlingFixtures.slice_server(self, WardlingFixtures.rules(), true, def.match_rules, def)
	auto_free(built[3])
	var server: ServerWorld = built[0]
	server.setup_match(def, 1.0)
	var roster := load(ROSTER) as BotRosterDef
	var director := BotDirector.new()
	director.setup(server, roster, roster.profile("normal"), 7)
	assert_bool(await WardlingFixtures.await_nav(get_tree(), server, def)).is_true()
	director.fill(false)
	var t0 := Time.get_ticks_usec()
	var ticks := 0
	while ticks < SIM_S * HZ and not server.match_flow.is_over():
		server.step()
		ticks += 1
	var tick_ms := (Time.get_ticks_usec() - t0) / 1000.0 / maxf(ticks, 1)
	var w := server.wardlings
	var ratio := float(w.snaps) / maxf(w.moves, 1)
	print("[perf-gate] %d ticks, %d Wardlings, tick %.2f ms (ceiling %.1f), snaps %d / moves %d = %.2f (max %.2f)" % [
		ticks, w.wardlings.size(), tick_ms, TICK_MS_CEILING, w.snaps, w.moves, ratio, SNAP_RATIO_MAX])
	assert_int(w.moves).override_failure_message("no Wardling moved: the gate measured nothing").is_greater(1000)
	assert_float(ratio).is_less_equal(SNAP_RATIO_MAX)
	assert_float(tick_ms).is_less(TICK_MS_CEILING)


func test_segment_height_follows_the_path_and_refuses_off_segment_points() -> void:
	var a := Vector3(0, 1, 0)
	var b := Vector3(10, 3, 0)
	assert_float(WardlingWorld.segment_height(a, b, Vector3(5, 9, 0.5))).is_equal_approx(2.0, 0.001)
	assert_bool(is_nan(WardlingWorld.segment_height(a, b, Vector3(5, 0, 2.0)))).is_true()  # 2 m beside it
	assert_bool(is_nan(WardlingWorld.segment_height(a, b, Vector3(14, 0, 0)))).is_true()  # past the end


func test_hidden_wardling_props_stop_their_bone_attachments() -> void:
	if not WardlingRig.available(ModelPalette.TEAM_CONCORD):
		return
	var rig: WardlingRig = auto_free(WardlingRig.new())
	rig.setup(ModelPalette.TEAM_CONCORD)
	add_child(rig)
	rig.set_tier(1)
	rig.set_marks(1, false, false)  # someone's squad: the sash only
	assert_int(rig.active_attachments()).is_equal(1)
	rig.set_tier(3)
	rig.set_marks(0, false, true)  # tier III Vanguard Elite: plates, crest, crown, pennant, halo
	assert_int(rig.active_attachments()).is_greater(1)
