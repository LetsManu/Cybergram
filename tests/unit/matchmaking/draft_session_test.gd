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


# --- P3: hover, timeout, blind, bans, trades ---------------------------------------

const MANY: Array[StringName] = [&"h01", &"h02", &"h03", &"h04", &"h05", &"h06", &"h07", &"h08", &"h09", &"h10",
	&"h11", &"h12", &"h13", &"h14"]


func test_hover_is_declared_and_blocks_allies_not_enemies() -> void:
	var d := DraftSession.new(A, B, HEROES, _rules(), T0, 1)
	assert_int(d.hover("a3", &"hero_c", T0)).is_equal(DraftSession.Err.OK)  # before its turn: allowed
	assert_int(d.hover("a1", &"hero_c", T0)).is_equal(DraftSession.Err.E_TAKEN)
	assert_int(d.pick("a0", &"hero_c", T0)).is_equal(DraftSession.Err.E_TAKEN)  # an ally declared it
	assert_bool(d.legal_heroes(0, "a0").has(&"hero_c")).is_false()
	assert_bool(d.legal_heroes(0, "a3").has(&"hero_c")).is_true()
	assert_int(d.hover("b0", &"hero_c", T0)).is_equal(DraftSession.Err.OK)  # the enemy may
	assert_int(d.hover("a3", &"", T0)).is_equal(DraftSession.Err.OK)  # cleared
	assert_int(d.pick("a0", &"hero_c", T0)).is_equal(DraftSession.Err.OK)


func test_hovered_hero_auto_locks_at_the_deadline() -> void:
	var r := _rules()
	var d := DraftSession.new(A, B, HEROES, r, T0, 1, 0, {"timeout_dodges": true})
	d.hover("a0", &"hero_e", T0)
	d.tick(T0 + r.pick_turn_s)
	assert_str(String(d.picks["a0"])).is_equal("hero_e")
	assert_array(d.hover_locked).contains_exactly(["a0"])
	assert_int(d.state).is_equal(DraftSession.State.PICKING)  # no dodge: the player was there


func test_ranked_timeout_with_nothing_hovered_aborts_as_a_dodge() -> void:
	var r := _rules()
	var d := DraftSession.new(A, B, HEROES, r, T0, 1, 0, {"timeout_dodges": true})
	d.pick("a0", &"hero_a", T0)
	d.hover("b0", &"hero_b", T0)  # b0 hovered, b1 did nothing
	assert_int(d.tick(T0 + r.pick_turn_s)).is_equal(DraftSession.State.ABORTED)
	assert_str(d.dodger).is_equal("b1")
	assert_bool(d.timed_out).is_true()


func test_normal_timeout_still_picks_at_random() -> void:
	var d := DraftSession.new(A, B, HEROES, _rules(), T0, 1)
	d.tick(T0 + 30)
	assert_bool(d.picks.has("a0")).is_true()
	assert_array(d.auto_picked).contains_exactly(["a0"])


func test_blind_everyone_picks_at_once_with_one_timer() -> void:
	var r := _rules()
	var d := DraftSession.new(A, B, HEROES, r, T0, 1, 0, {"blind": true})
	assert_int(d.turn_team).is_equal(DraftSession.BOTH)
	assert_int(d.current_pickers().size()).is_equal(10)
	assert_float(d.deadline).is_equal(T0 + r.blind_pick_s)
	assert_int(d.pick("b4", &"hero_a", T0)).is_equal(DraftSession.Err.OK)
	assert_int(d.pick("a2", &"hero_a", T0)).is_equal(DraftSession.Err.OK)  # mirror across teams
	assert_int(d.pick("a3", &"hero_a", T0)).is_equal(DraftSession.Err.E_TAKEN)  # first ally to lock wins
	d.tick(T0 + r.blind_pick_s)
	assert_int(d.state).is_equal(DraftSession.State.DONE)
	assert_int(d.picks.size()).is_equal(10)


func test_ban_count_is_capped_by_the_roster() -> void:
	var r := _rules()
	r.bans_per_team = 3
	var d := DraftSession.new(A, B, HEROES, r, T0, 1)  # 7 heroes: no room for bans
	assert_int(d.state).is_equal(DraftSession.State.PICKING)
	var d2 := DraftSession.new(A, B, MANY, r, T0, 1)  # 14 heroes: (14 - 8) / 2 = 3 per team
	assert_int(d2.state).is_equal(DraftSession.State.BANNING)
	assert_int(d2.current_banners().size()).is_equal(6)


func test_ban_phase_hover_locks_none_bans_nothing_then_reveal() -> void:
	var r := _rules()
	r.bans_per_team = 1
	var d := DraftSession.new(A, B, MANY, r, T0, 1)
	assert_array(d.current_banners()).contains_exactly(["a0", "b0"])
	assert_int(d.pick("a0", &"h01", T0)).is_equal(DraftSession.Err.E_CLOSED)  # no picks while banning
	assert_int(d.hover("a0", &"h03", T0)).is_equal(DraftSession.Err.OK)  # b0 does nothing
	d.tick(T0 + r.ban_s)
	assert_array(d.bans).is_equal([&"h03"])
	assert_int(d.state).is_equal(DraftSession.State.PICKING)
	assert_float(d.deadline).is_equal(T0 + r.ban_s + r.ban_reveal_s + r.pick_turn_s)
	assert_int(d.pick("a0", &"h03", T0 + r.ban_s)).is_equal(DraftSession.Err.E_BANNED)
	assert_int(d.hover("b0", &"h03", T0 + r.ban_s)).is_equal(DraftSession.Err.E_BANNED)
	assert_bool(d.legal_heroes(1).has(&"h03")).is_false()


func test_all_bans_locked_end_the_ban_phase_early() -> void:
	var r := _rules()
	r.bans_per_team = 1
	var d := DraftSession.new(A, B, MANY, r, T0, 1)
	d.ban("a0", &"h01", T0 + 1)
	d.ban("b0", &"h01", T0 + 2)  # both teams banned the same hero: one ban
	assert_int(d.state).is_equal(DraftSession.State.PICKING)
	assert_array(d.bans).is_equal([&"h01"])


func test_finalize_trades_between_locked_teammates_until_the_countdown() -> void:
	var r := _rules()
	r.finalize_s = 20.0
	r.finalize_lock_s = 5.0
	var d := DraftSession.new(A, B, HEROES, r, T0, 1, 0, {"blind": true})
	for i in 5:
		d.pick(A[i], HEROES[i], T0)
		d.pick(B[i], HEROES[i], T0)
	assert_int(d.state).is_equal(DraftSession.State.FINALIZING)
	assert_int(d.request_trade("a0", "b0", T0 + 1)).is_equal(DraftSession.Err.E_NOT_TEAMMATE)
	assert_int(d.request_trade("a0", "a1", T0 + 1)).is_equal(DraftSession.Err.OK)
	assert_array(d.trade_requests_to("a1", T0 + 2)).is_equal(["a0"])
	assert_int(d.accept_trade("a1", "a0", T0 + 2)).is_equal(DraftSession.Err.OK)
	assert_str(String(d.picks["a0"])).is_equal(String(HEROES[1]))
	assert_str(String(d.picks["a1"])).is_equal(String(HEROES[0]))
	assert_int(d.accept_trade("a1", "a0", T0 + 3)).is_equal(DraftSession.Err.E_NO_REQUEST)  # used up
	assert_int(d.request_trade("a2", "a3", T0 + 15.5)).is_equal(DraftSession.Err.E_CLOSED)  # countdown
	assert_int(d.tick(T0 + 20)).is_equal(DraftSession.State.DONE)


func test_trade_request_expires() -> void:
	var r := _rules()
	r.finalize_s = 60.0
	var d := DraftSession.new(A, B, HEROES, r, T0, 1, 0, {"blind": true})
	for i in 5:
		d.pick(A[i], HEROES[i], T0)
		d.pick(B[i], HEROES[i], T0)
	d.request_trade("a0", "a1", T0)
	assert_int(d.accept_trade("a1", "a0", T0 + r.swap_request_ttl_s + 0.1)).is_equal(DraftSession.Err.E_NO_REQUEST)


func test_dodge_during_finalize_aborts() -> void:
	var r := _rules()
	r.finalize_s = 20.0
	var d := DraftSession.new(A, B, HEROES, r, T0, 1, 0, {"blind": true})
	for i in 5:
		d.pick(A[i], HEROES[i], T0)
		d.pick(B[i], HEROES[i], T0)
	d.dodge("b2")
	assert_int(d.state).is_equal(DraftSession.State.ABORTED)


func test_short_draft_order_still_gives_every_seat_a_hero() -> void:
	var r := _rules()
	r.draft_order = PackedInt32Array([1, 1])  # bad data: 2 turns for 10 seats
	var d := DraftSession.new(A, B, HEROES, r, T0, 1)
	d.tick(T0 + 60)
	assert_int(d.state).is_equal(DraftSession.State.DONE)
	assert_int(d.picks.size()).is_equal(10)
