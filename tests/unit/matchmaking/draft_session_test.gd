extends GdUnitTestSuite
## W17-MM: 5v5 draft 1-2-2-2-2-1, team-unique heroes, timeouts, bots, dodge.

const T0 := 500.0
const HEROES: Array[StringName] = [&"hero_a", &"hero_b", &"hero_c", &"hero_d", &"hero_e", &"hero_f", &"hero_g"]
const A: Array = ["a0", "a1", "a2", "a3", "a4"]
const B: Array = ["b0", "b1", "b2", "b3", "b4"]


func _rules() -> MatchmakingRulesDef:
	return MatchmakingRulesDef.new()


func test_order_is_1_2_2_2_2_1() -> void:
	var d := DraftSession.new(A, B, HEROES, _rules(), T0, 1)
	var seen: Array = []
	var h := 0
	while d.state == DraftSession.State.PICKING:
		var pickers := d.current_pickers()
		seen.append([d.turn_team, pickers.size()])
		for s in pickers:
			assert_int(d.pick(s, d.legal_heroes(d.turn_team)[0], T0 + h)).is_equal(DraftSession.Err.OK)
		h += 1
	assert_array(seen).is_equal([[0, 1], [1, 2], [0, 2], [1, 2], [0, 2], [1, 1]])
	assert_int(d.picks.size()).is_equal(10)


func test_unique_per_team_but_shared_across_teams() -> void:
	var d := DraftSession.new(A, B, HEROES, _rules(), T0, 1)
	assert_int(d.pick("a0", &"hero_a", T0)).is_equal(DraftSession.Err.OK)
	assert_int(d.pick("b0", &"hero_a", T0)).is_equal(DraftSession.Err.OK)  # other team: allowed
	assert_int(d.pick("b1", &"hero_a", T0)).is_equal(DraftSession.Err.E_TAKEN)
	assert_int(d.pick("b1", &"hero_zzz", T0)).is_equal(DraftSession.Err.E_UNKNOWN_HERO)
	assert_int(d.pick("a1", &"hero_b", T0)).is_equal(DraftSession.Err.E_NOT_YOUR_TURN)


func test_timeout_picks_random_legal_hero_deterministically() -> void:
	var d1 := DraftSession.new(A, B, HEROES, _rules(), T0, 42)
	var d2 := DraftSession.new(A, B, HEROES, _rules(), T0, 42)
	d1.pick("a0", &"hero_a", T0)
	d2.pick("a0", &"hero_a", T0)
	d1.tick(T0 + 29.9)
	assert_bool(d1.picks.has("b0")).is_false()
	d1.tick(T0 + 30)
	d2.tick(T0 + 30)
	assert_bool(d1.picks.has("b0") and d1.picks.has("b1")).is_true()
	assert_str(String(d1.picks["b0"])).is_equal(String(d2.picks["b0"]))
	assert_bool(d1.picks["b0"] != d1.picks["b1"]).is_true()
	assert_array(d1.auto_picked).contains_exactly(["b0", "b1"])
	assert_int(d1.turn_team).is_equal(0)


func test_whole_draft_times_out() -> void:
	var d := DraftSession.new(A, B, HEROES, _rules(), T0, 7)
	assert_int(d.tick(T0 + 30 * 6)).is_equal(DraftSession.State.DONE)
	for t in 2:
		var hs := {}
		for s in d.teams[t]:
			assert_bool(HEROES.has(d.picks[s])).is_true()
			hs[d.picks[s]] = true
		assert_int(hs.size()).is_equal(5)
	assert_int(d.pick("a4", &"hero_a", T0 + 999)).is_equal(DraftSession.Err.E_CLOSED)


func test_bots_pick_at_once() -> void:
	var bots: Array = ["bot:1", "bot:2", "bot:3", "bot:4", "bot:5"]
	var d := DraftSession.new(A, bots, HEROES, _rules(), T0, 3)
	d.pick("a0", &"hero_a", T0)
	assert_bool(d.picks.has("bot:1") and d.picks.has("bot:2")).is_true()
	assert_int(d.turn_team).is_equal(0)
	assert_int(d.current_pickers().size()).is_equal(2)


func test_dodge_aborts() -> void:
	var d := DraftSession.new(A, B, HEROES, _rules(), T0, 3)
	d.dodge("b3")
	assert_int(d.state).is_equal(DraftSession.State.ABORTED)
	assert_str(d.dodger).is_equal("b3")
	assert_int(d.pick("a0", &"hero_a", T0)).is_equal(DraftSession.Err.E_CLOSED)


func test_hero_pool_reads_content_db() -> void:
	var db := ContentDB.from_ids({ContentDB.HERO: [&"hero_z", &"hero_y"]})
	assert_array(HeroPool.from_content_db(db)).is_equal([&"hero_y", &"hero_z"])
	assert_int(HeroPool.from_content_db().size()).is_greater_equal(5)
