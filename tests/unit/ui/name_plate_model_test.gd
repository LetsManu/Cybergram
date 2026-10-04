extends GdUnitTestSuite
## W11-V1: name plate visibility rules (ally / enemy line of sight / range).

var _t: HudTuningDef


func before_test() -> void:
	_t = HudTuningDef.new()


func test_ally_always_visible_through_walls_within_ally_range() -> void:
	assert_bool(NamePlateModel.is_visible(true, false, 150.0, _t)).is_true()
	assert_bool(NamePlateModel.is_visible(true, true, _t.plate_ally_max_distance_m + 1.0, _t)).is_false()


func test_enemy_needs_line_of_sight_and_range() -> void:
	assert_bool(NamePlateModel.is_visible(false, true, 10.0, _t)).is_true()
	assert_bool(NamePlateModel.is_visible(false, false, 10.0, _t)).is_false()
	assert_bool(NamePlateModel.is_visible(false, true, _t.plate_max_distance_m + 1.0, _t)).is_false()
	assert_bool(NamePlateModel.is_visible(false, true, _t.plate_max_distance_m, _t)).is_true()


func test_mastery_count_and_fork_text() -> void:
	var b := SnapshotData.EntityState.with_slot(0, 0, 1, true)
	b = SnapshotData.EntityState.with_slot(b, 1, 2, false)
	assert_int(NamePlateModel.mastery_count(b)).is_equal(1)
	assert_str(NamePlateModel.fork_text(b)).is_equal("A* B -")
