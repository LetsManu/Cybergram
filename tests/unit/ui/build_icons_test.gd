extends GdUnitTestSuite
## Armory v2 build icons (items-and-armory.md §3.8 rule 7): strip layout and
## the build lookup used by the weapon panel, scoreboard and death card.


func test_has_any_is_false_for_an_empty_build() -> void:
	assert_bool(BuildIcons.has_any(SnapshotData.EntityState.new().build)).is_false()


func test_has_any_is_true_with_one_item() -> void:
	var b := SnapshotData.EntityState.new().build
	b[SnapshotData.EntityState.B_AMMO] = 44
	assert_bool(BuildIcons.has_any(b)).is_true()


func test_strip_width_adds_the_group_gap_only_with_open_slots() -> void:
	var gun := BuildIcons.strip_width(10.0, SnapshotData.EntityState.B_OPEN0)
	assert_float(gun).is_equal_approx(5 * 10.0 + 4 * 10.0 * BuildIcons.GAP_RATIO, 1e-4)
	var full := BuildIcons.strip_width(10.0)
	assert_float(full).is_equal_approx(11 * 10.0 + 10 * 10.0 * BuildIcons.GAP_RATIO + 10.0 * BuildIcons.GROUP_GAP, 1e-4)


func test_build_of_without_client_is_empty() -> void:
	assert_int(ScoreboardModel.build_of(null, 3).size()).is_equal(0)


func test_build_catalog_falls_back_to_v22() -> void:
	assert_int(ScoreboardModel.build_catalog(null).index_of(&"ember_part")).is_greater_equal(0)
