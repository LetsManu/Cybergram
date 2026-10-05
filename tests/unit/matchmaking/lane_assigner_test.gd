extends GdUnitTestSuite
## W17-MM: lane preferences to starting lanes.

const SLOTS: Array = [&"north", &"center", &"south", &"flex", &"flex"]


func test_everyone_gets_primary_when_possible() -> void:
	var r := LaneAssigner.assign([[&"south", &"north"], [&"north", &"center"], [&"center", &"south"],
		[&"flex", &"north"], [&"flex", &"south"]], SLOTS)
	assert_array(r.lanes).is_equal([&"south", &"north", &"center", &"flex", &"flex"])
	assert_int(r.misses).is_equal(0)


func test_conflict_uses_secondary_and_fill() -> void:
	var r := LaneAssigner.assign([[&"north", &"center"], [&"north", &"south"], [&"fill"],
		[&"north", &"center"], [&"fill"]], SLOTS)
	assert_str(String(r.lanes[0])).is_equal("north")  # earlier player wins the tie
	assert_int(r.misses).is_equal(2)  # player 3 gets secondary (1), player 1 secondary (1)


func test_validation_and_no_slots() -> void:
	assert_bool(LaneAssigner.valid_prefs([&"north", &"north"])).is_false()
	assert_bool(LaneAssigner.valid_prefs([&"jungle", &"north"])).is_false()
	assert_bool(LaneAssigner.valid_prefs([&"fill"])).is_true()
	assert_bool(LaneAssigner.valid_prefs([])).is_true()
	var r := LaneAssigner.assign([[&"north", &"south"]], [])
	assert_array(r.lanes).is_equal([&""])
