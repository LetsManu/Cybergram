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
	assert_int(v.needed()).is_equal(4)  # ceil(0.8 * 4)
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
