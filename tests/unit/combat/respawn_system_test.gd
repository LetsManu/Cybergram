extends GdUnitTestSuite
## Respawn timer, match-flow-and-map.md F7 / Canon C11 (AC 12: within 0.1 s
## at deaths sampled at 0, 12, 30 and 60 minutes).


func _rules() -> MatchRulesDef:
	return load("res://assets/data/match/match_rules_slice.tres") as MatchRulesDef


func test_formula_matches_gdd_table() -> void:
	var r := _rules()
	assert_float(RespawnSystem.respawn_seconds(r, 0.0)).is_equal_approx(6.0, 0.1)
	assert_float(RespawnSystem.respawn_seconds(r, 12.0)).is_equal_approx(10.8, 0.1)
	assert_float(RespawnSystem.respawn_seconds(r, 30.0)).is_equal_approx(18.0, 0.1)
	assert_float(RespawnSystem.respawn_seconds(r, 45.0)).is_equal_approx(24.0, 0.1)
	assert_float(RespawnSystem.respawn_seconds(r, 60.0)).is_equal_approx(30.0, 0.1)


func test_capped_after_60_minutes() -> void:
	assert_float(RespawnSystem.respawn_seconds(_rules(), 90.0)).is_equal(30.0)


func test_ticks_round_up_at_30hz() -> void:
	var r := _rules()
	assert_int(RespawnSystem.respawn_ticks(r, 0, 30)).is_equal(180)
	# 12:00 = tick 21600 -> 10.8 s -> 324 ticks.
	assert_int(RespawnSystem.respawn_ticks(r, 21600, 30)).is_equal(324)
	# 1 s in: 6.00667 s -> 181 ticks (never early).
	assert_int(RespawnSystem.respawn_ticks(r, 30, 30)).is_equal(181)
