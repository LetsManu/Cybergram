extends GdUnitTestSuite
## W17-MM: Glicko2 math against Glickman's published worked example.


func test_paper_example() -> void:
	var terms := [Glicko2.term_vs(1500, 1400, 30, 1.0), Glicko2.term_vs(1500, 1550, 100, 0.0),
		Glicko2.term_vs(1500, 1700, 300, 0.0)]
	var r := Glicko2.update(1500.0, 200.0, 0.06, terms, 0.5)
	assert_float(r.rating).is_equal_approx(1464.05, 0.01)
	assert_float(r.rd).is_equal_approx(151.52, 0.01)
	assert_float(r.vol).is_equal_approx(0.059996, 0.000001)


func test_idle_period_only_grows_deviation() -> void:
	var r := Glicko2.update(1700.0, 100.0, 0.06, [], 0.5)
	assert_float(r.rating).is_equal(1700.0)
	assert_float(r.rd).is_greater(100.0)


func test_equal_players_expect_half() -> void:
	assert_float(Glicko2.expected(0.0, 0.0, Glicko2.g(1.0))).is_equal_approx(0.5, 0.000001)
	assert_float(Glicko2.g(0.0)).is_equal(1.0)
