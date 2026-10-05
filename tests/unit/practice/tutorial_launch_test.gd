extends GdUnitTestSuite
## W11-V1: the menu's Tutorial button launches the practice range and asks for the tutorial once.


func after_test() -> void:
	PracticeRange.tutorial_requested = false
	PracticeRange.active = false


func test_begin_tutorial_flags_range_and_is_consumed_once() -> void:
	var args := PracticeRange.begin_tutorial("hero_vesper_loom")
	assert_bool(PracticeRange.is_active([])).is_true()
	assert_bool(args.has(PracticeRange.MAP)).is_true()
	assert_bool(PracticeRange.consume_tutorial()).is_true()
	assert_bool(PracticeRange.consume_tutorial()).is_false()


func test_plain_practice_does_not_request_tutorial() -> void:
	PracticeRange.begin("hero_vesper_loom")
	assert_bool(PracticeRange.consume_tutorial()).is_false()
