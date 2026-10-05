extends GdUnitTestSuite
## W11-M1 Reveal: per-team reveal windows (RevealSet).

func test_reveal_is_per_team_and_expires() -> void:
	var r := RevealSet.new()
	r.reveal(7, 0, 30, 100)
	assert_bool(r.is_revealed(7, 0, 129)).is_true()
	assert_bool(r.is_revealed(7, 1, 100)).is_false()  # the other team never sees it
	assert_bool(r.is_revealed(7, 0, 130)).is_false()
	r.step(130)
	assert_int(r.revealed_ids(0, 130).size()).is_equal(0)


func test_reveal_extends_never_shortens() -> void:
	var r := RevealSet.new()
	r.reveal(7, 0, 60, 0)
	r.reveal(7, 0, 10, 0)
	assert_bool(r.is_revealed(7, 0, 59)).is_true()
	r.reveal(7, 0, 90, 10)
	assert_bool(r.is_revealed(7, 0, 99)).is_true()


func test_clear_hero_and_zero_ticks() -> void:
	var r := RevealSet.new()
	r.reveal(3, 0, 0, 0)
	assert_bool(r.is_revealed(3, 0, 0)).is_false()
	r.reveal(3, 0, 30, 0)
	r.reveal(3, 1, 30, 0)
	r.clear_hero(3)
	assert_bool(r.is_revealed(3, 0, 1) or r.is_revealed(3, 1, 1)).is_false()
