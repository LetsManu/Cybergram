extends GdUnitTestSuite
## W17-MM: ready check accept / decline / timeout.


func test_all_accept() -> void:
	var rc := ReadyCheck.new(["a", "b"], 0.0, 10.0)
	assert_bool(rc.accept("a", 1.0)).is_true()
	assert_int(rc.tick(2.0)).is_equal(ReadyCheck.State.PENDING)
	rc.accept("b", 3.0)
	assert_int(rc.state).is_equal(ReadyCheck.State.ACCEPTED)
	assert_array(rc.failed_ids()).is_empty()


func test_decline_fails_at_once_and_names_only_the_decliner() -> void:
	var rc := ReadyCheck.new(["a", "b", "c"], 0.0, 10.0)
	rc.accept("a", 1.0)
	assert_bool(rc.decline("b", 2.0)).is_true()
	assert_int(rc.state).is_equal(ReadyCheck.State.FAILED)
	assert_array(rc.failed_ids()).is_equal(["b"])
	assert_bool(rc.accept("c", 3.0)).is_false()


func test_timeout_fails_non_responders() -> void:
	var rc := ReadyCheck.new(["a", "b", "c"], 0.0, 10.0)
	rc.accept("a", 1.0)
	assert_bool(rc.accept("b", 10.0)).is_false()  # deadline reached
	assert_int(rc.state).is_equal(ReadyCheck.State.FAILED)
	assert_array(rc.failed_ids()).contains_exactly_in_any_order(["b", "c"])


func test_strangers_cannot_answer() -> void:
	var rc := ReadyCheck.new(["a"], 0.0, 10.0)
	assert_bool(rc.accept("x", 1.0)).is_false()
	assert_bool(rc.decline("x", 1.0)).is_false()
