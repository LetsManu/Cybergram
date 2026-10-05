extends GdUnitTestSuite
## W21-A1: announcer queue rules — priority order, queue size 3, drop after 4 s,
## double -> triple upgrade, 0.4 s gap, no repeat within 8 s (uplink 15 s),
## only priority >= 90 interrupts.

func _queue() -> AnnouncerQueue:
	return AnnouncerQueue.new(load("res://assets/data/audio/announcer.tres") as AnnouncerDef)


func test_highest_priority_first() -> void:
	var q := _queue()
	q.push(&"first_blood", 0.0)
	q.push(&"hardpoint_lost", 0.0)
	q.push(&"double_kill", 0.0)
	assert_array(q.pending()).is_equal([&"hardpoint_lost", &"double_kill", &"first_blood"])
	assert_str(String(q.next(0.0))).is_equal("hardpoint_lost")


func test_queue_keeps_three_and_drops_the_least_important() -> void:
	var q := _queue()
	q.push(&"hardpoint_lost", 0.0)
	q.push(&"hardpoint_captured", 0.0)
	q.push(&"shutdown", 0.0)
	assert_bool(q.push(&"thirty_seconds", 0.0)).is_false()
	assert_bool(q.push(&"uplink_under_attack", 0.0)).is_true()
	assert_array(q.pending()).is_equal([&"uplink_under_attack", &"hardpoint_lost", &"hardpoint_captured"])


func test_lines_older_than_four_seconds_are_dropped() -> void:
	var q := _queue()
	q.push(&"first_blood", 0.0)
	assert_str(String(q.next(4.5))).is_equal("")
	assert_array(q.pending()).is_empty()


func test_pending_double_upgrades_to_triple() -> void:
	var q := _queue()
	q.push(&"double_kill", 0.0)
	q.push(&"triple_kill", 0.5)
	assert_array(q.pending()).is_equal([&"triple_kill"])


func test_gap_between_lines() -> void:
	var q := _queue()
	q.push(&"first_blood", 0.0)
	q.push(&"double_kill", 0.0)
	var a := q.next(0.0)
	q.started(a, 0.0, 1.0)
	assert_str(String(q.next(1.2))).is_equal("")  # inside the 0.4 s gap
	assert_str(String(q.next(1.41))).is_equal("first_blood")


func test_no_repeat_within_window() -> void:
	var q := _queue()
	q.push(&"first_blood", 0.0)
	q.started(q.next(0.0), 0.0, 1.0)
	assert_bool(q.push(&"first_blood", 7.9)).is_false()
	assert_bool(q.push(&"first_blood", 8.1)).is_true()


func test_uplink_repeat_window_is_fifteen_seconds() -> void:
	var q := _queue()
	q.push(&"uplink_under_attack", 0.0)
	q.started(q.next(0.0), 0.0, 1.0)
	assert_bool(q.push(&"uplink_under_attack", 10.0)).is_false()
	assert_bool(q.push(&"uplink_under_attack", 15.1)).is_true()


func test_only_ninety_and_up_interrupts() -> void:
	var q := _queue()
	q.push(&"double_kill", 0.0)
	q.started(q.next(0.0), 0.0, 2.0)
	q.push(&"uplink_under_attack", 0.5)  # 80: waits
	assert_bool(q.interrupt_requested).is_false()
	assert_str(String(q.next(0.5))).is_equal("")
	q.push(&"sudden_death", 0.6)  # 90: interrupts
	assert_bool(q.interrupt_requested).is_true()
	assert_str(String(q.next(0.6))).is_equal("sudden_death")
