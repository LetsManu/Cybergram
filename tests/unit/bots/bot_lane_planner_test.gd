extends GdUnitTestSuite
## W14-M2 BotLanePlanner: a 5-bot team opens 2/2/1 (Center, North, South first),
## one lane = everyone in lane 0, a rebalance moves at most one bot toward the
## neediest lane (dead bots first) and never on a small imbalance.


func test_opening_spread() -> void:
	var p := BotLanePlanner.new(3)
	var got: Array[int] = []
	for id in [11, 12, 13, 14, 15]:
		got.append(p.lane_of(id, 0))
	assert_array(got).is_equal([1, 0, 2, 1, 0])
	assert_array(Array(p.counts(0))).is_equal([2, 2, 1])
	# The other team counts on its own.
	assert_int(p.lane_of(21, 1)).is_equal(1)
	assert_array(Array(p.counts(1))).is_equal([0, 1, 0])


func test_one_lane_map_keeps_everyone_in_lane_zero() -> void:
	var p := BotLanePlanner.new(1)
	for id in 5:
		assert_int(p.lane_of(id + 1, 0)).is_equal(0)
	assert_bool(p.due(0, 100.0)).is_false()
	assert_int(p.rebalance(0, PackedFloat32Array([5.0]))).is_equal(0)


func test_rebalance_moves_one_bot_to_the_neediest_lane() -> void:
	var p := BotLanePlanner.new(3)
	for id in [1, 2, 3, 4, 5]:
		p.lane_of(id, 0)  # N 2, C 2, S 1
	# Balanced need: nobody moves.
	assert_int(p.rebalance(0, PackedFloat32Array([1.0, 1.0, 1.0]))).is_equal(0)
	# South under attack (need 4 of 6): one bot leaves the North or Center.
	var moved := p.rebalance(0, PackedFloat32Array([1.0, 1.0, 4.0]), {})
	assert_int(moved).is_not_equal(0)
	assert_int(p.assignment[moved]).is_equal(2)
	var c := p.counts(0)
	assert_int(c[2]).is_equal(2)
	assert_int(c[0] + c[1]).is_equal(3)


func test_dead_bot_is_the_preferred_mover() -> void:
	var p := BotLanePlanner.new(3)
	for id in [1, 2, 3, 4, 5]:
		p.lane_of(id, 0)  # ids 2 and 5 in North (lane 0)
	var moved := p.rebalance(0, PackedFloat32Array([0.2, 2.0, 3.0]), {5: true})
	assert_int(moved).is_equal(5)


func test_desired_split_and_due_interval() -> void:
	var d := BotLanePlanner.desired(5, PackedFloat32Array([1.0, 2.0, 2.0]))
	assert_float(d[0]).is_equal_approx(1.0, 0.001)
	assert_float(d[1]).is_equal_approx(2.0, 0.001)
	var p := BotLanePlanner.new(3)
	p.eval_interval_s = 8.0
	assert_bool(p.due(0, 0.0)).is_true()
	assert_bool(p.due(0, 7.9)).is_false()
	assert_bool(p.due(0, 8.0)).is_true()
	assert_bool(p.due(1, 1.0)).is_true()


func test_a_moved_bot_stays_for_min_stay() -> void:
	var p := BotLanePlanner.new(3)
	p.min_stay_s = 20.0
	for id in [1, 2, 3, 4, 5]:
		p.lane_of(id, 0)
	var moved := p.rebalance(0, PackedFloat32Array([0.1, 0.1, 5.0]), {}, 0.0)
	assert_int(moved).is_not_equal(0)
	# Need swings back at once: the moved bot is not moved again before 20 s.
	var back := p.rebalance(0, PackedFloat32Array([5.0, 0.1, 0.1]), {}, 5.0)
	assert_int(back).is_not_equal(moved)
