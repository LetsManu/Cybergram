extends GdUnitTestSuite
## W17-MM: Matchmaker forming, balance, premades, ranked party gap, search
## window, bot fill (never ranked), ready-check failure and re-queue,
## lockouts, wait estimate. Deterministic: injected time, no randomness.

const T0 := 10_000.0


func _rules() -> MatchmakingRulesDef:
	var r := MatchmakingRulesDef.new()
	r.queues = MatchmakingRulesDef.standard_queues()
	return r


static func _m(id: String, rating: float, lanes: Array = [&"fill"]) -> Dictionary:
	return {"id": id, "rating": rating, "lanes": lanes}


func _solos(mm: Matchmaker, q: StringName, prefix: String, ratings: Array, now: float) -> void:
	for i in ratings.size():
		assert_int(mm.enqueue(q, [_m("%s%d" % [prefix, i], ratings[i])], now).err).is_equal(Matchmaker.Err.OK)


static func _team_ids(p: Dictionary, side: int) -> Array:
	return p.teams[side].map(func(s: Dictionary) -> String: return s.id)


static func _team_sum(p: Dictionary, side: int) -> float:
	var s := 0.0
	for seat in p.teams[side]:
		s += float(seat.rating)
	return s


func test_ten_solos_form_a_balanced_match() -> void:
	var mm := Matchmaker.new(_rules())
	_solos(mm, &"normal_5v5", "p", [1500, 1510, 1520, 1530, 1540, 1550, 1560, 1570, 1580, 1590], T0)
	assert_int(mm.queue_info(&"normal_5v5").players).is_equal(10)
	var ps := mm.tick(T0)
	assert_int(ps.size()).is_equal(1)
	var p := ps[0]
	assert_int(p.teams[0].size()).is_equal(5)
	assert_int(p.teams[1].size()).is_equal(5)
	assert_int(p.bots).is_equal(0)
	assert_bool(p.rated).is_true()
	assert_float(absf(_team_sum(p, 0) - _team_sum(p, 1))).is_less_equal(10.0)
	assert_int(mm.queue_info(&"normal_5v5").players).is_equal(0)


func test_not_enough_players_waits() -> void:
	var mm := Matchmaker.new(_rules())
	_solos(mm, &"ranked_5v5", "p", [1500, 1500, 1500, 1500, 1500, 1500, 1500, 1500, 1500], T0)
	assert_array(mm.tick(T0 + 10)).is_empty()


func test_search_window_widens_over_time() -> void:
	var mm := Matchmaker.new(_rules())
	# Five at 1500, five at 1800: 300 apart, base window 100, +5/s.
	_solos(mm, &"ranked_5v5", "lo", [1500, 1500, 1500, 1500, 1500], T0)
	_solos(mm, &"ranked_5v5", "hi", [1800, 1800, 1800, 1800, 1800], T0)
	assert_array(mm.tick(T0 + 39)).is_empty()  # window 295
	assert_int(mm.tick(T0 + 40).size()).is_equal(1)  # window 300


func test_premades_meet_premades() -> void:
	var mm := Matchmaker.new(_rules())
	var five_a: Array = []
	var five_b: Array = []
	for i in 5:
		five_a.append(_m("a%d" % i, 1500))
		five_b.append(_m("b%d" % i, 1500))
	assert_int(mm.enqueue(&"normal_5v5", five_a, T0).err).is_equal(Matchmaker.Err.OK)
	_solos(mm, &"normal_5v5", "s", [1500, 1500, 1500, 1500, 1500], T0 + 1)
	assert_int(mm.enqueue(&"normal_5v5", five_b, T0 + 2).err).is_equal(Matchmaker.Err.OK)
	var p := mm.tick(T0 + 3)[0]
	assert_array(_team_ids(p, 0)).is_equal(["a0", "a1", "a2", "a3", "a4"])
	assert_array(_team_ids(p, 1)).is_equal(["b0", "b1", "b2", "b3", "b4"])
	assert_int(mm.queue_info(&"normal_5v5").players).is_equal(5)


func test_duo_vs_duo_balance() -> void:
	var mm := Matchmaker.new(_rules())
	mm.enqueue(&"normal_5v5", [_m("d1", 1500), _m("d2", 1500)], T0)
	mm.enqueue(&"normal_5v5", [_m("e1", 1500), _m("e2", 1500)], T0)
	_solos(mm, &"normal_5v5", "s", [1500, 1500, 1500, 1500, 1500, 1500], T0)
	var p := mm.tick(T0)[0]
	var a := _team_ids(p, 0)
	assert_bool(a.has("d1") and a.has("d2")).is_true()
	assert_bool(a.has("e1")).is_false()


func test_ranked_party_gap() -> void:
	var r := _rules()
	r.ranked_party_gap_max = 300.0
	var mm := Matchmaker.new(r)
	assert_int(mm.enqueue(&"ranked_5v5", [_m("a", 1200), _m("b", 1600)], T0).err).is_equal(Matchmaker.Err.E_PARTY_GAP)
	assert_int(mm.enqueue(&"ranked_5v5", [_m("a", 1300), _m("b", 1600)], T0).err).is_equal(Matchmaker.Err.OK)
	# The gap does not apply outside ranked.
	assert_int(mm.enqueue(&"normal_5v5", [_m("c", 1000), _m("d", 2200)], T0).err).is_equal(Matchmaker.Err.OK)


func test_enqueue_errors() -> void:
	var mm := Matchmaker.new(_rules())
	assert_int(mm.enqueue(&"custom", [_m("a", 1500)], T0).err).is_equal(Matchmaker.Err.E_QUEUE)
	assert_int(mm.enqueue(&"nope", [_m("a", 1500)], T0).err).is_equal(Matchmaker.Err.E_QUEUE)
	assert_int(mm.enqueue(&"all_random_3v3", [_m("a", 1), _m("b", 1), _m("c", 1), _m("d", 1)], T0).err) \
		.is_equal(Matchmaker.Err.E_PARTY_SIZE)
	assert_int(mm.enqueue(&"normal_5v5", [_m("a", 1500, [&"north", &"north"])], T0).err).is_equal(Matchmaker.Err.E_LANES)
	assert_int(mm.enqueue(&"normal_5v5", [_m("a", 1500)], T0).err).is_equal(Matchmaker.Err.OK)
	assert_int(mm.enqueue(&"ranked_5v5", [_m("a", 1500)], T0).err).is_equal(Matchmaker.Err.E_ALREADY)
	assert_bool(mm.leave("a")).is_true()
	assert_int(mm.ticket_of("a")).is_equal(0)


func test_lane_preferences_drive_starting_lanes() -> void:
	var mm := Matchmaker.new(_rules())
	var lanes := [[&"north", &"center"], [&"center", &"north"], [&"south", &"flex"], [&"flex", &"south"], [&"flex", &"north"]]
	for side in 2:
		for i in 5:
			mm.enqueue(&"normal_5v5", [_m("p%d_%d" % [side, i], 1500, lanes[i])], T0)
	var p := mm.tick(T0)[0]
	for side in 2:
		var got := {}
		for seat in p.teams[side]:
			got[seat.lane] = int(got.get(seat.lane, 0)) + 1
		assert_dict(got).is_equal({&"north": 1, &"center": 1, &"south": 1, &"flex": 2})
	# Each team holds one of each preference set, so nobody misses a primary.
	for side in 2:
		for seat in p.teams[side]:
			var i := int(String(seat.id).get_slice("_", 1))
			assert_str(String(seat.lane)).is_equal(String(lanes[i][0]))


func test_empty_queue_bot_fill_after_delay() -> void:
	var mm := Matchmaker.new(_rules())
	mm.enqueue(&"normal_5v5", [_m("solo", 1500)], T0)
	assert_array(mm.tick(T0 + 74)).is_empty()
	var ps := mm.tick(T0 + 75)
	assert_int(ps.size()).is_equal(1)
	var p := ps[0]
	assert_int(p.bots).is_equal(9)
	assert_bool(p.rated).is_false()
	assert_array(Matchmaker.human_ids(p)).is_equal(["solo"])
	var bot_lanes := []
	for side in 2:
		for seat in p.teams[side]:
			if seat.bot:
				assert_bool(MatchmakingRulesDef.is_bot(seat.id)).is_true()
				bot_lanes.append(seat.lane)
	assert_bool(bot_lanes.has(&"")).is_false()


func test_bot_fill_splits_humans_and_3v3() -> void:
	var mm := Matchmaker.new(_rules())
	_solos(mm, &"all_random_3v3", "p", [1500, 1500, 1500, 1500], T0)
	var p := mm.tick(T0 + 80)[0]
	assert_int(p.bots).is_equal(2)
	var humans := [0, 0]
	for side in 2:
		for seat in p.teams[side]:
			humans[side] += 0 if seat.bot else 1
	assert_array(humans).is_equal([2, 2])


func test_ranked_never_uses_bots() -> void:
	var mm := Matchmaker.new(_rules())
	_solos(mm, &"ranked_5v5", "p", [1500, 1500, 1500], T0)
	assert_array(mm.tick(T0 + 3600)).is_empty()
	assert_int(mm.queue_info(&"ranked_5v5").players).is_equal(3)


func test_party_member_declines_ready_check() -> void:
	var mm := Matchmaker.new(_rules())
	mm.enqueue(&"normal_5v5", [_m("lead", 1500), _m("mate", 1500)], T0)
	_solos(mm, &"normal_5v5", "s", [1500, 1500, 1500, 1500, 1500, 1500, 1500, 1500], T0 + 5)
	var p := mm.tick(T0 + 5)[0]
	assert_int(mm.enqueue(&"normal_5v5", [_m("lead", 1500)], T0 + 6).err).is_equal(Matchmaker.Err.E_ALREADY)
	var rc := ReadyCheck.new(Matchmaker.human_ids(p), T0 + 5, mm.rules.ready_check_s)
	for id in Matchmaker.human_ids(p):
		if id != "mate":
			rc.accept(id, T0 + 6)
	rc.decline("mate", T0 + 7)
	var res := mm.resolve_ready_check(p, rc.failed_ids(), T0 + 7)
	assert_array(res.removed).contains_exactly_in_any_order(["lead", "mate"])
	assert_dict(res.locked).contains_keys(["mate"])
	assert_bool(res.locked.has("lead")).is_false()
	assert_int(res.requeued.size()).is_equal(8)
	for tid in res.requeued:
		var t := mm.ticket(tid)
		assert_bool(t.priority).is_true()
		assert_float(t.enqueued_at).is_equal(T0 + 5)  # keeps its place
	assert_int(mm.enqueue(&"normal_5v5", [_m("mate", 1500)], T0 + 8).err).is_equal(Matchmaker.Err.E_LOCKED)
	assert_int(mm.enqueue(&"normal_5v5", [_m("lead", 1500)], T0 + 8).err).is_equal(Matchmaker.Err.OK)


func test_priority_tickets_are_matched_first() -> void:
	var mm := Matchmaker.new(_rules())
	_solos(mm, &"all_random_3v3", "a", [1500, 1500, 1500, 1500, 1500, 1500], T0)
	var p := mm.tick(T0)[0]
	var res := mm.resolve_ready_check(p, ["a0"], T0 + 10)
	assert_int(res.requeued.size()).is_equal(5)
	_solos(mm, &"all_random_3v3", "late", [1500, 1500, 1500, 1500, 1500, 1500], T0 - 100)  # older, no priority
	var p2 := mm.tick(T0 + 11)[0]
	var ids := Matchmaker.human_ids(p2)
	for i in range(1, 6):
		assert_bool(ids.has("a%d" % i)).is_true()


func test_timeout_locks_non_responders_and_confirm_releases() -> void:
	var mm := Matchmaker.new(_rules())
	_solos(mm, &"all_random_3v3", "a", [1500, 1500, 1500, 1500, 1500, 1500], T0)
	var p := mm.tick(T0)[0]
	var rc := ReadyCheck.new(Matchmaker.human_ids(p), T0, 10.0)
	for id in ["a0", "a1", "a2", "a3"]:
		rc.accept(id, T0 + 1)
	rc.tick(T0 + 10)
	var res := mm.resolve_ready_check(p, rc.failed_ids(), T0 + 10)
	assert_dict(res.locked).contains_keys(["a4", "a5"])
	_solos(mm, &"all_random_3v3", "b", [1500, 1500], T0 + 11)
	var p2 := mm.tick(T0 + 11)[0]
	mm.confirm(p2)
	assert_int(mm.enqueue(&"normal_5v5", [_m("a0", 1500)], T0 + 20).err).is_equal(Matchmaker.Err.OK)


func test_wait_estimate_and_queue_info() -> void:
	var mm := Matchmaker.new(_rules())
	assert_float(mm.estimated_wait_s(&"all_random_3v3")).is_equal(60.0)
	_solos(mm, &"all_random_3v3", "a", [1500, 1500, 1500], T0)
	_solos(mm, &"all_random_3v3", "b", [1500, 1500, 1500], T0 + 30)
	var info := mm.queue_info(&"all_random_3v3")
	assert_int(info.players).is_equal(6)
	assert_int(info.parties).is_equal(6)
	mm.tick(T0 + 30)
	assert_float(mm.estimated_wait_s(&"all_random_3v3")).is_equal(15.0)  # (3*30 + 3*0) / 6
