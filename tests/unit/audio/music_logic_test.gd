extends GdUnitTestSuite
## W21-A1: MusicLogic transitions, intensity / heat, stem thresholds and the
## bar-synced crossfade; MusicDirector deck switching and the headless no-op.

func _def() -> MusicDef:
	return load("res://assets/data/audio/music.tres") as MusicDef


func test_phase_to_state_table() -> void:
	assert_int(MusicLogic.state_for_phase(MatchRules.Phase.DEPLOY)).is_equal(MusicLogic.State.MATCH_EARLY)
	assert_int(MusicLogic.state_for_phase(MatchRules.Phase.SKIRMISH)).is_equal(MusicLogic.State.MATCH_EARLY)
	assert_int(MusicLogic.state_for_phase(MatchRules.Phase.DROUGHT)).is_equal(MusicLogic.State.MATCH_EARLY)
	assert_int(MusicLogic.state_for_phase(MatchRules.Phase.SURGE_I)).is_equal(MusicLogic.State.MATCH_LATE)
	assert_int(MusicLogic.state_for_phase(MatchRules.Phase.SURGE_II)).is_equal(MusicLogic.State.MATCH_LATE)
	assert_int(MusicLogic.state_for_phase(MatchRules.Phase.SUDDEN_DEATH)).is_equal(MusicLogic.State.SUDDEN_DEATH)
	assert_int(MusicLogic.state_for_phase(MatchRules.Phase.END)).is_equal(MusicLogic.State.NONE)
	assert_int(MusicLogic.state_for_end(1, 1)).is_equal(MusicLogic.State.VICTORY)
	assert_int(MusicLogic.state_for_end(-1, 1)).is_equal(MusicLogic.State.DEFEAT)


func test_heat_raises_intensity_and_decays_over_six_seconds() -> void:
	var m := MusicLogic.new(_def())
	m.set_phase(MatchRules.Phase.SKIRMISH)
	var base := m.intensity
	m.add_shot(40.0)  # outside 25 m: no heat
	assert_float(m.intensity).is_equal(base)
	for i in 10:
		m.add_shot(5.0)
	assert_float(m.heat).is_equal_approx(0.8, 0.0001)
	assert_float(m.intensity).is_greater(base)
	for i in 60:
		m.step(0.1)
	assert_float(m.heat).is_equal(0.0)
	assert_float(m.intensity).is_equal_approx(base, 0.0001)


func test_drums_above_half_lead_above_point_eight() -> void:
	var m := MusicLogic.new(_def())
	m.base = 0.4
	m.step(0.0)
	assert_array(Array(m.stem_targets())).is_equal([1.0, 1.0, 0.0, 0.0])
	m.base = 0.6
	m.step(0.0)
	assert_array(Array(m.stem_targets())).is_equal([1.0, 1.0, 1.0, 0.0])
	m.base = 0.85
	m.step(0.0)
	assert_array(Array(m.stem_targets())).is_equal([1.0, 1.0, 1.0, 1.0])


func test_glide_is_frame_rate_independent() -> void:
	var m := MusicLogic.new(_def())
	var target := PackedFloat32Array([1.0, 1.0, 1.0, 1.0])
	var a := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var b := a.duplicate()
	for i in 10:
		a = m.glide(a, target, 0.05)
	for i in 50:
		b = m.glide(b, target, 0.01)
	assert_float(a[2]).is_equal_approx(b[2], 0.0001)


func test_crossfade_is_bar_synced_and_two_to_four_seconds() -> void:
	var m := MusicLogic.new(_def())
	var plan := m.crossfade_plan(1.0, 120.0, 4)  # bar = 2 s
	assert_float(plan.x).is_equal_approx(1.0, 0.0001)
	assert_float(plan.y).is_equal_approx(2.0, 0.0001)
	plan = m.crossfade_plan(0.0, 100.0, 4)  # bar = 2.4 s, on the line
	assert_float(plan.x).is_equal_approx(0.0, 0.0001)
	assert_float(plan.y).is_between(2.0, 4.0)
	plan = m.crossfade_plan(3.0, 40.0, 4)  # bar = 6 s: fade capped at 4
	assert_float(plan.y).is_equal_approx(4.0, 0.0001)


func test_director_is_a_noop_headless() -> void:
	var d := MusicDirector.new(_def(), true)
	add_child(auto_free(d))
	d.set_state(MusicLogic.State.MENU)
	assert_int(d.state).is_equal(MusicLogic.State.NONE)
	assert_bool(d.is_processing()).is_false()


func test_director_switches_decks_and_reduce_music_stops_match_loops() -> void:
	var d := MusicDirector.new(_def(), false)
	var gs := GameSettings.new()
	d.settings = gs
	add_child(auto_free(d))
	d.set_state(MusicLogic.State.MENU)
	d._process(0.01)
	assert_int(d.active_deck_state()).is_equal(MusicLogic.State.MENU)
	gs.reduce_music = true
	d.set_state(MusicLogic.State.MATCH_EARLY)
	assert_int(d.state).is_equal(MusicLogic.State.MATCH_EARLY)
	assert_int(d.active_deck_state()).is_equal(MusicLogic.State.NONE)
	gs.reduce_music = false
	d.set_state(MusicLogic.State.MATCH_LATE)
	d._process(5.0)
	assert_int(d.active_deck_state()).is_equal(MusicLogic.State.MATCH_LATE)
	assert_bool(d._decks[d._active].stream is AudioStreamSynchronized).is_true()
