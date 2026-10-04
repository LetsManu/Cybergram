extends GdUnitTestSuite
## W11-V1: Fork tint of remote skill VFX (A cool, B warm, per faction).


func test_no_fork_leaves_colour_alone() -> void:
	var c := Color(0.2, 0.3, 0.4, 0.7)
	assert_that(FxForkTint.apply(c, 0, 0)).is_equal(c)


func test_fork_a_is_cooler_than_fork_b_in_both_factions() -> void:
	for team in 2:
		var a := FxForkTint.tint_for(team, 1)
		var b := FxForkTint.tint_for(team, 2)
		assert_float(a.b - a.r).is_greater(0.0)  # cool: more blue than red
		assert_float(b.r - b.b).is_greater(0.0)  # warm


func test_apply_keeps_alpha_and_moves_toward_tint() -> void:
	var out := FxForkTint.apply(Color(1, 1, 1, 0.5), 0, 2)
	assert_float(out.a).is_equal(0.5)
	assert_float(out.b).is_less(1.0)
