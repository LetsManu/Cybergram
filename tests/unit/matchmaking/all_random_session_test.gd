extends GdUnitTestSuite
## W17-MM: 3v3 All Random deal, rerolls, shared bench (incl. running dry),
## teammate swaps, lock.

const T0 := 0.0
const HEROES: Array[StringName] = [&"hero_a", &"hero_b", &"hero_c", &"hero_d", &"hero_e", &"hero_f", &"hero_g"]
const A: Array = ["a0", "a1", "a2"]
const B: Array = ["b0", "b1", "b2"]


func _rules(rerolls: int = 1) -> MatchmakingRulesDef:
	var r := MatchmakingRulesDef.new()
	r.rerolls_per_player = rerolls
	return r


func _team_heroes(s: AllRandomSession, t: int) -> Array:
	return s.teams[t].map(func(x: String) -> StringName: return s.hero_of[x])


func test_deal_is_team_unique_and_seeded() -> void:
	var s1 := AllRandomSession.new(A, B, HEROES, _rules(), T0, 9)
	var s2 := AllRandomSession.new(A, B, HEROES, _rules(), T0, 9)
	for t in 2:
		var hs := _team_heroes(s1, t)
		var uniq := {}
		for h in hs:
			uniq[h] = true
		assert_int(uniq.size()).is_equal(3)
	assert_dict(s1.hero_of).is_equal(s2.hero_of)


func test_reroll_benches_old_hero() -> void:
	var s := AllRandomSession.new(A, B, HEROES, _rules(), T0, 9)
	var old: StringName = s.hero_of["a0"]
	assert_int(s.reroll("a0", 1)).is_equal(AllRandomSession.Err.OK)
	assert_array(s.bench[0]).is_equal([old])
	assert_bool(s.hero_of["a0"] != old).is_true()
	assert_bool(_team_heroes(s, 0).has(old)).is_false()
	assert_int(s.reroll("a0", 2)).is_equal(AllRandomSession.Err.E_NO_REROLLS)
	assert_array(s.bench[1]).is_empty()


func test_reroll_bench_runs_dry() -> void:
	var s := AllRandomSession.new(A, B, HEROES, _rules(3), T0, 9)
	# 7 heroes, 3 held: 4 rerolls empty the draw pool.
	for i in 4:
		assert_int(s.reroll(A[i % 3], 1)).is_equal(AllRandomSession.Err.OK)
	assert_array(s.drawable(0)).is_empty()
	assert_int(s.bench[0].size()).is_equal(4)
	var left: int = s.rerolls_left["a1"]
	assert_int(s.reroll("a1", 2)).is_equal(AllRandomSession.Err.E_EMPTY)
	assert_int(s.rerolls_left["a1"]).is_equal(left)  # not used up


func test_take_from_bench() -> void:
	var s := AllRandomSession.new(A, B, HEROES, _rules(), T0, 9)
	var benched: StringName = s.hero_of["a0"]
	s.reroll("a0", 1)
	var mine: StringName = s.hero_of["a1"]
	assert_int(s.take_from_bench("a1", benched, 2)).is_equal(AllRandomSession.Err.OK)
	assert_str(String(s.hero_of["a1"])).is_equal(String(benched))
	assert_array(s.bench[0]).is_equal([mine])
	assert_int(s.take_from_bench("b0", mine, 3)).is_equal(AllRandomSession.Err.E_NOT_ON_BENCH)


func test_swap_request_and_expiry() -> void:
	var s := AllRandomSession.new(A, B, HEROES, _rules(), T0, 9)
	var h0: StringName = s.hero_of["a0"]
	var h1: StringName = s.hero_of["a1"]
	assert_int(s.request_swap("a0", "b0", 1)).is_equal(AllRandomSession.Err.E_NOT_TEAMMATE)
	assert_int(s.request_swap("a0", "a1", 1)).is_equal(AllRandomSession.Err.OK)
	assert_int(s.accept_swap("a1", "a0", 2)).is_equal(AllRandomSession.Err.OK)
	assert_str(String(s.hero_of["a0"])).is_equal(String(h1))
	assert_str(String(s.hero_of["a1"])).is_equal(String(h0))
	assert_int(s.accept_swap("a1", "a0", 3)).is_equal(AllRandomSession.Err.E_NO_REQUEST)
	s.request_swap("a2", "a0", 5)
	assert_int(s.accept_swap("a0", "a2", 5 + 10.1)).is_equal(AllRandomSession.Err.E_NO_REQUEST)


func test_locks_at_deadline_and_bots_never_reroll() -> void:
	var s := AllRandomSession.new(A, ["bot:1", "b1", "b2"], HEROES, _rules(), T0, 9)
	assert_int(s.reroll("bot:1", 1)).is_equal(AllRandomSession.Err.E_NO_REROLLS)
	assert_int(s.tick(45)).is_equal(AllRandomSession.State.LOCKED)
	assert_int(s.reroll("a0", 46)).is_equal(AllRandomSession.Err.E_CLOSED)
