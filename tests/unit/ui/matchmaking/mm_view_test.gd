extends GdUnitTestSuite
## W17B-UI: display rules of the matchmaking screens (MmView) and the
## protocol-17 adapter's conversions (MmClientAdapter).


func test_clock_rounds_up_and_clamps() -> void:
	assert_str(MmView.clock(75.0)).is_equal("1:15")
	assert_str(MmView.clock(9.2)).is_equal("0:10")
	assert_str(MmView.clock(-3.0)).is_equal("0:00")
	assert_int(MmView.secs(0.01)).is_equal(1)
	assert_int(MmView.secs(0.0)).is_equal(0)


func test_lane_rules() -> void:
	assert_bool(MmView.lanes_valid(&"fill", &"north")).is_true()
	assert_bool(MmView.lanes_valid(&"north", &"center")).is_true()
	assert_bool(MmView.lanes_valid(&"north", &"north")).is_false()
	assert_array(MmView.lane_prefs(&"fill", &"south")).is_equal([&"fill"])
	assert_array(MmView.lane_prefs(&"south", &"flex")).is_equal([&"south", &"flex"])
	assert_str(String(MmView.fix_secondary(&"center", &"center"))).is_not_equal("center")
	assert_str(String(MmView.fix_secondary(&"center", &"south"))).is_equal("south")


func test_ranked_line_calibrating_and_medal() -> void:
	HudStrings.ensure_loaded()
	assert_str(MmView.ranked_line({"calibrating": true, "games_left": 7}, 10)).is_equal("Calibrating 3/10")
	assert_str(MmView.ranked_line({"calibrating": false, "rating": 1563, "medal": {"label": "Gold II"}}, 10)) \
		.is_equal("Gold II · 1563")
	assert_str(MmView.ranked_line({}, 10)).is_equal("Unranked")


func test_rating_change_only_for_ranked() -> void:
	HudStrings.ensure_loaded()
	var r := {"delta": 18}
	assert_bool(MmView.rating_change(MmView.Q_NORMAL, r, false).visible).is_false()
	assert_bool(MmView.rating_change(MmView.Q_ARAM, r, false).visible).is_false()
	var ranked := MmView.rating_change(MmView.Q_RANKED, r, false)
	assert_bool(ranked.visible).is_true()
	assert_str(ranked.text).is_equal("+18")
	assert_str(MmView.rating_change(MmView.Q_RANKED, {"delta": -16}, false).text).is_equal("-16")
	assert_int(MmView.rating_change(MmView.Q_RANKED, r, true).delta).is_equal(0)


func test_medal_progress_counts_from_band_min() -> void:
	var bands := [{"name": "Silver", "min": 1300.0}, {"name": "Gold", "min": 1500.0}]
	assert_float(MmView.medal_progress(1520.0, 40.0, bands)).is_equal_approx(0.5, 0.001)
	assert_float(MmView.medal_progress(1500.0, 40.0, bands)).is_equal_approx(0.0, 0.001)


func test_can_pick_is_team_unique_and_turn_bound() -> void:
	var st := {"me": "me", "seats": [
		{"id": "me", "team": 0, "hero": &"", "picking": true},
		{"id": "p2", "team": 0, "hero": &"hero_hex", "picking": false},
		{"id": "p6", "team": 1, "hero": &"hero_sable", "picking": false}]}
	assert_bool(MmView.can_pick(st, "me", &"hero_hex")).is_false()  # teammate holds it
	assert_bool(MmView.can_pick(st, "me", &"hero_sable")).is_true()  # the enemy may share
	st.seats[0].picking = false
	assert_bool(MmView.can_pick(st, "me", &"hero_sable")).is_false()  # not my turn


func test_turn_plan_alternates() -> void:
	var plan := MmView.turn_plan(PackedInt32Array([1, 2, 2, 2, 2, 1]), 1)
	assert_int(plan.size()).is_equal(6)
	assert_int(plan[0].team).is_equal(1)
	assert_int(plan[1].team).is_equal(0)
	assert_int(plan[1].picks).is_equal(2)


func test_reroll_and_bench_rules() -> void:
	assert_bool(MmView.can_reroll({"open": true, "rerolls_left": 1})).is_true()
	assert_bool(MmView.can_reroll({"open": true, "rerolls_left": 0})).is_false()
	assert_bool(MmView.can_reroll({"open": false, "rerolls_left": 1})).is_false()
	assert_bool(MmView.can_take_bench({"open": true, "bench": [&"hero_hex"]}, &"hero_hex")).is_true()
	assert_bool(MmView.can_take_bench({"open": true, "bench": [&"hero_hex"]}, &"hero_sable")).is_false()


func test_adapter_draft_state_flags_and_turns() -> void:
	var rules := MatchmakingRulesDef.load_default()
	var hex := MmView.hero_index(&"hero_hex")
	var d := {"mode": 0, "turn": 1, "turn_team": 0, "seconds": 22, "you": 0, "seats": [
		{"id": "a", "team": 0, "lane": 0, "hero": 0, "flags": MatchmakingCodec.SEAT_PICKING | MatchmakingCodec.SEAT_YOU, "name": "Me"},
		{"id": "", "team": 1, "lane": 255, "hero": hex, "flags": MatchmakingCodec.SEAT_AUTO | MatchmakingCodec.SEAT_PICKED, "name": ""}]}
	var s := MmClientAdapter.draft_of(d, MmView.Q_RANKED, rules)
	assert_str(s.me).is_equal("seat0")
	assert_int(s.first_team).is_equal(1)
	assert_bool(s.ranked).is_true()
	assert_bool(s.seats[0].picking).is_true()
	assert_str(String(s.seats[0].lane)).is_equal("north")
	assert_str(String(s.seats[1].hero)).is_equal("hero_hex")
	assert_bool(s.seats[1].auto).is_true()
	assert_float(s.deadline_s).is_equal(22.0)


func test_adapter_status_and_result() -> void:
	var st := MmClientAdapter.status_of({"state": MatchmakingCodec.QS_LOCKED, "queue": 1, "locked": 40, "code": MatchmakingCodec.E_LOCKED})
	assert_str(String(st.state)).is_equal("locked")
	assert_str(String(st.queue)).is_equal("ranked_5v5")
	assert_str(st.err).is_equal("HUD_MM_ERR_LOCKED")
	var rules := MatchmakingRulesDef.load_default()
	var res := MmClientAdapter.result_of({"match": "m1", "queue": 1, "won": 1, "voided": 0, "duration": 900, "rated": 1,
		"delta": 18.0, "players": [{"id": "a", "team": 0, "hero": 0, "flags": MatchmakingCodec.MEM_YOU, "kills": 3, "deaths": 1, "assists": 2, "name": "Me"},
			{"id": "", "team": 1, "hero": 0, "flags": MatchmakingCodec.MEM_BOT, "kills": 0, "deaths": 3, "assists": 0, "name": "Bot"}]},
		{"tracks": [{"track_id": &"ranked", "rating": 1581, "games_left": 0}]}, rules)
	assert_int(res.rating.delta).is_equal(18)
	assert_int(res.rating.before).is_equal(1563)
	assert_int(res.stats.kills).is_equal(3)
	assert_bool(res.players[1].bot).is_true()
