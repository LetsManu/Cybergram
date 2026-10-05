extends GdUnitTestSuite
## W17-MM: remake vote trigger, window, voters, threshold, timeout.

const START := 100.0
const TEAM: Array = ["a0", "a1", "a2", "a3", "a4"]


func _vote() -> RemakeVote:
	return RemakeVote.new(TEAM, START, MatchmakingRulesDef.new())


func test_needs_an_absent_player() -> void:
	var v := _vote()
	assert_int(v.start("a0", START + 10)).is_equal(RemakeVote.Err.E_NO_TRIGGER)


func test_passes_with_all_remaining_and_absent_cannot_vote() -> void:
	var v := _vote()
	v.mark_absent("a4")
	assert_int(v.needed()).is_equal(4)  # all four present
	assert_int(v.start("a4", START + 10)).is_equal(RemakeVote.Err.E_NOT_VOTER)
	assert_int(v.start("a0", START + 10)).is_equal(RemakeVote.Err.OK)
	assert_int(v.start("a1", START + 11)).is_equal(RemakeVote.Err.E_ACTIVE)
	assert_int(v.vote("a0", true, START + 11)).is_equal(RemakeVote.Err.E_ALREADY_VOTED)
	v.vote("a1", true, START + 12)
	v.vote("a2", true, START + 12)
	assert_int(v.state).is_equal(RemakeVote.State.OPEN)
	v.vote("a3", true, START + 13)
	assert_int(v.state).is_equal(RemakeVote.State.PASSED)


func test_one_no_fails_and_needs_new_absence() -> void:
	var v := _vote()
	v.mark_absent("a4")
	v.start("a0", START + 10)
	v.vote("a1", false, START + 11)
	assert_int(v.state).is_equal(RemakeVote.State.FAILED)
	assert_int(v.start("a2", START + 20)).is_equal(RemakeVote.Err.E_NO_TRIGGER)
	v.mark_absent("a3")
	assert_int(v.start("a2", START + 21)).is_equal(RemakeVote.Err.OK)
	assert_int(v.needed()).is_equal(3)


func test_window_and_timeout() -> void:
	var v := _vote()
	v.mark_absent("a4")
	assert_int(v.start("a0", START + 180.5)).is_equal(RemakeVote.Err.E_TOO_LATE)
	var w := _vote()
	w.mark_absent("a4")
	w.start("a0", START + 100)
	assert_int(w.tick(START + 130)).is_equal(RemakeVote.State.FAILED)


func test_bots_do_not_vote() -> void:
	var v := RemakeVote.new(["a0", "bot:1", "bot:2"], START, MatchmakingRulesDef.new())
	v.mark_absent("a0")
	assert_array(v.eligible_voters()).is_empty()
	assert_int(v.start("bot:1", START + 5)).is_equal(RemakeVote.Err.E_NOT_VOTER)


func test_threshold_is_all_present() -> void:
	var v := _vote()
	v.mark_absent("a3")
	v.mark_absent("a4")
	assert_int(v.needed()).is_equal(3)
	v.start("a0", START + 10)
	v.vote("a1", true, START + 11)
	assert_int(v.state).is_equal(RemakeVote.State.OPEN)  # 2 of 3 is not enough
	v.vote("a2", true, START + 12)
	assert_int(v.state).is_equal(RemakeVote.State.PASSED)
	assert_array(v.absent_at_pass).is_equal(["a3", "a4"])


func test_single_no_fails_even_with_many_yes() -> void:
	var v := _vote()
	v.mark_absent("a4")
	v.start("a0", START + 10)
	v.vote("a1", true, START + 11)
	v.vote("a2", true, START + 11)
	v.vote("a3", false, START + 12)
	assert_int(v.state).is_equal(RemakeVote.State.FAILED)
	assert_array(v.absent_at_pass).is_empty()


func test_absent_player_gets_escalating_leaver_strike() -> void:
	var rules := MatchmakingRulesDef.new()
	var lockouts := LockoutTracker.new(rules)
	var v := RemakeVote.new(["a0", "a1", "a2", "bot:1"], START, rules)
	v.mark_absent("a2")
	v.mark_absent("bot:1")
	v.start("a0", START + 10)
	v.vote("a1", true, START + 11)
	assert_int(v.state).is_equal(RemakeVote.State.PASSED)
	assert_array(v.absent_at_pass).is_equal(["a2"])
	var first := RemakeVote.strike_absent(lockouts, v.absent_at_pass, START + 11)
	assert_dict(first).is_equal({"a2": rules.leaver_lockout_steps_s[0]})
	assert_bool(lockouts.is_locked("a2", START + 12, true)).is_true()
	assert_bool(lockouts.is_locked("a2", START + 12, false)).is_false()
	assert_bool(lockouts.is_locked("a0", START + 12, true)).is_false()
	var second := RemakeVote.strike_absent(lockouts, ["a2", "bot:1"], START + 5000)
	assert_dict(second).is_equal({"a2": rules.leaver_lockout_steps_s[1]})


func test_reconnected_player_is_not_struck() -> void:
	var v := _vote()
	v.mark_absent("a4")
	v.mark_absent("a3")
	v.mark_present("a3")
	v.start("a0", START + 10)
	for s in ["a1", "a2", "a3"]:
		v.vote(s, true, START + 11)
	assert_int(v.state).is_equal(RemakeVote.State.PASSED)
	assert_array(v.absent_at_pass).is_equal(["a4"])
