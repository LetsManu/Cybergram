extends GdUnitTestSuite
## W17-MM: the whole phase-A pipeline as the front will drive it in phase B:
## queue -> tick -> ready check -> draft -> result -> ratings; plus a ranked
## pick-phase dodge (decline lockout, rating penalty, priority re-queue).

const T0 := 50_000.0
const NOW_UNIX := 1_800_000_000
const HEROES: Array[StringName] = [&"hero_a", &"hero_b", &"hero_c", &"hero_d", &"hero_e", &"hero_f", &"hero_g"]


static func _id(n: int) -> String:
	return "%032x" % n


func _setup() -> Array:
	var rules := MatchmakingRulesDef.new()
	rules.queues = MatchmakingRulesDef.standard_queues()
	var ratings := RatingService.new(MemoryRatingStore.new(), rules)
	var mm := Matchmaker.new(rules)
	for i in 10:
		var id := _id(i + 1)
		var e := ratings.entry(id, &"ranked")
		assert_int(mm.enqueue(&"ranked_5v5", [{"id": id, "rating": e.rating, "lanes": [&"fill"]}], T0).err) \
			.is_equal(Matchmaker.Err.OK)
	return [rules, ratings, mm]


func _team(p: Dictionary, side: int) -> Array:
	return p.teams[side].map(func(s: Dictionary) -> String: return s.id)


func test_full_ranked_flow() -> void:
	var s := _setup()
	var rules: MatchmakingRulesDef = s[0]
	var ratings: RatingService = s[1]
	var mm: Matchmaker = s[2]
	var p: Dictionary = mm.tick(T0)[0]
	var rc := ReadyCheck.new(Matchmaker.human_ids(p), T0, rules.ready_check_s)
	for id in Matchmaker.human_ids(p):
		rc.accept(id, T0 + 2)
	assert_int(rc.state).is_equal(ReadyCheck.State.ACCEPTED)
	mm.confirm(p)
	var d := DraftSession.new(_team(p, 0), _team(p, 1), HEROES, rules, T0 + 3, p.match_id)
	assert_int(d.tick(T0 + 3 + rules.pick_turn_s * rules.draft_order.size())).is_equal(DraftSession.State.DONE)
	var res := ratings.apply_result(&"ranked", _team(p, 0), _team(p, 1), 0, NOW_UNIX)
	assert_int(res.size()).is_equal(10)
	for id in _team(p, 0):
		assert_float(res[id].delta).is_greater(0.0)
	for id in _team(p, 1):
		assert_float(res[id].delta).is_less(0.0)
	assert_int(ratings.calibration_left(_team(p, 0)[0])).is_equal(rules.calibration_games - 1)


func test_ranked_dodge_in_pick_phase() -> void:
	var s := _setup()
	var rules: MatchmakingRulesDef = s[0]
	var ratings: RatingService = s[1]
	var mm: Matchmaker = s[2]
	var p: Dictionary = mm.tick(T0)[0]
	mm.confirm(p)
	var d := DraftSession.new(_team(p, 0), _team(p, 1), HEROES, rules, T0 + 3, 1)
	var dodger: String = _team(p, 1)[2]
	d.dodge(dodger)
	assert_int(d.state).is_equal(DraftSession.State.ABORTED)
	var res := mm.resolve_ready_check(p, [d.dodger], T0 + 5)
	assert_float(ratings.apply_dodge_penalty(d.dodger, &"ranked", NOW_UNIX)).is_equal(-rules.dodge_rating_penalty)
	assert_int(res.requeued.size()).is_equal(9)
	assert_bool(mm.lockouts.is_locked(dodger, T0 + 6, true)).is_true()
	assert_int(mm.queue_info(&"ranked_5v5").players).is_equal(9)


func test_void_after_remake() -> void:
	var s := _setup()
	var rules: MatchmakingRulesDef = s[0]
	var ratings: RatingService = s[1]
	var mm: Matchmaker = s[2]
	var p: Dictionary = mm.tick(T0)[0]
	mm.confirm(p)
	var vote := RemakeVote.new(_team(p, 0), T0 + 60, rules)
	vote.mark_absent(_team(p, 0)[4])
	vote.start(_team(p, 0)[0], T0 + 120)
	for i in range(1, 4):
		vote.vote(_team(p, 0)[i], true, T0 + 121)
	assert_int(vote.state).is_equal(RemakeVote.State.PASSED)
	var res := ratings.apply_result(&"ranked", _team(p, 0), _team(p, 1), 1, NOW_UNIX, [], true)
	assert_dict(res).is_empty()
	assert_int(ratings.calibration_left(_team(p, 0)[0])).is_equal(rules.calibration_games)
