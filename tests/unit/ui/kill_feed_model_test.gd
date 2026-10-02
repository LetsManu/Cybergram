extends GdUnitTestSuite
## E12 kill feed queue (design/ux/hud.md §4.10, §18: 5 rows, 6 s, newest on top).


func _e(k: String, v: String) -> KillFeedModel.Entry:
	return KillFeedModel.Entry.make(k, 0, v, 1, false)


func test_newest_first_and_row_cap() -> void:
	var m := KillFeedModel.new(5, 6.0)
	for i in 7:
		m.push(_e("k%d" % i, "v%d" % i))
	assert_int(m.entries.size()).is_equal(5)
	assert_str(m.entries[0].killer_name).is_equal("k6")
	assert_str(m.entries[4].killer_name).is_equal("k2")  # k0, k1 dropped


func test_rows_expire_after_duration() -> void:
	var m := KillFeedModel.new(5, 6.0)
	m.push(_e("a", "b"))
	m.advance(4.0)
	m.push(_e("c", "d"))
	m.advance(1.9)
	assert_int(m.entries.size()).is_equal(2)
	m.advance(0.2)  # "a" is now 6.1 s old
	assert_int(m.entries.size()).is_equal(1)
	assert_str(m.entries[0].killer_name).is_equal("c")
	m.advance(4.0)
	assert_bool(m.entries.is_empty()).is_true()


func test_fade_over_last_half_second() -> void:
	var m := KillFeedModel.new(5, 6.0)
	var e := _e("a", "b")
	m.push(e)
	assert_float(m.alpha(e)).is_equal(1.0)
	m.advance(5.75)
	assert_float(m.alpha(e)).is_equal_approx(0.5, 1e-4)


func test_tuning_bounds() -> void:
	var m := KillFeedModel.new(0, 0.0)
	assert_int(m.max_rows).is_equal(1)
	assert_float(m.duration_s).is_greater(0.0)
	m.push(_e("a", "b"))
	m.push(_e("c", "d"))
	assert_int(m.entries.size()).is_equal(1)
